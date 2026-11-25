import AppKit
import SwiftUI
import OSLog
#if !DAILYNOTE_STANDALONE
import WidgetKit
#endif

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private(set) var model: NoteViewModel?
    private let bridge = EditorBridge()
    private let quickBridge = EditorBridge()
    let quickEditor = QuickNoteController()
    private let hotCorner = HotCornerController()
    private var mainWindow: NSWindow?
    private var menus: NoteAppMenus?
    private var pendingURLs: [URL] = []
    private let log = Logger(subsystem: "local.yangxiao.DailyNote", category: "Navigation")

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"), let icon = NSImage(contentsOf: url) {
            NSApp.applicationIconImage = icon
        }
        let model = NoteViewModel()
        self.model = model
        quickEditor.install(model: model, bridge: quickBridge) { [weak self] in self?.showMainEditor() }
        hotCorner.install(enabledByDefault: !model.isPreviewBuild,
                          canOpen: { [weak self] in self?.quickEditor.isPresented == false },
                          open: { [weak self] in self?.showQuickEditor(day: DayKey.string(), hideOnPointerExit: true) })
        menus = NoteAppMenus(model: model, bridge: bridge,
                             hotCorner: hotCorner,
                             showQuick: { [weak self] in self?.showQuickEditor() },
                             showMain: { [weak self] in self?.showMainEditor() })
        let queued = pendingURLs
        pendingURLs.removeAll()
        if queued.isEmpty { showQuickEditor() }
        else { queued.forEach(open) }
        #if !DAILYNOTE_STANDALONE
        WidgetCenter.shared.reloadTimelines(ofKind: "DailyNoteWidget")
        #endif
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard model != nil else { pendingURLs.append(contentsOf: urls); return }
        urls.forEach(open)
    }

    private func open(_ url: URL) {
        guard let request = NoteDeepLink.parse(url), let model else { return }
        switch request.destination {
        case .quick:
            showQuickEditor(day: request.day, blockID: request.blockID)
        case .editor:
            _ = model.select(day: request.day)
            showMainEditor()
        }
        log.notice("Opened note link; quick=\(request.destination == .quick), mainVisible=\(self.mainWindow?.isVisible == true)")
    }

    private func showQuickEditor(day: String? = nil, blockID: UUID? = nil, hideOnPointerExit: Bool = false) {
        NSApp.unhide(nil)
        mainWindow?.orderOut(nil)
        quickEditor.show(day: day, blockID: blockID, hideOnPointerExit: hideOnPointerExit)
    }

    func showMainEditor() {
        guard let model else { return }
        quickEditor.hide()
        if mainWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 610, height: 690),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable],
                                  backing: .buffered, defer: false)
            window.title = model.isPreviewBuild ? "今日便笺 · 编辑器预览" : "今日便笺"
            window.identifier = NSUserInterfaceItemIdentifier("editor")
            window.isReleasedWhenClosed = false
            window.acceptsMouseMovedEvents = true
            window.delegate = self
            window.contentMinSize = NSSize(width: 480, height: 470)
            window.contentViewController = NSHostingController(rootView: ContentView(model: model, bridge: bridge))
            window.center()
            window.setFrameAutosaveName("DailyNoteEditor")
            mainWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        mainWindow?.makeKeyAndOrderFront(nil)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showQuickEditor(day: DayKey.string())
        return false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard model?.flush() != false else {
            let alert = NSAlert()
            alert.messageText = "便笺尚未保存"
            alert.informativeText = "请先解决窗口中的保存错误，或导出便笺。内容仍保留在编辑窗口中。"
            alert.runModal()
            return .terminateCancel
        }
        return .terminateNow
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationWillTerminate(_ notification: Notification) { hotCorner.stop() }
    func windowShouldClose(_ sender: NSWindow) -> Bool { model?.flush() != false }
    func windowDidResignKey(_ notification: Notification) { _ = model?.flush() }
}

@main
struct DailyNoteApp {
    @MainActor static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.regular)
        withExtendedLifetime(delegate) { application.run() }
    }
}
