import Foundation

struct HoverDismissState {
    private var hasEntered = false
    private var outsideSince: TimeInterval?

    mutating func shouldHide(insidePanel: Bool, insideOpeningCorner: Bool, busy: Bool, now: TimeInterval) -> Bool {
        if insidePanel {
            hasEntered = true
            outsideSince = nil
            return false
        }
        if busy || (!hasEntered && insideOpeningCorner) {
            outsideSince = nil
            return false
        }
        guard let outsideSince else { self.outsideSince = now; return false }
        // Allow the first trip from the screen corner to the inset panel.
        // After entry, a short delay prevents flicker at the panel edge.
        return now - outsideSince >= (hasEntered ? 0.2 : 1.0)
    }
}
