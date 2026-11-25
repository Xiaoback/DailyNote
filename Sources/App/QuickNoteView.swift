import AppKit
import SwiftUI

struct QuickNoteView: View {
    @ObservedObject var model: NoteViewModel
    @ObservedObject var bridge: EditorBridge
    var openMain: (() -> Void)? = nil
    var close: (() -> Void)? = nil
    var dateChooserChanged: ((Bool) -> Void)? = nil
    @Environment(\.openWindow) var openWindow
    var body: some View {
        VStack(spacing: 0) {
            ContentView(model: model, bridge: bridge, dateChooserChanged: dateChooserChanged)
            Divider()
            HStack {
                Button("打开主窗口") {
                    if let openMain { openMain() }
                    else { openWindow(id: "editor") }
                    NSApp.activate(ignoringOtherApps: true)
                }
                Spacer()
                Button("收起") { close?() }
            }
            .buttonStyle(.borderless)
            .font(.system(size: 11))
            .padding(.horizontal, 24).padding(.vertical, 10)
        }
        .frame(minWidth: 480, minHeight: 510)
        .background(Color(NSColor.windowBackgroundColor))
        .onDisappear { _ = model.flush() }
    }
}
