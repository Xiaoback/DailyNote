import AppKit
import SwiftUI
import OSLog

private final class QuickNotePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { performClose(sender) }
}

@MainActor
final class QuickNoteController: NSObject, NSWindowDelegate {
    private var panel: NSPanel?
    private weak var model: NoteViewModel?
    private weak var bridge: EditorBridge?
    private var hoverTimer: Timer?
    private var hoverState = HoverDismissState()
    private var openingScreen: CGRect?
    private var menuTrackingDepth = 0
    private var tracksPointerExit = false
    private var dateChooserVisible = false
    private let log = Logger(subsystem: "local.yangxiao.DailyNote", category: "QuickEditor")

    var isPresented: Bool {
        guard let panel, !NSApp.isHidden else { return false }
        return panel.isVisible && panel.isOnActiveSpace && (tracksPointerExit || NSApp.isActive || panel.isKeyWindow)
    }

    func install(model: NoteViewModel, bridge: EditorBridge, openMain: @escaping () -> Void) {
        guard panel == nil else { return }
        self.model = model
        self.bridge = bridge
        NotificationCenter.default.addObserver(self, selector: #selector(menuOpened(_:)), name: NSMenu.didBeginTrackingNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(menuClosed(_:)), name: NSMenu.didEndTrackingNotification, object: nil)
        let panel = QuickNotePanel(contentRect: NSRect(x: 0, y: 0, width: 520, height: 650),
                                  styleMask: [.titled, .closable, .nonactivatingPanel],
                                  backing: .buffered, defer: false)
        panel.title = "今日便笺 · 快速编辑"
        panel.identifier = NSUserInterfaceItemIdentifier("quick-editor")
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = true
        panel.becomesKeyOnlyIfNeeded = false
        panel.acceptsMouseMovedEvents = true
        panel.isExcludedFromWindowsMenu = true
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.delegate = self
        panel.contentViewController = NSHostingController(rootView:
            QuickNoteView(model: model, bridge: bridge, openMain: { [weak self] in
                self?.hide()
                openMain()
            }, close: { [weak self] in self?.hide() }, dateChooserChanged: { [weak self] visible in
                self?.dateChooserVisible = visible
            }))
        self.panel = panel
    }

    func show(day: String? = nil, blockID: UUID? = nil, hideOnPointerExit: Bool = false) {
        guard let panel, let model else { return }
        stopHoverDismiss()
        tracksPointerExit = hideOnPointerExit
        panel.hidesOnDeactivate = !hideOnPointerExit
        if let day { _ = model.select(day: day) }
        let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) })
            ?? NSScreen.main ?? NSScreen.screens.first
        if let screen { panel.setFrame(QuickNoteLayout.frame(in: screen.visibleFrame), display: false) }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        if hideOnPointerExit {
            openingScreen = screen?.frame
            hoverState = HoverDismissState()
            let timer = Timer(timeInterval: 0.1, target: self, selector: #selector(checkPointer(_:)), userInfo: nil, repeats: true)
            timer.tolerance = 0.03
            RunLoop.main.add(timer, forMode: .common)
            hoverTimer = timer
        }
        DispatchQueue.main.async { [weak self] in
            guard let self, let view = self.bridge?.textView else { return }
            view.window?.makeFirstResponder(view)
            if let blockID { _ = view.focus(blockID: blockID) }
            self.log.notice("Right editor shown; day=\(model.document.day, privacy: .public), key=\(panel.isKeyWindow), active=\(NSApp.isActive), hover=\(hideOnPointerExit)")
        }
    }

    func hide() {
        stopHoverDismiss()
        guard model?.flush() != false else { return }
        panel?.orderOut(nil)
    }

    private func stopHoverDismiss() {
        hoverTimer?.invalidate()
        hoverTimer = nil
    }

    @objc private func checkPointer(_ timer: Timer) {
        guard let panel, panel.isVisible, !NSApp.isHidden else { stopHoverDismiss(); return }
        let point = NSEvent.mouseLocation
        let openingCorner = openingScreen.map { HotCornerState.isTopRight(point, screens: [$0]) } ?? false
        let otherKeyWindow = NSApp.keyWindow.map { $0 !== panel && $0.isVisible } ?? false
        let busy = dateChooserVisible || menuTrackingDepth > 0 || NSApp.modalWindow != nil || panel.attachedSheet != nil
            || otherKeyWindow || panel.childWindows?.contains(where: \.isVisible) == true
            || bridge?.textView?.hasMarkedText() == true || NSEvent.pressedMouseButtons != 0
        if hoverState.shouldHide(insidePanel: panel.frame.contains(point), insideOpeningCorner: openingCorner,
                                 busy: busy, now: ProcessInfo.processInfo.systemUptime) {
            log.notice("Pointer left hot-corner editor; saving and hiding")
            hide()
        }
    }

    @objc private func menuOpened(_ notification: Notification) { menuTrackingDepth += 1 }
    @objc private func menuClosed(_ notification: Notification) { menuTrackingDepth = max(0, menuTrackingDepth - 1) }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard model?.flush() != false else { return false }
        stopHoverDismiss()
        return true
    }
    func windowDidResignKey(_ notification: Notification) { _ = model?.flush() }
}
