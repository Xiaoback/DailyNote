import Foundation

enum QuickNoteLayout {
    static func frame(in visibleFrame: CGRect) -> CGRect {
        let margin: CGFloat = 16
        let size = CGSize(width: min(520, visibleFrame.width - margin * 2),
                          height: min(680, visibleFrame.height - margin * 2))
        return CGRect(x: visibleFrame.maxX - margin - size.width,
                      y: visibleFrame.maxY - margin - size.height,
                      width: size.width, height: size.height)
    }
}
