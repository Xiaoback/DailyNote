import AppKit

extension NSAttributedString.Key {
    static let noteBlockID = NSAttributedString.Key("DailyNoteBlockID")
    static let noteAutomaticStrike = NSAttributedString.Key("DailyNoteAutomaticStrike")
    static let notePointSize = NSAttributedString.Key("DailyNotePointSize")
    static let noteHighlight = NSAttributedString.Key("DailyNoteHighlight")
    static let noteMarkerKind = NSAttributedString.Key("DailyNoteMarkerKind")
    static let noteMarkerState = NSAttributedString.Key("DailyNoteMarkerState")
    static let noteMarkerPointSize = NSAttributedString.Key("DailyNoteMarkerPointSize")
    static let noteLevel = NSAttributedString.Key("DailyNoteLevel")
    static let noteCollapsed = NSAttributedString.Key("DailyNoteCollapsed")
    static let noteHasChildren = NSAttributedString.Key("DailyNoteHasChildren")
    static let noteBold = NSAttributedString.Key("DailyNoteBold")
    static let noteItalic = NSAttributedString.Key("DailyNoteItalic")
}

enum RichTextCodec {
    static let highlightColor = NSColor(srgbRed: 1, green: 0.80, blue: 0.12, alpha: 0.65)
    static func prefix(_ block: NoteBlock) -> String {
        switch block.kind { case .paragraph: return ""; case .bullet: return "• "; case .task: return block.state.symbol + " " }
    }

    static func baseAttributes(size: CGFloat, family: String = "system", level: Int = 0) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 6
        paragraph.paragraphSpacing = 9
        // Keep the disclosure gutter inside the text container so AppKit's
        // drawing clip does not hide the arrow. The view reduces its outer inset.
        paragraph.firstLineHeadIndent = 16 + CGFloat(level) * 23
        paragraph.headIndent = 16 + CGFloat(level) * 23
        paragraph.tailIndent = -16
        return [.font: NoteFonts.font(family: family, size: size), .foregroundColor: NSColor.labelColor,
                .paragraphStyle: paragraph, .noteLevel: level, .noteCollapsed: false]
    }

    static func attributed(_ blocks: [NoteBlock], size: CGFloat = 16, family: String = "system", source: [NoteBlock]? = nil) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for (index, block) in blocks.enumerated() {
            let start = result.length
            let base = baseAttributes(size: size, family: family, level: block.level)
            result.append(NSAttributedString(string: prefix(block), attributes: base))
            for run in block.runs {
                var attributes = base
                let runSize = run.pointSize.map { CGFloat(min(72, max(8, $0))) } ?? size
                attributes[.font] = NoteFonts.font(family: family, size: runSize, bold: run.bold, italic: run.italic)
                attributes[.noteBold] = run.bold
                attributes[.noteItalic] = run.italic
                if run.italic && family == "wenkai" { attributes[.obliqueness] = 0.15 }
                if let pointSize = run.pointSize { attributes[.notePointSize] = pointSize }
                if run.highlighted {
                    attributes[.noteHighlight] = true
                    attributes[.backgroundColor] = highlightColor
                    attributes[.foregroundColor] = NSColor.black
                }
                if run.strikethrough { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
                result.append(NSAttributedString(string: run.text, attributes: attributes))
            }
            if index < blocks.count - 1 { result.append(NSAttributedString(string: "\n", attributes: base)) }
            let range = NSRange(location: start, length: result.length - start)
            if range.length > 0 {
                result.addAttribute(.noteBlockID, value: block.id.uuidString, range: range)
                result.addAttribute(.noteLevel, value: block.level, range: range)
                result.addAttribute(.noteCollapsed, value: block.collapsed, range: range)
                if let markerSize = block.markerPointSize {
                    result.addAttribute(.noteMarkerPointSize, value: markerSize, range: NSRange(location: start, length: 1))
                }
                if !NoteOutline.children(of: block.id, in: source ?? blocks).isEmpty {
                    result.addAttribute(.noteHasChildren, value: true, range: NSRange(location: start, length: 1))
                }
                if block.isResolved {
                    result.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: range)
                    // Preserve the user's own strikethrough when changing a task back to pending.
                    result.enumerateAttribute(.strikethroughStyle, in: range) { value, subrange, _ in
                        if (value as? Int ?? 0) == 0 {
                            result.addAttribute(.noteAutomaticStrike, value: true, range: subrange)
                            result.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: subrange)
                        }
                    }
                }
            }
        }
        result.enumerateAttribute(.noteHighlight, in: NSRange(location: 0, length: result.length)) { value, range, _ in
            if value as? Bool == true { result.addAttribute(.foregroundColor, value: NSColor.black, range: range) }
        }
        decorateMarkers(result, size: size)
        return result
    }

    static func blocks(_ text: NSAttributedString) -> [NoteBlock] {
        guard text.length > 0 else { return [] }
        let string = text.string as NSString
        var output: [NoteBlock] = []
        var position = 0
        var used = Set<UUID>()
        while position < string.length {
            let paragraph = string.paragraphRange(for: NSRange(location: position, length: 0))
            var content = paragraph
            while content.length > 0 {
                guard let scalar = UnicodeScalar(string.character(at: NSMaxRange(content) - 1)),
                      CharacterSet.newlines.contains(scalar) else { break }
                content.length -= 1
            }
            let value = string.substring(with: content)
            var block = NoteBlock()
            if let identifier = text.attribute(.noteBlockID, at: position, effectiveRange: nil) as? String,
               let id = UUID(uuidString: identifier), !used.contains(id) { block.id = id }
            used.insert(block.id)
            block.level = text.attribute(.noteLevel, at: position, effectiveRange: nil) as? Int ?? 0
            block.collapsed = text.attribute(.noteCollapsed, at: position, effectiveRange: nil) as? Bool ?? false
            block.markerPointSize = text.attribute(.noteMarkerPointSize, at: position, effectiveRange: nil) as? Double
            var prefixLength = 0
            if value.hasPrefix("• ") { block.kind = .bullet; prefixLength = 2 }
            if let state = TaskState.atStart(of: value) {
                block.kind = .task; block.state = state; prefixLength = 2
            }
            let body = NSRange(location: content.location + prefixLength, length: max(0, content.length - prefixLength))
            text.enumerateAttributes(in: body) { attributes, range, _ in
                let font = attributes[.font] as? NSFont ?? NSFont.systemFont(ofSize: 16)
                let traits = NSFontManager.shared.traits(of: font)
                let run = TextRun(text: string.substring(with: range), bold: attributes[.noteBold] as? Bool ?? traits.contains(.boldFontMask),
                                  italic: attributes[.noteItalic] as? Bool ?? traits.contains(.italicFontMask),
                                  strikethrough: (attributes[.strikethroughStyle] as? Int ?? 0) != 0 &&
                                    !(attributes[.noteAutomaticStrike] as? Bool ?? false),
                                  pointSize: attributes[.notePointSize] as? Double,
                                  highlighted: attributes[.noteHighlight] as? Bool ?? false)
                if let last = block.runs.last, last.bold == run.bold && last.italic == run.italic && last.strikethrough == run.strikethrough && last.pointSize == run.pointSize && last.highlighted == run.highlighted {
                    block.runs[block.runs.count - 1].text += run.text
                } else { block.runs.append(run) }
            }
            output.append(block)
            position = NSMaxRange(paragraph)
        }
        if string.hasSuffix("\n") { output.append(NoteBlock()) }
        return output
    }

    static func normalizeIDs(_ storage: NSTextStorage) {
        let blocks = blocks(storage)
        let string = storage.string as NSString
        var position = 0
        for block in blocks where position < storage.length {
            let range = string.paragraphRange(for: NSRange(location: position, length: 0))
            storage.addAttribute(.noteBlockID, value: block.id.uuidString, range: range)
            position = NSMaxRange(range)
        }
    }

    static func decorateMarkers(_ text: NSMutableAttributedString, size: CGFloat) {
        let all = NSRange(location: 0, length: text.length)
        text.enumerateAttribute(.noteMarkerKind, in: all) { value, range, _ in
            if value != nil {
                text.removeAttribute(.noteMarkerKind, range: range)
                text.removeAttribute(.noteMarkerState, range: range)
                text.addAttribute(.foregroundColor, value: NSColor.labelColor, range: range)
            }
        }
        let string = text.string as NSString
        var index = 0
        while index < string.length {
            let paragraph = string.paragraphRange(for: NSRange(location: index, length: 0))
            let line = string.substring(with: paragraph)
            let state = TaskState.atStart(of: line)
            if line.hasPrefix("• ") || state != nil {
                let marker = NSRange(location: index, length: 1)
                let separator = NSRange(location: index + 1, length: 1)
                let markerSize = CGFloat(text.attribute(.noteMarkerPointSize, at: index, effectiveRange: nil) as? Double ?? Double(size))
                let font = NSFont.systemFont(ofSize: markerSize)
                let glyphWidth = (string.substring(with: marker) as NSString).size(withAttributes: [.font: font]).width
                // AppKit inherits typing attributes from the character to the
                // left of the caret. The separator must behave like body text.
                let hasBody = line.trimmingCharacters(in: .newlines).utf16.count > 2
                var bodyAttributes = text.attributes(at: hasBody ? NSMaxRange(separator) : separator.location, effectiveRange: nil)
                bodyAttributes.removeValue(forKey: .kern)
                text.setAttributes(bodyAttributes, range: separator)
                let spaceWidth = (" " as NSString).size(withAttributes: bodyAttributes).width
                let markerAdvance = max(markerSize * 0.5, markerSize * 0.82 - spaceWidth)
                text.addAttributes([.noteMarkerKind: state == nil ? "bullet" : "task",
                                    .font: font, .kern: markerAdvance - glyphWidth,
                                    .foregroundColor: NSColor.clear], range: marker)
                if let state { text.addAttribute(.noteMarkerState, value: state.rawValue, range: marker) }
            }
            index = NSMaxRange(paragraph)
        }
    }

    static func markdown(_ doc: NoteDocument) -> String {
        doc.blocks.map { block in
            var prefix = ""
            if block.kind == .bullet { prefix = "- " }
            if block.kind == .task {
                switch block.state { case .pending: prefix = "- [ ] "; case .completed: prefix = "- [x] "; case .cancelled: prefix = "- [取消] " }
            }
            return String(repeating: "  ", count: block.level) + prefix + block.runs.map { run in
                var text = run.text
                if run.bold { text = "**\(text)**" }
                if run.italic { text = "*\(text)*" }
                if run.strikethrough { text = "~~\(text)~~" }
                if run.highlighted { text = "==\(text)==" }
                return text
            }.joined()
        }.joined(separator: "\n")
    }
}

// Draw actual shapes over the semantic text prefixes. Plain copy/paste still
// carries readable symbols, and the visual circles do not depend on a font glyph.
final class NoteLayoutManager: NSLayoutManager {
    override func drawGlyphs(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        guard let storage = textStorage else {
            super.drawGlyphs(forGlyphRange: glyphsToShow, at: origin)
            return
        }
        let characters = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        // Selection foreground overrides the marker's transparent text color.
        // Skip the semantic glyph itself; its shape is drawn below. Background
        // highlighting and glyph advances remain AppKit's normal layout.
        var markerGlyphs: [NSRange] = []
        storage.enumerateAttribute(.noteMarkerKind, in: characters) { value, range, _ in
            if value != nil {
                let glyphs = self.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
                let clipped = NSIntersectionRange(glyphs, glyphsToShow)
                if clipped.length > 0 { markerGlyphs.append(clipped) }
            }
        }
        var cursor = glyphsToShow.location
        for marker in markerGlyphs {
            if marker.location > cursor {
                super.drawGlyphs(forGlyphRange: NSRange(location: cursor, length: marker.location - cursor), at: origin)
            }
            cursor = NSMaxRange(marker)
        }
        if cursor < NSMaxRange(glyphsToShow) {
            super.drawGlyphs(forGlyphRange: NSRange(location: cursor, length: NSMaxRange(glyphsToShow) - cursor), at: origin)
        }
        storage.enumerateAttribute(.noteMarkerKind, in: characters) { value, range, _ in
            guard let kind = value as? String, range.length > 0 else { return }
            let glyph = self.glyphIndexForCharacter(at: range.location)
            let line = self.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            let location = self.location(forGlyphAt: glyph)
            let font = storage.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont ?? NSFont.systemFont(ofSize: 20)
            let diameter: CGFloat = font.pointSize * (kind == "bullet" ? 0.24 : 0.55)
            let center = NSPoint(x: origin.x + line.minX + location.x + font.pointSize * 0.30,
                                 y: origin.y + line.minY + location.y - font.pointSize * 0.35)
            let rect = NSRect(x: center.x - diameter / 2, y: center.y - diameter / 2, width: diameter, height: diameter)
            let level = storage.attribute(.noteLevel, at: range.location, effectiveRange: nil) as? Int ?? 0
            let circle = level >= 2 ? NSBezierPath(rect: rect) : NSBezierPath(ovalIn: rect)
            if kind == "bullet" {
                NSColor.labelColor.setFill()
                circle.fill()
                return
            }
            let raw = storage.attribute(.noteMarkerState, at: range.location, effectiveRange: nil) as? String
            let state = raw.flatMap(TaskState.init(rawValue:)) ?? .pending
            circle.lineWidth = max(0.8, font.pointSize * 0.06)
            if state == .completed {
                NSColor.black.setFill()
                circle.fill()
                NSColor.secondaryLabelColor.setStroke()
                circle.lineWidth = 0.6
                circle.stroke()
                let tick = NSBezierPath()
                tick.move(to: NSPoint(x: rect.minX + diameter * 0.25, y: rect.minY + diameter * 0.51))
                tick.line(to: NSPoint(x: rect.minX + diameter * 0.43, y: rect.minY + diameter * 0.69))
                tick.line(to: NSPoint(x: rect.minX + diameter * 0.76, y: rect.minY + diameter * 0.32))
                tick.lineWidth = max(0.85, font.pointSize * 0.06)
                tick.lineCapStyle = .round
                tick.lineJoinStyle = .round
                NSColor.white.setStroke()
                tick.stroke()
            } else {
                (state == .pending ? NSColor.labelColor : NSColor.secondaryLabelColor).setStroke()
                circle.stroke()
                if state == .cancelled {
                    let cross = NSBezierPath()
                    cross.move(to: NSPoint(x: rect.minX + diameter * 0.33, y: rect.minY + diameter * 0.33))
                    cross.line(to: NSPoint(x: rect.minX + diameter * 0.67, y: rect.minY + diameter * 0.67))
                    cross.move(to: NSPoint(x: rect.minX + diameter * 0.67, y: rect.minY + diameter * 0.33))
                    cross.line(to: NSPoint(x: rect.minX + diameter * 0.33, y: rect.minY + diameter * 0.67))
                    cross.lineWidth = max(0.8, font.pointSize * 0.055)
                    cross.stroke()
                }
            }
        }
        storage.enumerateAttribute(.noteHasChildren, in: characters) { value, range, _ in
            guard value as? Bool == true else { return }
            let glyph = self.glyphIndexForCharacter(at: range.location)
            let line = self.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            let location = self.location(forGlyphAt: glyph)
            let collapsed = storage.attribute(.noteCollapsed, at: range.location, effectiveRange: nil) as? Bool ?? false
            let x = origin.x + line.minX + location.x - 14
            let y = origin.y + line.minY + location.y - 6
            let path = NSBezierPath()
            if collapsed {
                path.move(to: NSPoint(x: x - 2, y: y - 3)); path.line(to: NSPoint(x: x + 1, y: y)); path.line(to: NSPoint(x: x - 2, y: y + 3))
            } else {
                path.move(to: NSPoint(x: x - 3, y: y - 1)); path.line(to: NSPoint(x: x, y: y + 2)); path.line(to: NSPoint(x: x + 3, y: y - 1))
            }
            path.lineWidth = 1.2; path.lineCapStyle = .round; path.lineJoinStyle = .round
            NSColor.secondaryLabelColor.setStroke(); path.stroke()
        }
    }
}
