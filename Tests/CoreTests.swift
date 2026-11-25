import AppKit
import Foundation

struct CheckFailure: Error, CustomStringConvertible { let description: String }

@main
struct CoreTests {
    static var count = 0
    static func check(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        guard try condition() else { throw CheckFailure(description: message) }
        count += 1
        print("PASS \(message)")
    }

    @MainActor static func main() throws {
        let arguments = CommandLine.arguments
        if arguments.count > 1 && arguments[1] == "--worker" {
            let store = try NoteStore(root: URL(fileURLWithPath: arguments[2]))
            try store.setTask(day: arguments[3], id: UUID(uuidString: arguments[4])!, state: TaskState(rawValue: arguments[5])!)
            return
        }
        _ = NSApplication.shared
        NSSetUncaughtExceptionHandler { exception in
            fputs("AppKit exception: \(exception.name.rawValue): \(exception.reason ?? "")\n", stderr)
        }
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("DailyNoteTests-\(UUID().uuidString)")
        let store = try NoteStore(root: root)
        defer { try? FileManager.default.removeItem(at: root) }
        let day = "2026-10-28"
        try check(DayKey.isValid(day), "valid local date")
        try check(!DayKey.isValid("2026-02-30") && !DayKey.isValid("../../tmp/x"), "reject impossible dates and path traversal")
        let cornerScreens = [CGRect(x: 0, y: 0, width: 1440, height: 900), CGRect(x: -1920, y: 0, width: 1920, height: 1080)]
        try check(HotCornerState.isTopRight(CGPoint(x: 1439, y: 899), screens: cornerScreens), "hot corner recognizes the physical top-right corner")
        try check(HotCornerState.isTopRight(CGPoint(x: -1, y: 1079), screens: cornerScreens), "hot corner supports an external display with negative coordinates")
        try check(!HotCornerState.isTopRight(CGPoint(x: 1430, y: 890), screens: cornerScreens) && !HotCornerState.isTopRight(CGPoint(x: 1439, y: 1), screens: cornerScreens), "normal menu-bar and bottom-right positions do not activate the corner")
        var corner = HotCornerState()
        try check(!corner.update(inside: true, allowed: true, now: 0) && !corner.update(inside: true, allowed: true, now: 1), "installing while the pointer is in the corner does not open a panel")
        _ = corner.update(inside: false, allowed: true, now: 1.1)
        try check(!corner.update(inside: true, allowed: true, now: 1.2) && !corner.update(inside: true, allowed: true, now: 1.59), "brief corner visits do not activate the panel")
        try check(corner.update(inside: true, allowed: true, now: 1.61), "a continuous 0.4-second corner dwell activates the panel")
        try check(!corner.update(inside: true, allowed: true, now: 5), "remaining in the corner never repeatedly activates the panel")
        _ = corner.update(inside: false, allowed: true, now: 5.1)
        _ = corner.update(inside: true, allowed: true, now: 5.2)
        _ = corner.update(inside: false, allowed: true, now: 5.4)
        _ = corner.update(inside: true, allowed: true, now: 5.5)
        try check(!corner.update(inside: true, allowed: true, now: 5.89) && corner.update(inside: true, allowed: true, now: 5.91), "leaving and re-entering restarts the full dwell interval")
        _ = corner.update(inside: false, allowed: true, now: 6)
        _ = corner.update(inside: true, allowed: false, now: 6.1)
        try check(!corner.update(inside: true, allowed: true, now: 7), "ending a drag in the corner does not accidentally activate the panel")
        _ = corner.update(inside: false, allowed: true, now: 7.1)
        _ = corner.update(inside: true, allowed: true, now: 7.2)
        try check(corner.update(inside: true, allowed: true, now: 7.61), "the corner works again after leaving a suppressed activation")
        corner.reset()
        try check(!corner.update(inside: true, allowed: true, now: 10), "wake and re-enable require leaving the corner before activation")
        try check(HotCornerState.isTopRight(CGPoint(x: 1434, y: 895), screens: cornerScreens), "corner activation has an eight-point tolerance")
        try check(HotCornerState.appKitPoint(fromQuartz: CGPoint(x: 1439, y: 1), primaryScreen: cornerScreens[0]) == CGPoint(x: 1439, y: 899), "event coordinates convert from Quartz to AppKit without a scale mismatch")
        var eventCorner = HotCornerState()
        _ = eventCorner.updateScreens(cornerScreens)
        _ = eventCorner.update(inside: false, allowed: true, now: 0)
        _ = eventCorner.update(inside: true, allowed: true, now: 0.01)
        try check(abs((eventCorner.remainingDwell(at: 0.21) ?? 0) - 0.2) < 0.001, "event entry exposes the remaining continuous dwell time")
        try check(!eventCorner.updateScreens(cornerScreens) && eventCorner.update(inside: true, allowed: true, now: 0.42), "unrelated screen-parameter notifications cannot reset an in-progress dwell")
        try check(eventCorner.remainingDwell(at: 0.43) == nil, "a fired entry has no outstanding dwell deadline")
        _ = eventCorner.update(inside: false, allowed: true, now: 0.431)
        _ = eventCorner.update(inside: true, allowed: true, now: 0.432)
        try check(eventCorner.update(inside: true, allowed: true, now: 0.85), "even a very fast exit and return can re-arm through pointer events")
        try check(eventCorner.updateScreens([CGRect(x: 0, y: 0, width: 1920, height: 1080)])
                  && !eventCorner.update(inside: true, allowed: true, now: 2), "real display changes still require leaving the corner before re-arming")
        var hover = HoverDismissState()
        try check(!hover.shouldHide(insidePanel: false, insideOpeningCorner: true, busy: false, now: 0)
                  && !hover.shouldHide(insidePanel: false, insideOpeningCorner: true, busy: false, now: 10), "hot-corner panel stays open while the pointer remains in its opening corner")
        try check(!hover.shouldHide(insidePanel: false, insideOpeningCorner: false, busy: false, now: 10.1)
                  && !hover.shouldHide(insidePanel: false, insideOpeningCorner: false, busy: false, now: 10.8), "pointer gets time to travel from the corner to the inset panel")
        try check(!hover.shouldHide(insidePanel: true, insideOpeningCorner: false, busy: false, now: 10.9)
                  && !hover.shouldHide(insidePanel: true, insideOpeningCorner: false, busy: false, now: 100), "pointer inside the panel keeps it visible indefinitely")
        try check(!hover.shouldHide(insidePanel: false, insideOpeningCorner: false, busy: false, now: 101)
                  && !hover.shouldHide(insidePanel: false, insideOpeningCorner: false, busy: false, now: 101.15)
                  && hover.shouldHide(insidePanel: false, insideOpeningCorner: false, busy: false, now: 101.25), "leaving an entered panel hides it after the short edge delay")
        var edgeHover = HoverDismissState()
        _ = edgeHover.shouldHide(insidePanel: true, insideOpeningCorner: false, busy: false, now: 0)
        _ = edgeHover.shouldHide(insidePanel: false, insideOpeningCorner: false, busy: false, now: 1)
        try check(!edgeHover.shouldHide(insidePanel: true, insideOpeningCorner: false, busy: false, now: 1.1)
                  && !edgeHover.shouldHide(insidePanel: true, insideOpeningCorner: false, busy: false, now: 2), "returning across the panel edge cancels pending dismissal")
        try check(!edgeHover.shouldHide(insidePanel: false, insideOpeningCorner: false, busy: true, now: 3)
                  && !edgeHover.shouldHide(insidePanel: false, insideOpeningCorner: false, busy: true, now: 20), "menus, popovers, dragging and IME composition pause hover dismissal")
        try check(!edgeHover.shouldHide(insidePanel: false, insideOpeningCorner: false, busy: false, now: 20.1)
                  && edgeHover.shouldHide(insidePanel: false, insideOpeningCorner: false, busy: false, now: 20.4), "hover dismissal resumes after an accessory interaction ends")
        var abandonedHover = HoverDismissState()
        _ = abandonedHover.shouldHide(insidePanel: false, insideOpeningCorner: false, busy: false, now: 0)
        try check(abandonedHover.shouldHide(insidePanel: false, insideOpeningCorner: false, busy: false, now: 1.1), "abandoning the corner without entering the panel also closes it")
        let linkedBlock = UUID()
        let linkedURL = NoteDeepLink.quick(day: "2026-11-02", blockID: linkedBlock)
        try check(NoteDeepLink.parse(linkedURL) == NoteDeepLink(day: "2026-11-02", blockID: linkedBlock, destination: .quick), "widget link preserves the selected day and paragraph")
        try check(NoteDeepLink.parse(URL(string: "daily-note://today?day=2026-10-29")!)?.destination == .quick, "previous widget links also open the right editor")
        try check(NoteDeepLink.parse(URL(string: "daily-note://quick")!, today: day)?.day == day, "links without a day use the local current date")
        try check(NoteDeepLink.parse(URL(string: "daily-note://quick?day=2026-02-30")!) == nil && NoteDeepLink.parse(URL(string: "https://quick?day=2026-10-29")!) == nil, "reject invalid date and foreign-scheme routes")
        for display in [CGRect(x: 0, y: 0, width: 1440, height: 873), CGRect(x: -1920, y: 40, width: 1920, height: 1040), CGRect(x: 50, y: 0, width: 1280, height: 620)] {
            let panel = QuickNoteLayout.frame(in: display)
            try check(display.contains(panel) && panel.maxX == display.maxX - 16 && panel.maxY == display.maxY - 16, "right panel fits its display, dock inset and menu bar")
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let instant = ISO8601DateFormatter().date(from: "2026-10-27T17:00:00Z")!
        try check(DayKey.string(instant, calendar: calendar) == day, "day boundary follows local time zone")
        try check(DayKey.offset("2026-12-31", by: 1) == "2027-01-01", "next-day navigation crosses years")
        try check(DayKey.offset("2024-03-01", by: -1) == "2024-02-29", "previous-day navigation respects leap years")
        let oldRun = try JSONDecoder().decode(TextRun.self, from: Data(#"{"text":"原有便笺","bold":true,"italic":false,"strikethrough":false}"#.utf8))
        try check(oldRun.bold && !oldRun.highlighted && oldRun.pointSize == nil, "existing note files load without new style fields")
        let oldPrefixes = NSAttributedString(string: "☐ 原有待办\n✓ 原有完成")
        let legacyTasks = RichTextCodec.blocks(oldPrefixes)
        try check(legacyTasks[0].state == .pending && legacyTasks[1].state == .completed, "old square and checkmark prefixes remain readable")

        let blocks = [
            NoteBlock(runs: [TextRun(text: "今日重点 🧑🏽‍💻", bold: true, pointSize: 23), TextRun(text: "，继续写✍️", italic: true, highlighted: true)]),
            NoteBlock(kind: .bullet, runs: [TextRun(text: "项目符号")]),
            NoteBlock(kind: .task, runs: [TextRun(text: "还未完成 😀")]),
            NoteBlock(kind: .task, state: .completed, runs: [TextRun(text: "完成的事项")]),
            NoteBlock(kind: .task, state: .cancelled, runs: [TextRun(text: "取消但保留", strikethrough: true)]),
            NoteBlock(runs: [])
        ]
        let attributed = RichTextCodec.attributed(blocks)
        let routedText = NoteTextView(frame: .zero)
        routedText.textStorage?.setAttributedString(attributed)
        try check(routedText.focus(blockID: blocks[2].id) && routedText.selectedRange().location == (routedText.string as NSString).range(of: blocks[2].text).location, "widget paragraph focus skips the task marker")
        try check(!routedText.focus(blockID: UUID()), "stale paragraph links leave the editor usable")
        let decoded = RichTextCodec.blocks(attributed)
        try check(decoded.count == blocks.count, "rich text preserves empty trailing paragraphs")
        for index in blocks.indices {
            try check(decoded[index].text == blocks[index].text && decoded[index].kind == blocks[index].kind && decoded[index].state == blocks[index].state,
                      "mixed paragraph round trip \(index)")
            try check(decoded[index].runs == blocks[index].runs, "formatting round trip \(index)")
        }
        try check(!decoded[3].runs[0].strikethrough, "automatic completion strike does not become permanent formatting")
        var restored = decoded
        restored[3].state = .pending
        let restoredText = RichTextCodec.attributed(restored)
        let restoredRange = (restoredText.string as NSString).range(of: "完成的事项")
        try check((restoredText.attribute(.strikethroughStyle, at: restoredRange.location, effectiveRange: nil) as? Int ?? 0) == 0,
                  "restoring a task removes automatic strikethrough")

        let duplicate = NSTextStorage(attributedString: RichTextCodec.attributed([blocks[0], blocks[0]]))
        RichTextCodec.normalizeIDs(duplicate)
        let normalized = RichTextCodec.blocks(duplicate)
        try check(Set(normalized.map(\.id)).count == 2, "split or pasted paragraphs receive distinct stable IDs")

        var draft = NoteDocument(day: day, blocks: blocks)
        let initial = try store.save(draft, basedOn: .empty(day: day))
        try check(try store.load(day) == initial, "atomic document persistence")
        try store.setTask(day: day, id: blocks[2].id, state: .completed)
        draft = initial
        draft.blocks[0].runs.append(TextRun(text: " 新增文字"))
        let merged = try store.save(draft, basedOn: initial)
        try check(merged.blocks[2].state == .completed && merged.blocks[0].text.hasSuffix("新增文字"), "widget status survives a stale editor autosave")
        var localChange = merged
        localChange.blocks[2].state = .cancelled
        try store.setTask(day: day, id: blocks[2].id, state: .pending)
        let localWins = try store.save(localChange, basedOn: merged)
        try check(localWins.blocks[2].state == .cancelled, "explicit editor task changes take precedence")

        var concurrency = NoteDocument.empty(day: "2026-10-27")
        concurrency.blocks = (0..<8).map { NoteBlock(kind: .task, runs: [TextRun(text: "任务 \($0)")]) }
        let concurrentBase = try store.save(concurrency, basedOn: .empty(day: concurrency.day))
        var workers: [Process] = []
        for block in concurrentBase.blocks {
            let worker = Process()
            worker.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
            worker.arguments = ["--worker", root.path, concurrentBase.day, block.id.uuidString, "completed"]
            try worker.run()
            workers.append(worker)
        }
        for worker in workers { worker.waitUntilExit(); try check(worker.terminationStatus == 0, "widget worker exited successfully") }
        try check(try store.load(concurrentBase.day).completedCount == 8, "simultaneous widget processes do not lose task updates")

        let previous = "2026-10-26"
        let previousDoc = NoteDocument(day: previous, blocks: [
            NoteBlock(kind: .task, runs: [TextRun(text: "需要结转")]),
            NoteBlock(kind: .task, state: .completed, runs: [TextRun(text: "已完成")]),
            NoteBlock(kind: .task, state: .cancelled, runs: [TextRun(text: "已取消")])
        ])
        _ = try store.save(previousDoc, basedOn: .empty(day: previous))
        let destination = "2026-10-27"
        let carryRoot = root.appendingPathComponent("carry-tests")
        let carryStore = try NoteStore(root: carryRoot)
        _ = try carryStore.save(previousDoc, basedOn: .empty(day: previous))
        let carried = try carryStore.carryForward(to: destination)
        let carriedAgain = try carryStore.carryForward(to: destination)
        try check(carried.blocks.count == 1 && carriedAgain.blocks.count == 1, "carry forward is idempotent and excludes completed/cancelled items")
        try check(carried.blocks[0].id != previousDoc.blocks[0].id, "archived source and carried task have independent identity")
        try check(try carryStore.load(previous).blocks == previousDoc.blocks, "carry forward preserves the historical note")

        for _ in 0..<23 { _ = try store.save(localWins, basedOn: localWins) }
        let backups = try FileManager.default.contentsOfDirectory(at: root.appendingPathComponent("Backups/\(day)"), includingPropertiesForKeys: nil)
        try check(backups.count == 20, "backup retention is bounded to 20 revisions per note")
        let corruptedDay = "2026-10-25"
        let corruptedURL = root.appendingPathComponent("\(corruptedDay).json")
        let broken = Data("{this is damaged".utf8)
        try broken.write(to: corruptedURL)
        var rejected = false
        do { _ = try store.save(.empty(day: corruptedDay), basedOn: .empty(day: corruptedDay)) }
        catch { rejected = true }
        try check(rejected && (try Data(contentsOf: corruptedURL)) == broken, "a corrupt file is never silently replaced")

        let text = NoteTextView(frame: NSRect(x: 0, y: 0, width: 500, height: 500))
        let window = NSWindow(contentRect: text.frame, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.contentView = text
        text.allowsUndo = true
        text.textStorage?.setAttributedString(RichTextCodec.attributed([NoteBlock(runs: [TextRun(text: "第一段中文 😀")])]))
        text.setSelectedRange(NSRange(location: 0, length: 3))
        text.perform(.bold)
        try check(RichTextCodec.blocks(text.attributedString())[0].runs[0].bold, "editor formats a selected Chinese text range")
        text.setSelectedRange(NSRange(location: 0, length: 0))
        text.perform(.task)
        try check(text.string.hasPrefix("○ "), "editor converts a paragraph to a task")
        text.breakUndoCoalescing()
        RunLoop.main.run(until: Date().addingTimeInterval(0.03))
        try check(text.undoManager != nil && text.undoManager!.canUndo, "editor formatting registers native undo")
        text.perform(.undo)
        RunLoop.main.run(until: Date().addingTimeInterval(0.03))
        try check(!text.string.hasPrefix("○ "), "undo restores the paragraph before task conversion")
        text.perform(.redo)
        RunLoop.main.run(until: Date().addingTimeInterval(0.03))
        try check(text.string.hasPrefix("○ "), "redo restores task conversion")
        text.perform(.state)
        try check(text.string.hasPrefix("● "), "editor completes a task")
        text.perform(.state)
        try check(text.string.hasPrefix("✕ "), "editor cancels a task")
        text.perform(.state)
        try check(text.string.hasPrefix("○ "), "editor restores a task")
        text.setSelectedRange(NSRange(location: text.string.utf16.count, length: 0))
        text.insertNewline(nil)
        try check(text.string.hasSuffix("\n○ "), "return continues the task list with a pending item")
        text.insertNewline(nil)
        try check(text.string.hasSuffix("\n"), "return on an empty task returns to free writing")

        // Exercise real AppKit editing at every boundary of a semantic prefix.
        let markerFixture = NoteBlock(kind: .task, runs: [TextRun(text: "学前教育文章修改", bold: true)])
        for offset in 0...2 {
            text.textStorage?.setAttributedString(RichTextCodec.attributed([markerFixture]))
            text.setSelectedRange(NSRange(location: offset, length: 0))
            text.insertNewline(nil)
            let split = RichTextCodec.blocks(text.attributedString())
            try check(split.count == 2 && split[0].kind == .task && split[0].text.isEmpty &&
                      split[1].kind == .task && split[1].text == markerFixture.text,
                      "return at prefix boundary \(offset) creates one marker per task")
            try check(split[1].runs.allSatisfy(\.bold), "return at prefix preserves body formatting \(offset)")
        }
        for selection in [NSRange(location: 1, length: 0), NSRange(location: 2, length: 0), NSRange(location: 0, length: 1)] {
            text.textStorage?.setAttributedString(RichTextCodec.attributed([markerFixture]))
            text.setSelectedRange(selection)
            text.deleteBackward(nil)
            let deleted = RichTextCodec.blocks(text.attributedString())
            try check(deleted.count == 1 && deleted[0].kind == .paragraph && deleted[0].text == markerFixture.text,
                      "backspace removes the whole prefix at \(selection)")
        }

        for state in TaskState.allCases {
            var fixture = markerFixture
            fixture.state = state
            fixture.level = 1
            fixture.markerPointSize = 23
            text.textStorage?.setAttributedString(RichTextCodec.attributed([fixture]))
            text.setSelectedRange(NSRange(location: 1, length: 0))
            text.insertNewline(nil)
            let split = RichTextCodec.blocks(text.attributedString())
            try check(split[1].id == fixture.id && split[1].state == state && split[1].level == 1 && split[1].markerPointSize == 23,
                      "inserting before a task preserves identity, state, nesting and marker size: \(state)")
        }
        for offset in 0...1 {
            text.textStorage?.setAttributedString(RichTextCodec.attributed([markerFixture]))
            text.setSelectedRange(NSRange(location: offset, length: 0))
            text.deleteForward(nil)
            try check(text.string == markerFixture.text, "forward delete removes the whole marker at \(offset)")
        }
        for backward in [true, false] {
            text.textStorage?.setAttributedString(RichTextCodec.attributed([NoteBlock(runs: [TextRun(text: "前文")]), markerFixture]))
            text.setSelectedRange(NSRange(location: backward ? 3 : 2, length: 0))
            if backward { text.deleteBackward(nil) } else { text.deleteForward(nil) }
            try check(text.string == "前文学前教育文章修改", "joining a task to preceding text leaves no orphan circle: \(backward)")
        }
        text.textStorage?.setAttributedString(RichTextCodec.attributed([markerFixture]))
        text.setSelectedRange(NSRange(location: 1, length: 1))
        text.insertNewline(nil)
        try check(text.string == "\n○ 学前教育文章修改", "return replacing only the separator leaves no orphan circle")
        text.textStorage?.setAttributedString(RichTextCodec.attributed([markerFixture]))
        text.undoManager?.removeAllActions()
        text.setSelectedRange(NSRange(location: 2, length: 0))
        text.deleteBackward(nil)
        text.breakUndoCoalescing()
        RunLoop.main.run(until: Date().addingTimeInterval(0.03))
        text.undoManager?.undo()
        try check(text.string == "○ " + markerFixture.text, "undo restores an atomically deleted prefix")
        text.undoManager?.redo()
        try check(text.string == markerFixture.text && RichTextCodec.blocks(text.attributedString())[0].runs.allSatisfy(\.bold),
                  "redo removes the prefix and preserves bold body text")

        text.textStorage?.setAttributedString(RichTextCodec.attributed([NoteBlock(runs: [TextRun(text: "部分文字高亮", bold: true)])]))
        text.setSelectedRange(NSRange(location: 0, length: 2))
        text.perform(.highlight)
        var styledRuns = RichTextCodec.blocks(text.attributedString())[0].runs
        try check(styledRuns[0].highlighted && !styledRuns[1].highlighted, "highlight applies only to the selected Chinese text")
        let plus = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.command], timestamp: 0,
                                   windowNumber: window.windowNumber, context: nil, characters: "+", charactersIgnoringModifiers: "+", isARepeat: false, keyCode: 24)!
        try check(text.performKeyEquivalent(with: plus), "command plus is handled by the editor")
        styledRuns = RichTextCodec.blocks(text.attributedString())[0].runs
        try check(styledRuns[0].pointSize == 17 && styledRuns[1].pointSize == nil, "command plus enlarges only the selection")
        try check(styledRuns[0].bold && styledRuns[0].highlighted, "resizing preserves bold and highlight")
        let minus = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.command], timestamp: 0,
                                    windowNumber: window.windowNumber, context: nil, characters: "-", charactersIgnoringModifiers: "-", isARepeat: false, keyCode: 27)!
        try check(text.performKeyEquivalent(with: minus), "command minus is handled by the editor")
        try check(RichTextCodec.blocks(text.attributedString())[0].runs[0].pointSize == 16, "command minus reduces the selected text size")
        text.perform(.task)
        let restyled = RichTextCodec.blocks(text.attributedString())[0]
        try check(restyled.runs[0].highlighted && restyled.runs[0].pointSize == 16, "task conversion preserves per-word sizes and highlights")
        text.setSelectedRange(NSRange(location: 2, length: 2))
        text.perform(.highlight)
        try check(!RichTextCodec.blocks(text.attributedString())[0].runs[0].highlighted, "highlight button also removes an existing highlight")

        setenv("DAILYNOTE_DATA_DIR", root.appendingPathComponent("ime-test").path, 1)
        let model = NoteViewModel()
        let coordinator = RichNoteEditor.Coordinator(model)
        coordinator.textView = text
        text.delegate = coordinator
        coordinator.apply(model)
        text.setSelectedRange(NSRange(location: 0, length: 0))
        text.setMarkedText("jin", selectedRange: NSRange(location: 3, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        try check(text.hasMarkedText(), "editor accepts input-method marked text")
        try check(model.document.blocks.isEmpty, "uncommitted input-method text is not saved as final content")
        text.insertText("今日", replacementRange: NSRange(location: NSNotFound, length: 0))
        try check(!text.hasMarkedText() && model.document.blocks.map(\.text).joined() == "今日", "committed Chinese input reaches the document")
        try check(model.flush(), "committed input is saved successfully")
        let originalDay = model.document.day
        model.moveDay(by: 1)
        let tomorrow = DayKey.offset(originalDay, by: 1)!
        try check(model.document.day == tomorrow && model.document.blocks.isEmpty, "next-day button opens tomorrow without copying today's text")
        model.edited([NoteBlock(kind: .task, runs: [TextRun(text: "明天提前安排的任务", pointSize: 19, highlighted: true)])])
        model.moveDay(by: -1)
        try check(model.document.day == originalDay && model.document.blocks.map(\.text).joined() == "今日", "date navigation saves edits before switching and restores the previous day")
        model.select(day: tomorrow)
        try check(model.document.blocks[0].text == "明天提前安排的任务" && model.document.blocks[0].runs[0].highlighted,
                  "future note content and formatting survive a date round trip")
        let planned = "2027-01-20"
        try check(model.select(day: planned, createIfMissing: true) && model.days.contains(planned), "date picker creates a saved note for any specified date")
        let savedFormat = NoteDocument(day: planned, blocks: [restyled])
        let encoded = try JSONEncoder().encode(savedFormat)
        try check(try JSONDecoder().decode(NoteDocument.self, from: encoded) == savedFormat, "size and highlight persist in portable note backups")

        let parent = NoteBlock(kind: .bullet, runs: [TextRun(text: "上午", bold: true)], collapsed: true)
        let child = NoteBlock(kind: .task, runs: [TextRun(text: "阅读文献", highlighted: true)], level: 1)
        let child2 = NoteBlock(kind: .task, state: .completed, runs: [TextRun(text: "回复邮件")], level: 1)
        let nextParent = NoteBlock(kind: .bullet, runs: [TextRun(text: "下午")])
        let outline = [parent, child, child2, nextParent]
        try check(NoteOutline.visible(outline).map(\.id) == [parent.id, nextParent.id], "folding hides only the selected parent's children")
        let renderedOutline = RichTextCodec.attributed(NoteOutline.visible(outline), source: outline)
        let visibleOutline = RichTextCodec.blocks(renderedOutline)
        try check(visibleOutline[0].collapsed && visibleOutline[0].kind == .bullet, "fold state survives rich-text projection")
        var visibleEdit = visibleOutline
        visibleEdit[0].runs = [TextRun(text: "上午：优先完成")]
        let combined = NoteOutline.merging(visibleEdit, into: outline)
        try check(combined.count == 4 && combined[1] == child && combined[2] == child2, "editing a folded parent preserves hidden tasks and formatting")
        let orphaned = NoteOutline.merging([nextParent], into: outline)
        try check(orphaned.contains(where: { $0.id == child.id && $0.level == 0 }), "deleting a folded parent preserves unseen tasks as top-level items")
        let outlineDay = "2027-02-01"
        let outlineDoc = NoteDocument(day: outlineDay, blocks: outline)
        let outlineSaved = try store.save(outlineDoc, basedOn: .empty(day: outlineDay))
        try store.setCollapsed(day: outlineDay, id: parent.id, collapsed: false)
        var stale = outlineSaved
        stale.blocks[0].runs = [TextRun(text: "上午的新标题")]
        let foldMerged = try store.save(stale, basedOn: outlineSaved)
        try check(!foldMerged.blocks[0].collapsed && foldMerged.blocks[1] == child, "widget fold changes survive a concurrent editor save")

        let outlineCoordinator = RichNoteEditor.Coordinator(model)
        model.select(day: outlineDay, createIfMissing: true)
        outlineCoordinator.textView = text
        text.delegate = outlineCoordinator
        model.document = outlineDoc
        model.editorVersion += 1
        outlineCoordinator.apply(model)
        try check(!text.string.contains(child.text), "native editor does not display collapsed child text")
        let layout = text.layoutManager!
        layout.ensureLayout(for: text.textContainer!)
        let parentGlyph = layout.glyphIndexForCharacter(at: 0)
        let parentRect = layout.boundingRect(forGlyphRange: NSRange(location: parentGlyph, length: 1), in: text.textContainer!)
        let disclosurePoint = text.convert(NSPoint(x: text.textContainerOrigin.x + parentRect.minX - 14,
                                                  y: text.textContainerOrigin.y + parentRect.midY), to: nil)
        let disclosureClick = NSEvent.mouseEvent(with: .leftMouseDown, location: disclosurePoint, modifierFlags: [],
                                                 timestamp: 0, windowNumber: window.windowNumber, context: nil,
                                                 eventNumber: 1, clickCount: 1, pressure: 1)!
        text.mouseDown(with: disclosureClick)
        try check(text.string.contains(child.text) && model.document.blocks.count == 4, "native disclosure expands a parent and preserves every child")
        RunLoop.main.run(until: Date().addingTimeInterval(0.03))
        text.perform(.undo)
        RunLoop.main.run(until: Date().addingTimeInterval(0.03))
        try check(!text.string.contains(child.text) && model.document.blocks.contains(where: { $0.id == child.id }), "undo folding changes visibility without deleting child data")
        text.perform(.redo)
        RunLoop.main.run(until: Date().addingTimeInterval(0.03))
        try check(text.string.contains(child.text) && model.document.blocks.count == 4, "redo folding restores the expanded outline")
        text.toggleFold(id: parent.id)
        text.setSelectedRange(NSRange(location: 2, length: 2))
        text.insertText("晨间", replacementRange: text.selectedRange())
        try check(model.document.blocks.contains(where: { $0.id == child.id && $0.text == child.text }), "typing into a folded parent cannot erase hidden child content")
        text.toggleFold(id: parent.id)
        try check(text.string.contains(child.text), "hidden content remains available after a folded parent edit")
        let childRange = (text.string as NSString).range(of: child.text)
        text.setSelectedRange(NSRange(location: childRange.location, length: 0))
        text.insertBacktab(nil)
        try check(model.document.blocks.first(where: { $0.id == child.id })?.level == 0, "shift-tab promotes a child to a top-level item")
        text.insertTab(nil)
        try check(model.document.blocks.first(where: { $0.id == child.id })?.level == 1, "tab turns an item into a child")

        model.document = NoteDocument(day: outlineDay, blocks: [NoteBlock(kind: .bullet, runs: [TextRun(text: "排练报告")])])
        model.editorVersion += 1
        outlineCoordinator.apply(model)
        text.setSelectedRange(NSRange(location: 0, length: text.string.utf16.count))
        text.perform(.larger)
        let enlarged = model.document.blocks[0]
        try check(enlarged.markerPointSize == 17 && enlarged.runs[0].pointSize == 17, "selecting marker and text resizes both together")
        text.setSelectedRange(NSRange(location: 2, length: 2))
        text.perform(.larger)
        try check(model.document.blocks[0].markerPointSize == 17 && model.document.blocks[0].runs[0].pointSize == 18, "text-only resizing leaves the unselected marker unchanged")
        let outlineJSON = try JSONEncoder().encode(NoteDocument(day: outlineDay, blocks: outline + [enlarged]))
        try check(try JSONDecoder().decode(NoteDocument.self, from: outlineJSON).blocks == outline + [enlarged], "nested items, fold state, styles and marker sizes survive a backup round trip")
        let oldBlockJSON = Data(#"{"id":"12345678-1234-1234-1234-123456789012","kind":"bullet","state":"pending","runs":[{"text":"旧项目"}]}"#.utf8)
        let oldBlock = try JSONDecoder().decode(NoteBlock.self, from: oldBlockJSON)
        try check(oldBlock.level == 0 && !oldBlock.collapsed && oldBlock.markerPointSize == nil, "existing flat note files remain compatible")

        if ProcessInfo.processInfo.environment["DAILYNOTE_SKIP_FONT_CHECK"] != "1" {
            let wenkai = NoteFonts.font(family: "wenkai", size: 18)
            try check(wenkai.fontName == "LXGWWenKai-Regular", "bundled LXGW WenKai is really loaded, not a system-font fallback")
            let wenkaiText = RichTextCodec.attributed([NoteBlock(runs: [TextRun(text: "霞鹜文楷加粗", bold: true)])], family: "wenkai")
            try check(RichTextCodec.blocks(wenkaiText)[0].runs[0].bold, "WenKai medium weight preserves explicit bold formatting")
            text.noteFontFamily = "wenkai"
            text.textStorage?.setAttributedString(wenkaiText)
            text.outlineSource = RichTextCodec.blocks(wenkaiText)
            text.setSelectedRange(NSRange(location: 0, length: wenkaiText.length))
            text.perform(.bold)
            try check(!RichTextCodec.blocks(text.attributedString())[0].runs[0].bold, "WenKai bold can be toggled off without losing font family")
            let regularFont = text.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
            try check(regularFont?.fontName == "LXGWWenKai-Regular", "unbolding WenKai restores its regular face")
        }
        if ProcessInfo.processInfo.environment["DAILYNOTE_SKIP_FONT_CHECK"] != "1" {
            let prefixEditor = NoteTextView(frame: NSRect(x: 0, y: 0, width: 500, height: 240))
            let prefixWindow = NSWindow(contentRect: prefixEditor.frame, styleMask: [.titled], backing: .buffered, defer: false)
            prefixWindow.contentView = prefixEditor
            prefixEditor.noteFontFamily = "wenkai"
            for kind in [BlockKind.task, .bullet] {
                let styled = NoteBlock(kind: kind, runs: [TextRun(text: "回复邮件", bold: true, pointSize: 21)], markerPointSize: 14)
                prefixEditor.textStorage?.setAttributedString(RichTextCodec.attributed([styled], family: "wenkai"))
                prefixEditor.setSelectedRange(NSRange(location: 0, length: 0))
                prefixEditor.setSelectedRange(NSRange(location: 2, length: 0))
                prefixEditor.insertText("用jbox", replacementRange: NSRange(location: NSNotFound, length: 0))
                let result = prefixEditor.attributedString()
                let insertedFont = result.attribute(.font, at: 2, effectiveRange: nil) as? NSFont
                let existingFont = result.attribute(.font, at: 7, effectiveRange: nil) as? NSFont
                try check(insertedFont == existingFont && insertedFont?.fontName == "LXGWWenKai-Medium",
                          "inserting at a \(kind) body start inherits its actual WenKai font and size")
                try check(result.attribute(.kern, at: 2, effectiveRange: nil) == nil &&
                          RichTextCodec.blocks(result)[0].runs == [TextRun(text: "用jbox回复邮件", bold: true, pointSize: 21)],
                          "new list text inherits body formatting without marker kerning")
            }
        }
        model.fontFamily = "wenkai"
        model.appearanceMode = "dark"
        model.appearanceChanged()
        try check(NSApp.appearance?.name == .darkAqua, "night mode applies a dark native appearance for white text")
        let reloadedSettings = NoteViewModel()
        try check(reloadedSettings.fontFamily == "wenkai" && reloadedSettings.appearanceMode == "dark", "font and night-mode choices persist across launches")
        model.appearanceMode = "system"
        model.appearanceChanged()
        try check(NSApp.appearance == nil, "automatic appearance follows the system again")

        try check(model.select(day: "2026-11-02", createIfMissing: true), "open isolated two-editor test note")
        model.edited([NoteBlock(runs: [TextRun(text: "同步便笺")])])
        outlineCoordinator.apply(model)
        let popupText = NoteTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        popupText.allowsUndo = true
        let popupWindow = NSWindow(contentRect: popupText.frame, styleMask: [.titled], backing: .buffered, defer: false)
        popupWindow.contentView = popupText
        let popupCoordinator = RichNoteEditor.Coordinator(model)
        popupCoordinator.textView = popupText
        popupText.delegate = popupCoordinator
        popupCoordinator.apply(model)
        text.setSelectedRange(NSRange(location: text.string.utf16.count, length: 0))
        text.insertText(" 主窗口", replacementRange: text.selectedRange())
        let localSelection = text.selectedRange()
        outlineCoordinator.apply(model)
        try check(text.selectedRange() == localSelection, "local typing preserves selection when model version advances")
        popupCoordinator.apply(model)
        try check(popupText.string == text.string && popupText.string.contains("主窗口"), "main editor changes reach the quick editor")
        popupText.setSelectedRange(NSRange(location: popupText.string.utf16.count, length: 0))
        popupText.insertText(" 浮窗", replacementRange: popupText.selectedRange())
        outlineCoordinator.apply(model)
        try check(text.string == popupText.string && text.string.contains("浮窗"), "quick editor changes reach the main editor")
        try check(text.undoManager?.canUndo != true, "external text updates invalidate stale undo in the sibling editor")
        try check(popupText.undoManager?.canUndo == true, "typing retains undo in the active quick editor")
        popupWindow.makeKeyAndOrderFront(nil)
        popupWindow.makeFirstResponder(popupText)
        RunLoop.main.run(until: Date().addingTimeInterval(0.03))
        let menuCommands = EditorBridge()
        menuCommands.textView = text
        popupText.setSelectedRange(NSRange(location: 0, length: 2))
        menuCommands.perform(.bold)
        try check(RichTextCodec.blocks(popupText.attributedString())[0].runs[0].bold,
                  "format commands target the focused quick editor rather than the main window")
        popupWindow.orderOut(nil)
        try check(model.flush(), "quick editor changes persist through the shared model")
        try check(try model.store!.load("2026-11-02").blocks == model.document.blocks, "both editors save the same full note")

        let templateRoot = root.appendingPathComponent("TemplateLibrary")
        let templateStore = try NoteStore(root: templateRoot)
        let preset = try templateStore.loadTemplates()
        try check(preset.count == 1 && preset[0].blocks.count == 6, "first use includes editable daily groups")
        var custom = NoteTemplate(name: "研究与生活", blocks: [
            NoteBlock(kind: .bullet, runs: [TextRun(text: "研究", bold: true)]),
            NoteBlock(kind: .task, state: .completed, runs: [TextRun(text: "阅读", pointSize: 22, highlighted: true)], level: 1)
        ])
        try templateStore.saveTemplates([custom])
        try check(try templateStore.loadTemplates() == [custom], "custom template name, hierarchy and rich formatting persist")
        custom.name = "改名模板"
        try templateStore.saveTemplates([custom])
        try check(try templateStore.loadTemplates()[0].name == custom.name, "template edits replace the same saved template")
        let firstUse = custom.instantiate(), secondUse = custom.instantiate()
        try check(firstUse[1].state == .pending && firstUse[1].runs == custom.blocks[1].runs && firstUse[1].level == 1,
                  "instantiation resets task status and preserves rich text and nesting")
        try check(Set((firstUse + secondUse + custom.blocks).map(\.id)).count == 6, "each template insertion has independent block IDs")
        text.textStorage?.setAttributedString(RichTextCodec.attributed([NoteBlock(runs: [TextRun(text: "已有内容")])]))
        text.outlineSource = RichTextCodec.blocks(text.attributedString())
        text.undoManager?.removeAllActions()
        text.insertTemplate(custom)
        let inserted = RichTextCodec.blocks(text.attributedString())
        try check(inserted.count == 3 && inserted[0].text == "已有内容" && inserted[2].state == .pending,
                  "template insertion appends without replacing existing note content")
        text.undoManager?.undo()
        try check(text.string == "已有内容", "template insertion can be undone as one action")
        try templateStore.saveTemplates([])
        try check(try templateStore.loadTemplates().isEmpty, "deleting every template does not restore the preset on restart")
        let previousTemplates = try JSONDecoder().decode([NoteTemplate].self, from: Data(contentsOf: templateRoot.appendingPathComponent("templates.previous.json")))
        try check(previousTemplates == [custom], "template deletion leaves a recoverable previous library")
        try check(try templateStore.days().isEmpty, "template library files never appear as dated notes")
        let damaged = Data("broken template file".utf8)
        try damaged.write(to: templateRoot.appendingPathComponent("templates.json"))
        var corruptTemplateRejected = false
        do { try templateStore.saveTemplates([custom]) } catch { corruptTemplateRejected = true }
        try check(corruptTemplateRejected && (try Data(contentsOf: templateRoot.appendingPathComponent("templates.json"))) == damaged,
                  "corrupt template library is never overwritten")
        let memoryDraft = NoteViewModel(templateBlocks: custom.blocks)
        memoryDraft.edited([NoteBlock(runs: [TextRun(text: "仅模板草稿")])])
        try check(memoryDraft.store == nil && memoryDraft.flush() && memoryDraft.document.blocks[0].text == "仅模板草稿",
                  "template drafts edit in memory without writing dated notes")

        let nestedBlocks = [
            NoteBlock(kind: .bullet, runs: [TextRun(text: "一级")]),
            NoteBlock(kind: .task, runs: [TextRun(text: "子项目")], level: 1),
            NoteBlock(kind: .task, runs: [TextRun(text: "孙项目", bold: true, highlighted: true)], level: 2),
            NoteBlock(kind: .task, runs: [TextRun(text: "曾孙项目")], level: 3),
            NoteBlock(kind: .task, runs: [TextRun(text: "同级子项目")], level: 1),
            NoteBlock(runs: [TextRun(text: "下组")])]
        try check(try JSONDecoder().decode([NoteBlock].self, from: JSONEncoder().encode(nestedBlocks)) == nestedBlocks,
                  "multiple outline levels survive portable backup encoding")
        try check(RichTextCodec.blocks(RichTextCodec.attributed(nestedBlocks)) == nestedBlocks,
                  "rich text projection preserves deep nesting and formatting")
        var foldedNested = nestedBlocks
        foldedNested[1].collapsed = true
        try check(NoteOutline.visible(foldedNested).map(\.id) == [nestedBlocks[0].id, nestedBlocks[1].id, nestedBlocks[4].id, nestedBlocks[5].id],
                  "folding a nested parent hides only its descendants")
        try check(NoteOutline.children(of: nestedBlocks[2].id, in: nestedBlocks).map(\.id) == [nestedBlocks[3].id],
                  "a grandchild can itself have children")
        try check(NoteOutline.merging(NoteOutline.visible(foldedNested), into: foldedNested) == foldedNested,
                  "saving nested folded content preserves all hidden descendants")
        foldedNested[0].collapsed = true
        try check(NoteOutline.merging(NoteOutline.visible(foldedNested), into: foldedNested) == foldedNested,
                  "nested collapsed branches reattach exactly once")
        foldedNested[0].collapsed = false
        let removedNested = NoteOutline.merging(NoteOutline.visible(foldedNested).filter { $0.id != nestedBlocks[1].id }, into: foldedNested)
        try check(removedNested.contains(where: { $0.id == nestedBlocks[2].id }) && removedNested.contains(where: { $0.id == nestedBlocks[3].id }),
                  "deleting a collapsed nested parent never deletes hidden descendants")
        try check(removedNested.first(where: { $0.id == nestedBlocks[3].id })!.level == removedNested.first(where: { $0.id == nestedBlocks[2].id })!.level + 1,
                  "promoted hidden descendants retain relative nesting")
        let nestingText = NoteTextView(frame: NSRect(x: 0, y: 0, width: 500, height: 400))
        nestingText.allowsUndo = true
        let nestingWindow = NSWindow(contentRect: nestingText.frame, styleMask: [.titled], backing: .buffered, defer: false)
        nestingWindow.contentView = nestingText
        var editableNested = nestedBlocks
        editableNested[2].level = 1
        editableNested[3].level = 1
        nestingText.textStorage?.setAttributedString(RichTextCodec.attributed(editableNested))
        nestingText.outlineSource = editableNested
        func selectNested(_ title: String) {
            let range = (nestingText.string as NSString).range(of: title)
            nestingText.setSelectedRange(NSRange(location: range.location, length: 0))
        }
        selectNested("孙项目")
        nestingText.insertTab(nil)
        try check(RichTextCodec.blocks(nestingText.attributedString())[2].level == 2, "Tab creates a grandchild below an existing child")
        selectNested("曾孙项目")
        nestingText.insertTab(nil)
        nestingText.insertTab(nil)
        try check(RichTextCodec.blocks(nestingText.attributedString())[3].level == 3, "repeated Tab supports a third nested level")
        selectNested("子项目")
        nestingText.insertBacktab(nil)
        let promotedTree = RichTextCodec.blocks(nestingText.attributedString())
        try check(promotedTree[1].level == 0 && promotedTree[2].level == 1 && promotedTree[3].level == 2,
                  "Shift-Tab promotes a whole subtree by one level")
        selectNested("孙项目")
        nestingText.insertBacktab(nil)
        try check(RichTextCodec.blocks(nestingText.attributedString())[2].level == 0,
                  "Shift-Tab decreases one level rather than forcing an arbitrary level")
        nestingText.toggleFold(id: nestedBlocks[2].id)
        try check(!nestingText.string.contains("曾孙项目"), "native nested-parent disclosure hides its descendants")
        nestingText.toggleFold(id: nestedBlocks[2].id)
        try check(nestingText.string.contains("曾孙项目"), "native nested-parent disclosure expands without losing content")
        var nestedDocument = NoteDocument(day: "2026-11-05", blocks: nestedBlocks)
        nestedDocument = try templateStore.save(nestedDocument, basedOn: .empty(day: nestedDocument.day))
        try templateStore.setCollapsed(day: nestedDocument.day, id: nestedBlocks[1].id, collapsed: true)
        try check(try templateStore.load(nestedDocument.day).blocks[1].collapsed, "widget storage can fold a nested parent")
        let nestedTemplate = NoteTemplate(name: "多级模板", blocks: nestedBlocks)
        try check(nestedTemplate.instantiate().map(\.level) == [0, 1, 2, 3, 1, 0], "templates retain all nesting levels")

        var completionTree = [
            NoteBlock(kind: .task, runs: [TextRun(text: "父事项")]),
            NoteBlock(kind: .task, runs: [TextRun(text: "子事项")], level: 1, collapsed: true),
            NoteBlock(kind: .task, state: .completed, runs: [TextRun(text: "孙事项甲")], level: 2),
            NoteBlock(kind: .task, runs: [TextRun(text: "孙事项乙")], level: 2)]
        try check(!completionTree[0].usesSquareMarker && !completionTree[1].usesSquareMarker && completionTree[2].usesSquareMarker,
                  "grandchildren use square markers while first two levels remain circular")
        try check(NoteBlock(level: 3).usesSquareMarker, "deeper descendants keep square markers")
        try check(NoteOutline.completingParents(completionTree)[0].state == .pending, "unfinished descendants keep parent pending")
        completionTree[3].state = .completed
        let allComplete = NoteOutline.completingParents(completionTree)
        try check(allComplete.allSatisfy { $0.state == .completed }, "last leaf completion propagates through folded task ancestors")
        var reopened = allComplete
        reopened[2].state = .pending
        reopened = NoteOutline.completingParents(reopened)
        try check(reopened[0].state == .pending && reopened[1].state == .pending, "reopening a leaf reopens each task ancestor")
        reopened[2].state = .cancelled
        try check(NoteOutline.completingParents(reopened)[0].state == .pending, "cancelled descendants do not count as completed")
        var headingTree = completionTree
        headingTree[0].kind = .bullet
        try check(NoteOutline.completingParents(headingTree)[0].state == .pending, "plain section headings are not converted into completed tasks")
        let leaf = NoteBlock(kind: .task, state: .completed)
        try check(NoteOutline.completingParents([leaf]) == [leaf], "standalone tasks retain manual state")
        let completionModel = NoteViewModel(templateBlocks: completionTree)
        let completionText = NoteTextView(frame: NSRect(x: 0, y: 0, width: 500, height: 400))
        let completionWindow = NSWindow(contentRect: completionText.frame, styleMask: [.titled], backing: .buffered, defer: false)
        completionWindow.contentView = completionText
        completionText.allowsUndo = true
        let completionCoordinator = RichNoteEditor.Coordinator(completionModel)
        completionCoordinator.textView = completionText
        completionText.delegate = completionCoordinator
        completionCoordinator.apply(completionModel)
        completionText.toggleFold(id: completionTree[1].id)
        let leafRange = (completionText.string as NSString).range(of: "孙事项乙")
        completionText.setSelectedRange(NSRange(location: leafRange.location, length: 0))
        // Start from pending, so the next native action completes the last child.
        completionModel.document.blocks[3].state = .pending
        completionModel.document.blocks[0].state = .pending
        completionModel.document.blocks[1].state = .pending
        completionModel.editorVersion += 1
        completionCoordinator.apply(completionModel)
        completionText.setSelectedRange(NSRange(location: leafRange.location, length: 0))
        completionText.perform(.state)
        try check(completionModel.document.blocks.allSatisfy { $0.state == .completed }, "native child checkbox immediately completes and redraws ancestors")
        completionText.perform(.undo)
        try check(completionModel.document.blocks[0].state == .pending && completionModel.document.blocks[3].state == .pending,
                  "undo restores both leaf and parent completion states")
        let completionStore = try NoteStore(root: root.appendingPathComponent("ParentCompletion"))
        let completionDay = "2026-11-05"
        let savedComplete = try completionStore.save(NoteDocument(day: completionDay, blocks: completionTree), basedOn: .empty(day: completionDay))
        try check(savedComplete.blocks[0].state == .completed, "saving and importing also derive parent completion")
        try completionStore.setTask(day: completionDay, id: completionTree[3].id, state: .pending)
        let remoteReopen = try completionStore.load(completionDay)
        try check(remoteReopen.blocks[0].state == .pending && remoteReopen.blocks[1].state == .pending,
                  "widget child toggle reopens ancestors in shared storage")
        var staleDraft = savedComplete
        staleDraft.blocks[0].runs = [TextRun(text: "并发文字修改", bold: true)]
        let mergedCompletion = try completionStore.save(staleDraft, basedOn: savedComplete)
        try check(mergedCompletion.blocks[0].state == .pending && mergedCompletion.blocks[3].state == .pending && mergedCompletion.blocks[0].text == "并发文字修改",
                  "concurrent editor save preserves remote child state and recomputes parent state")

        print("\n\(count) checks passed.")
    }
}
