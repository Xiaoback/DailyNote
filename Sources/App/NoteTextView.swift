import AppKit
import SwiftUI

enum EditorAction { case bold, italic, strike, highlight, larger, smaller, bullet, task, state, indent, outdent, fold, schedule, undo, redo }

@MainActor
final class EditorBridge: ObservableObject {
    weak var textView: NoteTextView?
    func perform(_ action: EditorAction) {
        let focused = (NSApp.keyWindow?.firstResponder as? NoteTextView)
            ?? NoteTextView.focusedEditor.flatMap { $0.window?.isVisible == true ? $0 : nil }
        (focused ?? textView)?.perform(action)
    }
}

final class NoteTextView: NSTextView {
    static weak var focusedEditor: NoteTextView?
    var noteFontSize: CGFloat = 16
    var noteFontFamily = "system"
    var outlineSource: [NoteBlock] = []

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { Self.focusedEditor = self }
        return accepted
    }

    @discardableResult func focus(blockID: UUID) -> Bool {
        guard let storage = textStorage, storage.length > 0 else { return false }
        var position: Int?
        storage.enumerateAttribute(.noteBlockID, in: NSRange(location: 0, length: storage.length)) { value, range, stop in
            guard value as? String == blockID.uuidString else { return }
            var marker = NSRange()
            let kind = storage.attribute(.noteMarkerKind, at: range.location, effectiveRange: &marker)
            var cursor = kind == nil ? range.location : NSMaxRange(marker)
            if kind != nil, cursor < storage.length, (storage.string as NSString).character(at: cursor) == 32 {
                cursor += 1
            }
            position = cursor
            stop.pointee = true
        }
        guard let position else { return false }
        let range = NSRange(location: min(position, storage.length), length: 0)
        setSelectedRange(range)
        scrollRangeToVisible(range)
        return true
    }

    override init(frame frameRect: NSRect, textContainer: NSTextContainer? = nil) {
        if let textContainer {
            super.init(frame: frameRect, textContainer: textContainer)
        } else {
            let storage = NSTextStorage()
            let layout = NoteLayoutManager()
            let container = NSTextContainer(containerSize: NSSize(width: frameRect.width, height: CGFloat.greatestFiniteMagnitude))
            storage.addLayoutManager(layout)
            layout.addTextContainer(container)
            super.init(frame: frameRect, textContainer: container)
        }
    }

    required init?(coder: NSCoder) { super.init(coder: coder) }

    func perform(_ action: EditorAction) {
        window?.makeFirstResponder(self)
        switch action {
        case .bold: toggleTrait(.boldFontMask)
        case .italic: toggleTrait(.italicFontMask)
        case .strike: toggleStrike()
        case .highlight: toggleHighlight()
        case .larger: adjustPointSize(by: 1)
        case .smaller: adjustPointSize(by: -1)
        case .bullet: changeParagraphs(to: .bullet)
        case .task: changeParagraphs(to: .task)
        case .state: cycleCurrentTask()
        case .indent: changeLevel(by: 1)
        case .outdent: changeLevel(by: -1)
        case .fold: toggleCurrentFold()
        case .schedule: insertSchedule()
        case .undo: undoManager?.undo()
        case .redo: undoManager?.redo()
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if modifiers.contains(.command), !modifiers.contains(.option), !modifiers.contains(.control) {
            let key = event.charactersIgnoringModifiers ?? ""
            if key == "+" || key == "=" { perform(.larger); return true }
            if key == "-" || key == "−" { perform(.smaller); return true }
        }
        return super.performKeyEquivalent(with: event)
    }

    private func adjustPointSize(by delta: CGFloat) {
        let selection = selectedRange()
        if selection.length == 0 {
            let font = typingAttributes[.font] as? NSFont ?? NSFont.systemFont(ofSize: noteFontSize)
            let size = min(72, max(8, font.pointSize + delta))
            typingAttributes[.font] = NSFontManager.shared.convert(font, toSize: size)
            typingAttributes[.notePointSize] = Double(size)
            return
        }
        let copy = NSMutableAttributedString(attributedString: attributedString())
        copy.enumerateAttributes(in: selection) { attributes, range, _ in
            if attributes[.noteMarkerKind] != nil {
                let old = attributes[.noteMarkerPointSize] as? Double ?? Double(noteFontSize)
                copy.addAttribute(.noteMarkerPointSize, value: min(72, max(8, old + Double(delta))), range: range)
                return
            }
            let font = attributes[.font] as? NSFont ?? NSFont.systemFont(ofSize: noteFontSize)
            let size = min(72, max(8, font.pointSize + delta))
            copy.addAttributes([.font: NSFontManager.shared.convert(font, toSize: size), .notePointSize: Double(size)], range: range)
        }
        RichTextCodec.decorateMarkers(copy, size: noteFontSize)
        replaceDocument(copy, selection: selection, name: delta > 0 ? "放大文字" : "缩小文字")
    }

    private func toggleHighlight() {
        let selection = selectedRange()
        if selection.length == 0 {
            if typingAttributes[.noteHighlight] as? Bool == true {
                typingAttributes.removeValue(forKey: .noteHighlight)
                typingAttributes.removeValue(forKey: .backgroundColor)
                typingAttributes[.foregroundColor] = NSColor.labelColor
            } else {
                typingAttributes[.noteHighlight] = true
                typingAttributes[.backgroundColor] = RichTextCodec.highlightColor
                typingAttributes[.foregroundColor] = NSColor.black
            }
            return
        }
        let copy = NSMutableAttributedString(attributedString: attributedString())
        let remove = copy.attribute(.noteHighlight, at: selection.location, effectiveRange: nil) as? Bool ?? false
        if remove {
            copy.removeAttribute(.noteHighlight, range: selection)
            copy.removeAttribute(.backgroundColor, range: selection)
            copy.addAttribute(.foregroundColor, value: NSColor.labelColor, range: selection)
        } else {
            copy.addAttributes([.noteHighlight: true, .backgroundColor: RichTextCodec.highlightColor, .foregroundColor: NSColor.black], range: selection)
        }
        RichTextCodec.decorateMarkers(copy, size: noteFontSize)
        replaceDocument(copy, selection: selection, name: "文字高亮")
    }

    private func replaceDocument(_ value: NSAttributedString, selection: NSRange, name: String, source: [NoteBlock]? = nil) {
        guard let storage = textStorage else { return }
        let old = NSAttributedString(attributedString: storage)
        let oldSelection = selectedRange()
        let oldSource = outlineSource
        let manager = undoManager
        let createsGroup = manager != nil && manager?.isUndoing == false && manager?.isRedoing == false
        if createsGroup { manager?.beginUndoGrouping() }
        defer { if createsGroup { manager?.endUndoGrouping() } }
        manager?.registerUndo(withTarget: self) { view in
            view.replaceDocument(old, selection: oldSelection, name: name, source: oldSource)
        }
        manager?.setActionName(name)
        outlineSource = source ?? NoteOutline.merging(RichTextCodec.blocks(value), into: outlineSource)
        storage.setAttributedString(value)
        setSelectedRange(NSRange(location: min(selection.location, storage.length), length: min(selection.length, max(0, storage.length - selection.location))))
        typingAttributes = RichTextCodec.baseAttributes(size: noteFontSize, family: noteFontFamily)
        didChangeText()
    }

    private func toggleTrait(_ trait: NSFontTraitMask) {
        let range = selectedRange()
        if range.length == 0 {
            let font = typingAttributes[.font] as? NSFont ?? NSFont.systemFont(ofSize: noteFontSize)
            let key: NSAttributedString.Key = trait == .boldFontMask ? .noteBold : .noteItalic
            let has = typingAttributes[key] as? Bool ?? NSFontManager.shared.traits(of: font).contains(trait)
            typingAttributes[key] = !has
            let bold = typingAttributes[.noteBold] as? Bool ?? false
            let italic = typingAttributes[.noteItalic] as? Bool ?? false
            typingAttributes[.font] = NoteFonts.font(family: noteFontFamily, size: font.pointSize, bold: bold, italic: italic)
            typingAttributes[.obliqueness] = italic && noteFontFamily == "wenkai" ? 0.15 : 0
            return
        }
        let copy = NSMutableAttributedString(attributedString: attributedString())
        let first = copy.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont ?? NSFont.systemFont(ofSize: noteFontSize)
        let key: NSAttributedString.Key = trait == .boldFontMask ? .noteBold : .noteItalic
        let remove = copy.attribute(key, at: range.location, effectiveRange: nil) as? Bool ?? NSFontManager.shared.traits(of: first).contains(trait)
        copy.enumerateAttributes(in: range) { attributes, subrange, _ in
            let font = attributes[.font] as? NSFont ?? NSFont.systemFont(ofSize: noteFontSize)
            let traits = NSFontManager.shared.traits(of: font)
            let bold = trait == .boldFontMask ? !remove : (attributes[.noteBold] as? Bool ?? traits.contains(.boldFontMask))
            let italic = trait == .italicFontMask ? !remove : (attributes[.noteItalic] as? Bool ?? traits.contains(.italicFontMask))
            copy.addAttributes([.font: NoteFonts.font(family: noteFontFamily, size: font.pointSize, bold: bold, italic: italic),
                                .noteBold: bold, .noteItalic: italic, .obliqueness: italic && noteFontFamily == "wenkai" ? 0.15 : 0], range: subrange)
        }
        RichTextCodec.decorateMarkers(copy, size: noteFontSize)
        replaceDocument(copy, selection: range, name: "文字格式")
    }

    private func toggleStrike() {
        let range = selectedRange()
        if range.length == 0 {
            let enabled = (typingAttributes[.strikethroughStyle] as? Int ?? 0) != 0
            typingAttributes[.strikethroughStyle] = enabled ? 0 : NSUnderlineStyle.single.rawValue
            typingAttributes.removeValue(forKey: .noteAutomaticStrike)
            return
        }
        let copy = NSMutableAttributedString(attributedString: attributedString())
        let remove = (copy.attribute(.strikethroughStyle, at: range.location, effectiveRange: nil) as? Int ?? 0) != 0
        copy.addAttribute(.strikethroughStyle, value: remove ? 0 : NSUnderlineStyle.single.rawValue, range: range)
        copy.removeAttribute(.noteAutomaticStrike, range: range)
        replaceDocument(copy, selection: range, name: "删除线")
    }

    private func selectedBlockIndices(_ blocks: [NoteBlock]) -> [Int] {
        let selection = selectedRange()
        var start = 0
        var indices: [Int] = []
        for (i, block) in blocks.enumerated() {
            let length = ((RichTextCodec.prefix(block) + block.text) as NSString).length
            let end = start + length
            if selection.length == 0 ? (selection.location >= start && selection.location <= end) : (selection.location <= end && NSMaxRange(selection) > start) {
                indices.append(i)
            }
            start = end + 1
        }
        return indices
    }

    private func changeParagraphs(to kind: BlockKind) {
        var blocks = RichTextCodec.blocks(attributedString())
        if blocks.isEmpty { blocks = [NoteBlock()] }
        let indices = selectedBlockIndices(blocks)
        let remove = indices.allSatisfy { blocks[$0].kind == kind }
        let oldLength = attributedString().length
        for index in indices {
            blocks[index].kind = remove ? .paragraph : kind
            blocks[index].state = .pending
        }
        let full = NoteOutline.merging(blocks, into: outlineSource)
        let copy = RichTextCodec.attributed(NoteOutline.visible(full), size: noteFontSize, family: noteFontFamily, source: full)
        let location = max(0, min(copy.length, selectedRange().location + copy.length - oldLength))
        replaceDocument(copy, selection: NSRange(location: location, length: 0), name: kind == .task ? "待办事项" : "项目符号", source: full)
    }

    private func cycleCurrentTask() {
        var blocks = RichTextCodec.blocks(attributedString())
        let indices = selectedBlockIndices(blocks)
        guard indices.contains(where: { blocks[$0].kind == .task }) else { return }
        for i in indices where blocks[i].kind == .task { blocks[i].state = blocks[i].state.next }
        show(NoteOutline.merging(blocks, into: outlineSource), selection: selectedRange(), name: "事项状态")
    }

    private func show(_ full: [NoteBlock], selection: NSRange, name: String) {
        let completed = NoteOutline.completingParents(full)
        let text = RichTextCodec.attributed(NoteOutline.visible(completed), size: noteFontSize, family: noteFontFamily, source: completed)
        replaceDocument(text, selection: selection, name: name, source: completed)
    }

    private func changeLevel(by delta: Int) {
        let visible = RichTextCodec.blocks(attributedString())
        let ids = Set(selectedBlockIndices(visible).map { visible[$0].id })
        var full = NoteOutline.merging(visible, into: outlineSource)
        // Move an entire subtree once, even if descendants are also selected.
        var index = 0
        while index < full.count {
            guard ids.contains(full[index].id) else { index += 1; continue }
            let oldLevel = full[index].level
            var end = index + 1
            while end < full.count && full[end].level > oldLevel { end += 1 }
            let target = delta > 0 ? min(oldLevel + 1, index > 0 ? full[index - 1].level + 1 : 0) : max(0, oldLevel - 1)
            let shift = target - oldLevel
            if shift != 0 {
                for child in index..<end { full[child].level += shift }
                // An indented subtree must remain visible inside its new parent.
                if target > 0, let parent = full[..<index].lastIndex(where: { $0.level < target }) {
                    full[parent].collapsed = false
                }
            }
            index = end
        }
        show(full, selection: selectedRange(), name: delta > 0 ? "增加缩进" : "减少缩进")
    }

    private func toggleCurrentFold() {
        let visible = RichTextCodec.blocks(attributedString())
        guard let index = selectedBlockIndices(visible).first else { return }
        toggleFold(id: visible[index].id)
    }

    func toggleFold(id: UUID) {
        let full = NoteOutline.merging(RichTextCodec.blocks(attributedString()), into: outlineSource)
        guard let index = full.firstIndex(where: { $0.id == id }), !NoteOutline.children(of: id, in: full).isEmpty else { return }
        var changed = full
        changed[index].collapsed.toggle()
        let preceding = NoteOutline.visible(changed).prefix { $0.id != id }
        let location = preceding.reduce(0) { $0 + (RichTextCodec.prefix($1) + $1.text).utf16.count + 1 }
        show(changed, selection: NSRange(location: location, length: 0), name: changed[index].collapsed ? "折叠项目" : "展开项目")
    }

    func insertTemplate(_ template: NoteTemplate) {
        guard isEditable, !hasMarkedText() else { return }
        var full = NoteOutline.merging(RichTextCodec.blocks(attributedString()), into: outlineSource)
        if full.last?.text.isEmpty == true && full.last?.kind == .paragraph { full.removeLast() }
        let location = full.reduce(0) { $0 + (RichTextCodec.prefix($1) + $1.text).utf16.count + 1 }
        full.append(contentsOf: template.instantiate())
        show(full, selection: NSRange(location: location, length: 0), name: "插入模板")
    }

    private func insertSchedule() { insertTemplate(.dailyGroups) }

    override func insertTab(_ sender: Any?) { changeLevel(by: 1) }
    override func insertBacktab(_ sender: Any?) { changeLevel(by: -1) }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let index = characterIndexForInsertion(at: point)
        let string = self.string as NSString
        if string.length > 0, index < string.length {
            let paragraph = string.paragraphRange(for: NSRange(location: index, length: 0))
            let line = string.substring(with: paragraph)
            if textStorage?.attribute(.noteHasChildren, at: paragraph.location, effectiveRange: nil) as? Bool == true,
               let layout = layoutManager, let idString = textStorage?.attribute(.noteBlockID, at: paragraph.location, effectiveRange: nil) as? String,
               let id = UUID(uuidString: idString) {
                let glyph = layout.glyphIndexForCharacter(at: paragraph.location)
                let fragment = layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
                let location = layout.location(forGlyphAt: glyph)
                let hit = NSRect(x: textContainerOrigin.x + fragment.minX + location.x - 24,
                                 y: textContainerOrigin.y + fragment.minY + location.y - 16, width: 20, height: 22)
                if hit.contains(point) { toggleFold(id: id); return }
            }
            if TaskState.atStart(of: line) != nil, index <= paragraph.location + 1 {
                setSelectedRange(NSRange(location: paragraph.location, length: 0))
                cycleCurrentTask()
                return
            }
        }
        super.mouseDown(with: event)
    }

    override func insertNewline(_ sender: Any?) {
        if selectedRange().length > 0, !hasMarkedText() {
            setSelectedRange(wholePrefixDeletion(selectedRange()))
        }
        let content = string as NSString
        let caret = selectedRange().location
        guard content.length > 0 else { super.insertNewline(sender); return }
        let range = content.paragraphRange(for: NSRange(location: min(caret, content.length), length: 0))
        let line = content.substring(with: range).trimmingCharacters(in: .newlines)
        let level = textStorage?.attribute(.noteLevel, at: min(range.location, max(0, content.length - 1)), effectiveRange: nil) as? Int ?? 0
        let isTask = TaskState.atStart(of: line) != nil
        let prefix = isTask ? "○ " : (line.hasPrefix("• ") ? "• " : "")
        guard !prefix.isEmpty else {
            super.insertNewline(sender)
            typingAttributes = RichTextCodec.baseAttributes(size: noteFontSize, family: noteFontFamily, level: level)
            return
        }
        // The marker and its separator are one editing unit. Splitting inside
        // that unit otherwise leaves an ordinary, full-size circle in the body.
        if selectedRange().length == 0, caret <= range.location + 2, line.count > 2 {
            var attributes = RichTextCodec.baseAttributes(size: noteFontSize, family: noteFontFamily, level: level)
            attributes[.noteBlockID] = UUID().uuidString
            insertText(NSAttributedString(string: prefix + "\n", attributes: attributes),
                       replacementRange: NSRange(location: range.location, length: 0))
            setSelectedRange(NSRange(location: range.location + (prefix as NSString).length + 3, length: 0))
            typingAttributes = RichTextCodec.baseAttributes(size: noteFontSize, family: noteFontFamily, level: level)
            return
        }
        if line.count == 2 {
            insertText("", replacementRange: NSRange(location: range.location, length: 2))
        } else {
            super.insertNewline(sender)
            typingAttributes = RichTextCodec.baseAttributes(size: noteFontSize, family: noteFontFamily, level: level)
            insertText(prefix, replacementRange: selectedRange())
        }
    }

    // Expand deletion of any part of a list prefix to include its separator.
    // Preserve attributed body text and let NSTextView register native undo.
    private func wholePrefixDeletion(_ selection: NSRange) -> NSRange {
        let content = string as NSString
        var result = selection
        var position = 0
        while position < content.length {
            let paragraph = content.paragraphRange(for: NSRange(location: position, length: 0))
            let line = content.substring(with: paragraph)
            if line.hasPrefix("• ") || TaskState.atStart(of: line) != nil {
                let prefix = NSRange(location: position, length: 2)
                if NSIntersectionRange(selection, prefix).length > 0 { result = NSUnionRange(result, prefix) }
            }
            position = NSMaxRange(paragraph)
        }
        return result
    }

    override func deleteBackward(_ sender: Any?) {
        guard !hasMarkedText() else { super.deleteBackward(sender); return }
        let selection = selectedRange()
        let deletion = selection.length > 0 ? selection : NSRange(location: max(0, selection.location - 1), length: selection.location > 0 ? 1 : 0)
        var expanded = wholePrefixDeletion(deletion)
        // Joining lines must not move a second semantic marker into the body.
        if selection.length == 0, selection.location > 0, (string as NSString).character(at: selection.location - 1) == 10 {
            let tail = (string as NSString).substring(from: selection.location)
            if tail.hasPrefix("• ") || TaskState.atStart(of: tail) != nil {
                expanded = NSRange(location: deletion.location, length: 3)
            }
        }
        if expanded != deletion { insertText("", replacementRange: expanded) }
        else { super.deleteBackward(sender) }
    }

    override func deleteForward(_ sender: Any?) {
        guard !hasMarkedText() else { super.deleteForward(sender); return }
        let selection = selectedRange()
        let deletion = selection.length > 0 ? selection : NSRange(location: selection.location, length: selection.location < (string as NSString).length ? 1 : 0)
        var expanded = wholePrefixDeletion(deletion)
        if selection.length == 0, deletion.length == 1, (string as NSString).character(at: deletion.location) == 10 {
            let tail = (string as NSString).substring(from: NSMaxRange(deletion))
            if tail.hasPrefix("• ") || TaskState.atStart(of: tail) != nil {
                expanded = NSRange(location: deletion.location, length: 3)
            }
        }
        if expanded != deletion { insertText("", replacementRange: expanded) }
        else { super.deleteForward(sender) }
    }

    override func paste(_ sender: Any?) {
        // Keep the document's supported formatting, while dropping external fonts,
        // images and links that do not have a portable representation in the widget.
        let board = NSPasteboard.general
        if let rtf = board.data(forType: .rtf),
           let value = try? NSAttributedString(data: rtf, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil) {
            let clean = RichTextCodec.attributed(RichTextCodec.blocks(value), size: noteFontSize, family: noteFontFamily)
            insertText(clean, replacementRange: selectedRange())
        } else if let plain = board.string(forType: .string) {
            insertText(plain, replacementRange: selectedRange())
        }
    }
}

struct RichNoteEditor: NSViewRepresentable {
    @ObservedObject var model: NoteViewModel
    let bridge: EditorBridge

    func makeCoordinator() -> Coordinator { Coordinator(model) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        let view = NoteTextView(frame: .zero)
        view.isRichText = true
        view.importsGraphics = false
        view.allowsUndo = true
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false
        view.isAutomaticTextReplacementEnabled = true
        view.isContinuousSpellCheckingEnabled = false
        view.drawsBackground = false
        view.isVerticallyResizable = true
        view.isHorizontallyResizable = false
        view.autoresizingMask = [.width]
        view.textContainerInset = NSSize(width: 8, height: 24)
        view.textContainer?.widthTracksTextView = true
        view.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        view.minSize = NSSize(width: 0, height: 0)
        view.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        view.delegate = context.coordinator
        view.setAccessibilityLabel("便笺正文")
        scroll.documentView = view
        bridge.textView = view
        context.coordinator.textView = view
        context.coordinator.apply(model)
        return scroll
    }
    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.model = model
        context.coordinator.apply(model)
    }
    @MainActor final class Coordinator: NSObject, NSTextViewDelegate {
        var model: NoteViewModel
        weak var textView: NoteTextView?
        var appliedVersion = -1
        var applying = false
        init(_ model: NoteViewModel) { self.model = model }
        func apply(_ model: NoteViewModel) {
            guard appliedVersion != model.editorVersion, let view = textView else { return }
            // Never replace marked text while an input method is composing Chinese.
            guard !view.hasMarkedText() else { return }
            applying = true
            let dayChanged = view.identifier?.rawValue != model.document.day
            let selection = dayChanged ? NSRange(location: 0, length: 0) : view.selectedRange()
            let attributed = RichTextCodec.attributed(NoteOutline.visible(model.document.blocks), size: model.fontSize, family: model.fontFamily, source: model.document.blocks)
            let textChanged = view.string != attributed.string
            view.noteFontSize = model.fontSize
            view.noteFontFamily = model.fontFamily
            view.outlineSource = model.document.blocks
            view.textStorage?.setAttributedString(attributed)
            view.typingAttributes = RichTextCodec.baseAttributes(size: model.fontSize, family: model.fontFamily)
            view.setSelectedRange(NSRange(location: min(selection.location, view.string.utf16.count), length: 0))
            view.isEditable = !model.loadFailed
            if dayChanged || textChanged { view.undoManager?.removeAllActions() }
            view.identifier = NSUserInterfaceItemIdentifier(model.document.day)
            appliedVersion = model.editorVersion
            applying = false
        }
        func textDidChange(_ notification: Notification) {
            guard !applying, let view = textView, !view.hasMarkedText(), let storage = view.textStorage else { return }
            RichTextCodec.normalizeIDs(storage)
            RichTextCodec.decorateMarkers(storage, size: view.noteFontSize)
            let visible = RichTextCodec.blocks(storage)
            let merged = NoteOutline.merging(visible, into: view.outlineSource)
            let full = NoteOutline.completingParents(merged)
            if full != merged {
                let selection = view.selectedRange()
                let typing = view.typingAttributes
                applying = true
                storage.setAttributedString(RichTextCodec.attributed(NoteOutline.visible(full), size: view.noteFontSize, family: view.noteFontFamily, source: full))
                view.setSelectedRange(selection)
                view.typingAttributes = typing
                applying = false
            }
            view.outlineSource = full
            model.edited(full)
            // Keep the active editor's selection, typing attributes and undo stack.
            // Sibling editors observe the new model version and refresh their text.
            if NoteOutline.visible(full).map(\.id) == visible.map(\.id) {
                appliedVersion = model.editorVersion
            }
        }
    }
}
