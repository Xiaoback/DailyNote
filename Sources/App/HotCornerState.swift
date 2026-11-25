import Foundation

struct HotCornerState {
    let dwell: TimeInterval = 0.4
    private var enteredAt: TimeInterval?
    private var needsExit = true
    private(set) var screens: [CGRect] = []

    static func isTopRight(_ point: CGPoint, screens: [CGRect]) -> Bool {
        screens.contains { frame in
            point.x >= frame.maxX - 8 && point.x <= frame.maxX
                && point.y >= frame.maxY - 8 && point.y <= frame.maxY
        }
    }

    static func appKitPoint(fromQuartz point: CGPoint, primaryScreen: CGRect) -> CGPoint {
        CGPoint(x: point.x, y: primaryScreen.maxY - point.y)
    }

    mutating func reset() {
        enteredAt = nil
        needsExit = true
    }

    @discardableResult mutating func updateScreens(_ next: [CGRect]) -> Bool {
        guard next != screens else { return false }
        screens = next
        reset()
        return true
    }

    func remainingDwell(at now: TimeInterval) -> TimeInterval? {
        guard !needsExit, let enteredAt else { return nil }
        return max(0, dwell - (now - enteredAt))
    }

    mutating func update(inside: Bool, allowed: Bool, now: TimeInterval) -> Bool {
        guard inside else {
            enteredAt = nil
            needsExit = false
            return false
        }
        guard allowed else { reset(); return false }
        guard !needsExit else { return false }
        guard let enteredAt else { self.enteredAt = now; return false }
        guard now - enteredAt >= dwell else { return false }
        reset()
        return true
    }
}
