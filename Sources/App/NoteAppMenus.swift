import AppKit

@MainActor
final class NoteAppMenus: NSObject, NSMenuItemValidation {
    private let model: NoteViewModel
    private let bridge: EditorBridge
    private let hotCorner: HotCornerController
    private let showQuick: () -> Void
    private let showMain: () -> Void
    private var formats: [EditorAction] = []

    init(model: NoteViewModel, bridge: EditorBridge, hotCorner: HotCornerController, showQuick: @escaping () -> Void, showMain: @escaping () -> Void) {
        self.model = model
        self.bridge = bridge
        self.hotCorner = hotCorner
        self.showQuick = showQuick
        self.showMain = showMain
        super.init()
        build()
    }

    private func build() {
        let root = NSMenu()
        NSApp.mainMenu = root
        func menu(_ title: String) -> NSMenu {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            let submenu = NSMenu(title: title)
            root.addItem(item)
            root.setSubmenu(submenu, for: item)
            return submenu
        }
        func add(_ title: String, to menu: NSMenu, action: Selector, key: String = "",
                 modifiers: NSEvent.ModifierFlags = .command, target: AnyObject? = nil) {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.keyEquivalentModifierMask = modifiers
            item.target = target
            menu.addItem(item)
        }
        let app = menu("今日便笺")
        add("关于今日便笺", to: app, action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)))
        app.addItem(.separator())
        add("右上角触发便笺", to: app, action: #selector(toggleCorner(_:)), target: self)
        app.addItem(.separator())
        let services = NSMenu(title: "服务")
        let serviceItem = NSMenuItem(title: "服务", action: nil, keyEquivalent: "")
        serviceItem.submenu = services
        app.addItem(serviceItem)
        NSApp.servicesMenu = services
        app.addItem(.separator())
        add("隐藏今日便笺", to: app, action: #selector(NSApplication.hide(_:)), key: "h")
        add("隐藏其他", to: app, action: #selector(NSApplication.hideOtherApplications(_:)), key: "h", modifiers: [.command, .option])
        add("全部显示", to: app, action: #selector(NSApplication.unhideAllApplications(_:)))
        app.addItem(.separator())
        add("退出今日便笺", to: app, action: #selector(NSApplication.terminate(_:)), key: "q")

        let file = menu("文件")
        add("打开右侧编辑面板", to: file, action: #selector(openQuick), key: "n", modifiers: [.command, .option], target: self)
        add("打开主窗口", to: file, action: #selector(openMain), key: "n", target: self)
        file.addItem(.separator())
        add("导出当前便笺…", to: file, action: #selector(exportNote), key: "e", modifiers: [.command, .shift], target: self)
        add("导出可恢复备份…", to: file, action: #selector(exportBackup), target: self)
        add("导入便笺备份…", to: file, action: #selector(importBackup), target: self)
        file.addItem(.separator())
        add("关闭窗口", to: file, action: #selector(NSWindow.performClose(_:)), key: "w")

        let edit = menu("编辑")
        add("撤销", to: edit, action: Selector(("undo:")), key: "z")
        add("重做", to: edit, action: Selector(("redo:")), key: "z", modifiers: [.command, .shift])
        edit.addItem(.separator())
        add("剪切", to: edit, action: #selector(NSText.cut(_:)), key: "x")
        add("拷贝", to: edit, action: #selector(NSText.copy(_:)), key: "c")
        add("粘贴", to: edit, action: #selector(NSText.paste(_:)), key: "v")
        add("全选", to: edit, action: #selector(NSText.selectAll(_:)), key: "a")

        let format = menu("格式")
        let definitions: [(String, String, NSEvent.ModifierFlags, EditorAction)] = [
            ("加粗", "b", .command, .bold), ("斜体", "i", .command, .italic),
            ("删除线", "x", [.command, .shift], .strike), ("高亮", "h", [.command, .shift], .highlight),
            ("放大所选文字", "+", .command, .larger), ("缩小所选文字", "-", .command, .smaller),
            ("项目符号", "7", [.command, .shift], .bullet), ("待办事项", "l", [.command, .shift], .task),
            ("切换事项状态", "k", [.command, .shift], .state), ("增加一级缩进", "]", .command, .indent),
            ("减少一级缩进", "[", .command, .outdent), ("折叠 / 展开项目", ".", [.command, .shift], .fold)
        ]
        for (title, key, modifiers, operation) in definitions {
            let item = NSMenuItem(title: title, action: #selector(performFormat(_:)), keyEquivalent: key)
            item.keyEquivalentModifierMask = modifiers
            item.target = self
            item.tag = formats.count
            formats.append(operation)
            format.addItem(item)
        }
        let windows = menu("窗口")
        add("最小化", to: windows, action: #selector(NSWindow.performMiniaturize(_:)), key: "m")
        NSApp.windowsMenu = windows
    }

    @objc private func openQuick() { showQuick() }
    @objc private func toggleCorner(_ sender: NSMenuItem) {
        hotCorner.isEnabled.toggle()
        sender.state = hotCorner.isEnabled ? .on : .off
    }
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(toggleCorner(_:)) {
            menuItem.state = hotCorner.isEnabled ? .on : .off
        }
        return true
    }
    @objc private func openMain() { showMain() }
    @objc private func exportNote() { model.export() }
    @objc private func exportBackup() { model.exportBackup() }
    @objc private func importBackup() { model.importBackup() }
    @objc private func performFormat(_ sender: NSMenuItem) {
        guard formats.indices.contains(sender.tag) else { return }
        bridge.perform(formats[sender.tag])
    }
}
