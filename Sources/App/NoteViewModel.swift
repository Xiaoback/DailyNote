import AppKit
import Combine
#if !DAILYNOTE_STANDALONE
import WidgetKit
#endif
import UniformTypeIdentifiers

@MainActor
final class NoteViewModel: ObservableObject {
    @Published var document = NoteDocument.empty(day: DayKey.string())
    @Published var templates: [NoteTemplate] = []
    private var memoryOnly = false
    @Published var editorVersion = 0
    @Published var saveStatus = "已保存到本机"
    @Published var errorMessage: String?
    @Published var loadFailed = false
    @Published var days: [String] = []
    @Published var pendingCount = 0
    @Published var fontSize: CGFloat = 16
    @Published var paper = "butter"
    @Published var fontFamily = "system"
    @Published var appearanceMode = "system"
    let isPreviewBuild = Bundle.main.object(forInfoDictionaryKey: "DailyNotePreviewDataDirectory") != nil
    private(set) var store: NoteStore?
    private var base = NoteDocument.empty(day: DayKey.string())
    private var dirty = false
    private var saveWork: DispatchWorkItem?
    private var timer: AnyCancellable?
    private var followedToday = true

    init(templateBlocks: [NoteBlock]? = nil) {
        if let templateBlocks {
            memoryOnly = true
            document.blocks = templateBlocks
            NoteFonts.register()
            return
        }
        do {
            store = try NoteStore.configured()
            if let settings = store?.root.appendingPathComponent("appearance.json"),
               let data = try? Data(contentsOf: settings),
               let values = try? JSONDecoder().decode([String: String].self, from: data) {
                fontSize = min(24, max(13, CGFloat(Double(values["fontSize"] ?? "16") ?? 16)))
                paper = values["paper"] ?? "butter"
                fontFamily = values["fontFamily"] == "wenkai" ? "wenkai" : "system"
                appearanceMode = ["system", "light", "dark"].contains(values["appearanceMode"] ?? "") ? values["appearanceMode"]! : "system"
            }
            NoteFonts.register()
            applyAppearance()
            if ProcessInfo.processInfo.arguments.contains("--demo"),
               let store, try store.days().isEmpty {
                let sample = NoteDocument.example(day: DayKey.string())
                _ = try store.save(sample, basedOn: .empty(day: sample.day))
            }
            load(day: DayKey.string())
            do { templates = try store?.loadTemplates() ?? [] }
            catch { present(error) }
        } catch { present(error); loadFailed = true }
        timer = Timer.publish(every: 3, on: .main, in: .common).autoconnect().sink { [weak self] _ in
            self?.refresh()
        }
    }

    func edited(_ blocks: [NoteBlock]) {
        guard !loadFailed else { return }
        document.blocks = NoteOutline.completingParents(blocks)
        editorVersion += 1
        dirty = true
        if memoryOnly { saveStatus = "模板草稿"; return }
        saveStatus = "正在保存…"
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in _ = self?.flush() }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: work)
    }

    @discardableResult func flush() -> Bool {
        if memoryOnly { return true }
        saveWork?.cancel()
        guard dirty else { return true }
        guard let store else { return false }
        do {
            let saved = try store.save(document, basedOn: base)
            let changedByMerge = saved.blocks != document.blocks
            document = saved
            base = saved
            dirty = false
            saveStatus = "已保存到本机"
            if changedByMerge { editorVersion += 1 }
            #if !DAILYNOTE_STANDALONE
        WidgetCenter.shared.reloadTimelines(ofKind: "DailyNoteWidget")
        #endif
            updateLists()
            return true
        } catch {
            saveStatus = "保存失败，内容仍在窗口中"
            present(error)
            return false
        }
    }

    @discardableResult func select(day: String, createIfMissing: Bool = false) -> Bool {
        guard DayKey.isValid(day), flush() else { return false }
        if createIfMissing {
            do {
                guard let store else { throw NoteError.sharedContainerUnavailable }
                if !(try store.days()).contains(day) {
                    _ = try store.save(.empty(day: day), basedOn: .empty(day: day))
                }
            } catch { present(error); return false }
        }
        guard load(day: day) else { return false }
        followedToday = day == DayKey.string()
        return true
    }

    @discardableResult func saveTemplate(_ template: NoteTemplate) -> Bool {
        var value = template
        value.name = value.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.name.isEmpty, let store else { return false }
        var next = templates
        if let index = next.firstIndex(where: { $0.id == value.id }) { next[index] = value }
        else { next.append(value) }
        do { try store.saveTemplates(next); templates = next; return true }
        catch { present(error); return false }
    }

    @discardableResult func deleteTemplate(_ id: UUID) -> Bool {
        guard let store else { return false }
        let next = templates.filter { $0.id != id }
        do { try store.saveTemplates(next); templates = next; return true }
        catch { present(error); return false }
    }

    func moveDay(by offset: Int) {
        guard let day = DayKey.offset(document.day, by: offset) else { return }
        select(day: day)
    }

    @discardableResult private func load(day: String) -> Bool {
        do {
            guard let store else { throw NoteError.sharedContainerUnavailable }
            let loaded = try store.load(day)
            document = loaded
            base = loaded
            dirty = false
            loadFailed = false
            errorMessage = nil
            editorVersion += 1
            saveStatus = "已保存到本机"
            updateLists()
            return true
        } catch { loadFailed = true; present(error); return false }
    }

    private func refresh() {
        // Defer any external replacement while Chinese IME composition is active.
        if let text = NSApp.keyWindow?.firstResponder as? NSTextView, text.hasMarkedText() { return }
        if dirty && !flush() { return }
        let today = DayKey.string()
        if followedToday && document.day != today { load(day: today); return }
        guard !loadFailed, let latest = try? store?.load(document.day) else { return }
        if latest.revision != base.revision {
            document = latest
            base = latest
            editorVersion += 1
            updateLists()
        }
    }

    private func updateLists() {
        days = (try? store?.days()) ?? []
        pendingCount = (try? store?.pendingBefore(document.day).count) ?? 0
    }

    func carryForward() {
        guard flush(), let store else { return }
        do {
            document = try store.carryForward(to: document.day)
            base = document
            editorVersion += 1
            updateLists()
            #if !DAILYNOTE_STANDALONE
        WidgetCenter.shared.reloadTimelines(ofKind: "DailyNoteWidget")
        #endif
        } catch { present(error) }
    }

    func appearanceChanged() {
        applyAppearance()
        editorVersion += 1
        guard let store else { return }
        do {
            let settings = ["fontSize": String(Double(fontSize)), "paper": paper, "fontFamily": fontFamily, "appearanceMode": appearanceMode]
            try JSONEncoder().encode(settings).write(to: store.root.appendingPathComponent("appearance.json"), options: .atomic)
            #if !DAILYNOTE_STANDALONE
        WidgetCenter.shared.reloadTimelines(ofKind: "DailyNoteWidget")
        #endif
        } catch { present(error) }
    }

    private func applyAppearance() {
        let name: NSAppearance.Name? = appearanceMode == "dark" ? .darkAqua : (appearanceMode == "light" ? .aqua : nil)
        NSApplication.shared.appearance = name.flatMap(NSAppearance.init(named:))
    }

    func export() {
        // Export remains available as a rescue path when the regular store fails.
        _ = flush()
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        panel.nameFieldStringValue = "\(document.day)-今日便笺.md"
        panel.title = "导出便笺"
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        do { try RichTextCodec.markdown(document).write(to: destination, atomically: true, encoding: .utf8) }
        catch { present(error) }
    }

    func openBackups() {
        guard let root = store?.root else { return }
        NSWorkspace.shared.open(root.appendingPathComponent("Backups"))
    }

    func exportBackup() {
        _ = flush()
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "\(document.day)-便笺备份.json"
        panel.title = "导出可恢复的便笺备份"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try JSONEncoder().encode(document).write(to: url, options: .atomic) }
        catch { present(error) }
    }

    func importBackup() {
        guard flush(), let store else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.title = "导入便笺备份"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let imported = try JSONDecoder().decode(NoteDocument.self, from: Data(contentsOf: url))
            guard imported.schemaVersion == 1 else { throw NoteError.unsupportedVersion }
            guard DayKey.isValid(imported.day), Set(imported.blocks.map(\.id)).count == imported.blocks.count else {
                throw NoteError.damagedFile(url.lastPathComponent)
            }
            let existing = try store.load(imported.day)
            if !existing.blocks.isEmpty {
                let alert = NSAlert()
                alert.messageText = "替换 \(imported.day) 的便笺？"
                alert.informativeText = "当前版本会先存入本地备份。导入后可从备份恢复。"
                alert.addButton(withTitle: "导入并替换")
                alert.addButton(withTitle: "取消")
                guard alert.runModal() == .alertFirstButtonReturn else { return }
            }
            _ = try store.save(imported, basedOn: existing)
            select(day: imported.day)
            #if !DAILYNOTE_STANDALONE
        WidgetCenter.shared.reloadTimelines(ofKind: "DailyNoteWidget")
        #endif
        } catch { present(error) }
    }

    func openURL(_ url: URL) {
        guard url.scheme == "daily-note", url.host == "today" else { return }
        let day = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "day" })?.value
        select(day: day.flatMap { DayKey.isValid($0) ? $0 : nil } ?? DayKey.string())
        NSApp.activate(ignoringOtherApps: true)
    }

    private func present(_ error: Error) { errorMessage = error.localizedDescription }
}
