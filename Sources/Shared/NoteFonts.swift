import AppKit
import CoreText

enum NoteFonts {
    private static let registration: Void = {
        let folder: URL?
        if let path = ProcessInfo.processInfo.environment["DAILYNOTE_FONT_DIR"] {
            folder = URL(fileURLWithPath: path)
        } else { folder = Bundle.main.resourceURL?.appendingPathComponent("Fonts") }
        guard let folder else { return }
        for name in ["LXGWWenKai-Regular.ttf", "LXGWWenKai-Medium.ttf"] {
            let url = folder.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: url.path) { CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil) }
        }
    }()
    static func register() { _ = registration }
    static func font(family: String = "system", size: CGFloat, bold: Bool = false, italic: Bool = false) -> NSFont {
        register()
        var font: NSFont
        if family == "wenkai", let custom = NSFont(name: bold ? "LXGWWenKai-Medium" : "LXGWWenKai-Regular", size: size) {
            font = custom
        } else { font = NSFont.systemFont(ofSize: size, weight: bold ? .bold : .regular) }
        if italic { font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask) }
        return font
    }
}
