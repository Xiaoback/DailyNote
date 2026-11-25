import SwiftUI

struct ContentView: View {
    @ObservedObject var model: NoteViewModel
    @ObservedObject var bridge: EditorBridge
    var dateChooserChanged: ((Bool) -> Void)? = nil
    @Environment(\.colorScheme) var colorScheme
    @State private var showHistory = false
    @State private var showTemplates = false
    @State private var chooserDate = Date()

    private var dateLabel: String {
        if model.document.day == DayKey.string() { return "TODAY / 今日便笺" }
        return model.document.day > DayKey.string() ? "PLAN / 未来便笺" : "ARCHIVE / 往日便笺"
    }

    private var paperColor: Color {
        if colorScheme == .dark {
            return Color(red: 32 / 255, green: 33 / 255, blue: 36 / 255)
        }
        switch model.paper {
        case "sage": return Color(red: 0.91, green: 0.95, blue: 0.90)
        case "rose": return Color(red: 1.0, green: 0.92, blue: 0.91)
        case "plain": return Color(red: 0.98, green: 0.98, blue: 0.97)
        default: return Color(red: 1.0, green: 0.97, blue: 0.83)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.5)
            formatBar
            if model.pendingCount > 0 && model.document.day == DayKey.string() {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.turn.down.right")
                    Text("上一张便笺还有 \(model.pendingCount) 件未完成")
                    Spacer()
                    Button("转入今天") { model.carryForward() }.buttonStyle(.plain).fontWeight(.medium)
                }
                .font(.system(size: 12)).foregroundStyle(.secondary)
                .padding(.horizontal, 24).padding(.vertical, 10)
                .background(.primary.opacity(0.035))
            }
            ZStack(alignment: .topLeading) {
                if model.document.blocks.allSatisfy({ $0.text.isEmpty && $0.kind == .paragraph }) {
                    Text(model.document.day > DayKey.string() ? "提前安排这一天。\n\n写下计划，也留一点自由发挥的空间。" : "想写些什么？\n\n记录想法，也给重要的事留个位置。")
                        .font(.system(size: model.fontSize)).lineSpacing(9)
                        .foregroundStyle(.tertiary).padding(.leading, 29).padding(.top, 24)
                        .allowsHitTesting(false)
                }
                RichNoteEditor(model: model, bridge: bridge)
            }
            Divider().opacity(0.45)
            footer
        }
        .background(paperColor)
        .preferredColorScheme(model.appearanceMode == "dark" ? .dark : (model.appearanceMode == "light" ? .light : nil))
        .frame(minWidth: 480, minHeight: 470)
        .alert("便笺需要留意", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("查看备份") { model.openBackups() }
            Button("好", role: .cancel) { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
        .onChange(of: model.fontSize) { _, _ in model.appearanceChanged() }
        .onChange(of: model.paper) { _, _ in model.appearanceChanged() }
        .onChange(of: model.fontFamily) { _, _ in model.appearanceChanged() }
        .onChange(of: model.appearanceMode) { _, _ in model.appearanceChanged() }
        .onChange(of: showHistory) { _, _ in dateChooserChanged?(showHistory || showTemplates) }
        .onChange(of: showTemplates) { _, _ in dateChooserChanged?(showHistory || showTemplates) }
        .sheet(isPresented: $showTemplates) {
            TemplateLibraryView(model: model) { template in bridge.textView?.insertTemplate(template) }
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 7) {
                    Circle().fill(Color(red: 0.72, green: 0.47, blue: 0.16)).frame(width: 6, height: 6)
                    Text(dateLabel)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced)).tracking(1.5)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 9) {
                    Button { model.moveDay(by: -1) } label: {
                        Image(systemName: "chevron.left").frame(width: 24, height: 28).contentShape(Rectangle())
                    }.buttonStyle(.plain).font(.system(size: 16, weight: .medium)).help("前一天").accessibilityLabel("前一天便笺")
                    Text(DayKey.title(model.document.day))
                        .font(.system(size: 24, weight: .semibold, design: .rounded))
                        .lineLimit(1).minimumScaleFactor(0.8)
                    Button { model.moveDay(by: 1) } label: {
                        Image(systemName: "chevron.right").frame(width: 24, height: 28).contentShape(Rectangle())
                    }.buttonStyle(.plain).font(.system(size: 16, weight: .medium)).help("后一天").accessibilityLabel("后一天便笺")
                    Button {
                        chooserDate = DayKey.date(model.document.day) ?? Date()
                        showHistory.toggle()
                    } label: { Image(systemName: "calendar").frame(width: 28, height: 28).contentShape(Rectangle()) }
                        .buttonStyle(.plain).font(.system(size: 16, weight: .medium)).help("选择日期 · 打开或创建便笺").accessibilityLabel("选择便笺日期")
                        .popover(isPresented: $showHistory, arrowEdge: .bottom) {
                            DateChooserView(model: model, date: $chooserDate) { showHistory = false }
                        }
                }
            }
            Spacer()
            if model.document.day != DayKey.string() {
                Button("回到今天") { model.select(day: DayKey.string()) }.buttonStyle(.borderless).font(.system(size: 12))
            }
            Menu {
                Section("外观") {
                    ForEach([("system", "跟随系统"), ("light", "浅色"), ("dark", "暗夜黑")], id: \.0) { key, label in
                        Button { model.appearanceMode = key } label: {
                            if model.appearanceMode == key { Label(label, systemImage: "checkmark") } else { Text(label) }
                        }
                    }
                }
                Section("正文字体") {
                    ForEach([("system", "系统字体"), ("wenkai", "霞鹜文楷")], id: \.0) { key, label in
                        Button { model.fontFamily = key } label: {
                            if model.fontFamily == key { Label(label, systemImage: "checkmark") } else { Text(label) }
                        }
                    }
                }
                Section("纸张颜色") {
                    ForEach([("butter", "奶油黄"), ("sage", "鼠尾草绿"), ("rose", "浅玫瑰"), ("plain", "素白")], id: \.0) { key, label in
                        Button { model.paper = key } label: {
                            if model.paper == key { Label(label, systemImage: "checkmark") } else { Text(label) }
                        }
                    }
                }
                Section("默认字号") {
                    ForEach([14, 16, 18, 20, 24], id: \.self) { size in
                        Button("\(size) 磅\(Int(model.fontSize) == size ? " ✓" : "")") { model.fontSize = CGFloat(size) }
                    }
                }
                Divider()
                Button("导出当前便笺…", action: model.export)
                Button("导出可恢复备份…", action: model.exportBackup)
                Button("导入便笺备份…", action: model.importBackup)
                Button("查看本地备份", action: model.openBackups)
            } label: { Image(systemName: "ellipsis.circle").frame(width: 28, height: 28) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("便笺选项")
        }
        .padding(.horizontal, 24).padding(.top, 23).padding(.bottom, 20)
    }

    private var formatBar: some View {
        HStack(spacing: 4) {
            tool("bold", "加粗 ⌘B", .bold)
            tool("italic", "斜体 ⌘I", .italic)
            tool("strikethrough", "删除线 ⇧⌘X", .strike)
            tool("highlighter", "高亮所选文字 ⇧⌘H", .highlight)
            Rectangle().fill(.primary.opacity(0.12)).frame(width: 1, height: 16).padding(.horizontal, 8)
            tool("list.bullet", "项目符号 ⇧⌘7", .bullet)
            tool("checklist", "待办事项 ⇧⌘L", .task)
            tool("checkmark.circle", "切换事项状态：未完成 → 完成 → 取消", .state)
            Menu {
                Button("增加一级缩进（Tab）") { bridge.perform(.indent) }
                Button("减少一级缩进（Shift+Tab）") { bridge.perform(.outdent) }
                Divider()
                Button("折叠 / 展开项目") { bridge.perform(.fold) }
                Divider()
                Section("插入每日模板") {
                    ForEach(model.templates) { template in
                        Button(template.name) { bridge.textView?.insertTemplate(template) }.disabled(model.loadFailed)
                    }
                }
                Button("管理每日模板…") { showTemplates = true }
            } label: { Image(systemName: "list.bullet.indent").frame(width: 27, height: 29) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("项目层级与折叠")
            Spacer()
            tool("arrow.uturn.backward", "撤销 ⌘Z", .undo)
            tool("arrow.uturn.forward", "重做 ⇧⌘Z", .redo)
        }
        .padding(.horizontal, 19).padding(.vertical, 8)
        .background(.primary.opacity(0.025))
    }

    private func tool(_ image: String, _ help: String, _ action: EditorAction) -> some View {
        Button { bridge.perform(action) } label: {
            Image(systemName: image).font(.system(size: 14, weight: .medium)).frame(width: 32, height: 29).contentShape(Rectangle())
        }
        .buttonStyle(.plain).foregroundStyle(.primary.opacity(0.8)).help(help).accessibilityLabel(help)
        .disabled(model.loadFailed)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Image(systemName: model.saveStatus.hasPrefix("已保存") ? "checkmark.circle" : "circle.dotted")
            Text(model.saveStatus)
            Spacer()
            if model.document.taskCount > 0 { Text("\(model.document.completedCount)/\(model.document.taskCount) 已完成") }
            else { Text("Tab 增加缩进 · Shift+Tab 减少缩进") }
        }
        .font(.system(size: 11)).foregroundStyle(.secondary)
        .padding(.horizontal, 24).padding(.vertical, 13)
    }

}

struct DateChooserView: View {
    @ObservedObject var model: NoteViewModel
    @Binding var date: Date
    var dismiss: () -> Void
    private var day: String { DayKey.string(date) }
    private var exists: Bool { model.days.contains(day) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("选择或创建便笺").font(.headline)
            DatePicker("选择日期", selection: $date, displayedComponents: .date)
                .datePickerStyle(.graphical).labelsHidden()
                .environment(\.locale, Locale(identifier: "zh_CN"))
            HStack {
                DatePicker("指定日期", selection: $date, displayedComponents: .date)
                    .datePickerStyle(.field).labelsHidden().frame(width: 135)
                    .environment(\.locale, Locale(identifier: "zh_CN"))
                Spacer()
                Button(exists ? "打开便笺" : "创建这天的便笺") {
                    if model.select(day: day, createIfMissing: true) { dismiss() }
                }.buttonStyle(.borderedProminent).tint(.brown)
            }
            HStack {
                Button("今天") { date = Date() }
                Button("明天") { date = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date() }
                Spacer()
            }.buttonStyle(.borderless).font(.system(size: 12))
            if !model.days.isEmpty {
                Divider()
                Text("已有便笺").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(model.days, id: \.self) { day in
                            Button {
                                if model.select(day: day) { dismiss() }
                            } label: {
                                HStack {
                                    Text(day)
                                    Spacer()
                                    if day == model.document.day { Image(systemName: "checkmark") }
                                }.padding(.vertical, 7).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                        }
                    }
                }.frame(maxHeight: 150)
            }
        }.padding(20).frame(width: 310)
    }
}
