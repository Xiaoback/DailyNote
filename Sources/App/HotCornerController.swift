import AppKit
import OSLog

@MainActor
final class HotCornerController: NSObject {
    private let defaults = UserDefaults.standard
    private let key = "DailyNoteTopRightCornerEnabled"
    private var timer: Timer?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var dwellWork: DispatchWorkItem?
    private var dwellGeneration = 0
    private var receivedGlobalMovement = false
    private var state = HotCornerState()
    private var sessionActive = true
    private var screenAwake = true
    private var canOpen: (() -> Bool)?
    private var open: (() -> Void)?
    private let log = Logger(subsystem: "local.yangxiao.DailyNote", category: "HotCorner")

    var isEnabled: Bool {
        get { defaults.bool(forKey: key) }
        set { defaults.set(newValue, forKey: key); restartMonitoring() }
    }

    func install(enabledByDefault: Bool, canOpen: @escaping () -> Bool, open: @escaping () -> Void) {
        defaults.register(defaults: [key: enabledByDefault])
        self.canOpen = canOpen
        self.open = open
        refreshScreens(nil)
        NotificationCenter.default.addObserver(self, selector: #selector(refreshScreens(_:)),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(self, selector: #selector(sessionInactive(_:)), name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
        workspace.addObserver(self, selector: #selector(sessionResumed(_:)), name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)
        workspace.addObserver(self, selector: #selector(screenSleeping(_:)), name: NSWorkspace.willSleepNotification, object: nil)
        workspace.addObserver(self, selector: #selector(screenSleeping(_:)), name: NSWorkspace.screensDidSleepNotification, object: nil)
        workspace.addObserver(self, selector: #selector(screenResumed(_:)), name: NSWorkspace.didWakeNotification, object: nil)
        workspace.addObserver(self, selector: #selector(screenResumed(_:)), name: NSWorkspace.screensDidWakeNotification, object: nil)
        restartMonitoring()
    }

    private func restartMonitoring() {
        stopMonitoring()
        guard isEnabled else { log.notice("Top-right corner disabled"); return }
        // Observe only pointer movement/drag/release. Never consume events or monitor keys.
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged,
                                          .leftMouseUp, .rightMouseUp, .otherMouseUp]
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            guard let self else { return }
            if !self.receivedGlobalMovement {
                self.receivedGlobalMovement = true
                self.log.notice("Global pointer events received")
            }
            self.observePointer(event)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.observePointer(event)
            return event
        }
        // Fallback for system-owned surfaces that don't forward mouse events.
        let timer = Timer(timeInterval: 0.2, target: self, selector: #selector(tick(_:)), userInfo: nil, repeats: true)
        timer.tolerance = 0.03
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        log.notice("Top-right monitoring enabled; global=\(self.globalMonitor != nil), local=\(self.localMonitor != nil)")
    }

    @objc private func tick(_ timer: Timer) { evaluatePointer() }

    private func observePointer(_ event: NSEvent) {
        let dragging = event.type == .leftMouseDragged || event.type == .rightMouseDragged || event.type == .otherMouseDragged
        if let point = event.cgEvent?.location, let primary = state.screens.first {
            evaluatePointer(at: HotCornerState.appKitPoint(fromQuartz: point, primaryScreen: primary), dragging: dragging)
        } else {
            evaluatePointer(dragging: dragging)
        }
    }

    private func evaluatePointer(at point: CGPoint? = nil, dragging: Bool = false) {
        guard sessionActive, screenAwake else { resetPendingEntry(); return }
        let now = ProcessInfo.processInfo.systemUptime
        let inside = HotCornerState.isTopRight(point ?? NSEvent.mouseLocation, screens: state.screens)
        guard inside else {
            _ = state.update(inside: false, allowed: true, now: now)
            cancelDwell()
            return
        }
        let allowed = !dragging && NSEvent.pressedMouseButtons == 0 && NSApp.modalWindow == nil && (canOpen?() ?? false)
        if state.update(inside: true, allowed: allowed, now: now) {
            cancelDwell()
            log.notice("Top-right corner triggered")
            open?()
        } else if let remaining = state.remainingDwell(at: now) {
            guard dwellWork == nil else { return }
            let generation = dwellGeneration
            let work = DispatchWorkItem { [weak self] in
                guard let self, self.dwellGeneration == generation else { return }
                self.dwellWork = nil
                self.evaluatePointer()
            }
            dwellWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + remaining + 0.01, execute: work)
        } else {
            cancelDwell()
        }
    }

    private func cancelDwell() {
        guard let dwellWork else { return }
        dwellGeneration += 1
        dwellWork.cancel()
        self.dwellWork = nil
    }

    private func resetPendingEntry() { state.reset(); cancelDwell() }

    @objc private func refreshScreens(_ notification: Notification?) {
        // Menu-bar/Space changes can post this without changing physical screens.
        // Resetting an unchanged frame would lock a pointer already in the corner.
        if state.updateScreens(NSScreen.screens.map(\.frame)) { cancelDwell() }
    }
    @objc private func sessionInactive(_ notification: Notification?) { sessionActive = false; resetPendingEntry() }
    @objc private func sessionResumed(_ notification: Notification?) { sessionActive = true; resetPendingEntry() }
    @objc private func screenSleeping(_ notification: Notification?) { screenAwake = false; resetPendingEntry() }
    @objc private func screenResumed(_ notification: Notification?) { screenAwake = true; resetPendingEntry() }

    private func stopMonitoring() {
        timer?.invalidate()
        timer = nil
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
        receivedGlobalMovement = false
        resetPendingEntry()
    }

    func stop() {
        stopMonitoring()
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }
}
