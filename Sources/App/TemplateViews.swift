import SwiftUI

struct TemplateLibraryView: View {
    @ObservedObject var model: NoteViewModel
    let insert: (NoteTemplate) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var editing: NoteTemplate?
    @State private var deleting: NoteTemplate?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("每日待办模板").font(.title2.bold())
            Text("保存常用分组和事项，在任意日期重复使用。插入时，所有待办恢复为未完成。")
                .font(.callout).foregroundStyle(.secondary)
            HStack {
                Button("新建空白模板") { editing = NoteTemplate(name: "新模板", blocks: [NoteBlock()]) }
                Button("从当前便笺新建") { editing = NoteTemplate(name: "我的每日待办", blocks: model.document.blocks) }
            }
            List {
                ForEach(model.templates) { template in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(template.name).fontWeight(.medium)
                            Text("\(template.blocks.filter { $0.kind == .task }.count) 件待办 · \(template.blocks.count) 段")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("插入") { insert(template); dismiss() }.disabled(model.loadFailed)
                        Button("编辑") { editing = template }
                        Button { deleting = template } label: { Image(systemName: "trash") }.help("删除模板")
                    }.padding(.vertical, 5)
                }
            }.overlay { if model.templates.isEmpty { Text("还没有模板，点击上方按钮创建。").foregroundStyle(.secondary) } }
            if let error = model.errorMessage { Text(error).font(.caption).foregroundStyle(.red) }
            HStack { Spacer(); Button("完成") { dismiss() }.keyboardShortcut(.cancelAction) }
        }
        .padding(24).frame(width: 540, height: 450)
        .sheet(item: $editing) { template in
            TemplateDraftView(template: template, fontSize: model.fontSize, fontFamily: model.fontFamily) { model.saveTemplate($0) }
        }
        .confirmationDialog("删除模板“\(deleting?.name ?? "")”？", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button("删除模板", role: .destructive) { if let id = deleting?.id { _ = model.deleteTemplate(id) }; deleting = nil }
            Button("取消", role: .cancel) { deleting = nil }
        } message: { Text("已插入便笺的内容会保留。") }
    }
}

struct TemplateDraftView: View {
    let template: NoteTemplate
    let save: (NoteTemplate) -> Bool
    @State private var name: String
    @State private var failed = false
    @StateObject private var draft: NoteViewModel
    @StateObject private var bridge = EditorBridge()
    @Environment(\.dismiss) private var dismiss

    init(template: NoteTemplate, fontSize: CGFloat, fontFamily: String, save: @escaping (NoteTemplate) -> Bool) {
        self.template = template
        self.save = save
        _name = State(initialValue: template.name)
        let model = NoteViewModel(templateBlocks: template.blocks)
        model.fontSize = fontSize
        model.fontFamily = fontFamily
        _draft = StateObject(wrappedValue: model)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("编辑模板").font(.title2.bold())
            TextField("模板名称", text: $name).textFieldStyle(.roundedBorder)
            Text("像普通便笺一样编辑；Tab 增加一级缩进，Shift+Tab 减少一级缩进。")
                .font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 15) {
                tool("bold", "加粗", .bold)
                tool("highlighter", "高亮", .highlight)
                tool("list.bullet", "项目符号", .bullet)
                tool("checklist", "待办事项", .task)
                tool("increase.indent", "增加一级缩进", .indent)
                tool("decrease.indent", "减少一级缩进", .outdent)
                tool("chevron.down", "折叠或展开", .fold)
                Spacer()
                tool("arrow.uturn.backward", "撤销", .undo)
                tool("arrow.uturn.forward", "重做", .redo)
            }.buttonStyle(.borderless)
            RichNoteEditor(model: draft, bridge: bridge)
                .background(Color(NSColor.textBackgroundColor)).clipShape(RoundedRectangle(cornerRadius: 8))
            if failed { Text("模板保存失败，请关闭编辑框后查看错误提示。草稿仍保留在这里。").font(.caption).foregroundStyle(.red) }
            HStack {
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("保存模板") {
                    if bridge.textView?.hasMarkedText() == true { return }
                    var value = template
                    value.name = name
                    value.blocks = draft.document.blocks
                    if save(value) { dismiss() } else { failed = true }
                }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(24).frame(width: 540, height: 550)
    }

    private func tool(_ icon: String, _ label: String, _ action: EditorAction) -> some View {
        Button { bridge.textView?.perform(action) } label: { Image(systemName: icon).frame(width: 24, height: 24) }
            .help(label).accessibilityLabel(label)
    }
}
