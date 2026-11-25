import Foundation

enum TaskState: String, Codable, CaseIterable {
    case pending, completed, cancelled
    var symbol: String {
        switch self { case .pending: return "○"; case .completed: return "●"; case .cancelled: return "✕" }
    }
    static func atStart(of line: String) -> TaskState? {
        // Accept text copied from the first version as well as the new circles.
        if line.hasPrefix("○ ") || line.hasPrefix("☐ ") { return .pending }
        if line.hasPrefix("● ") || line.hasPrefix("✓ ") { return .completed }
        if line.hasPrefix("✕ ") { return .cancelled }
        return nil
    }
    var next: TaskState {
        switch self { case .pending: return .completed; case .completed: return .cancelled; case .cancelled: return .pending }
    }
}

enum BlockKind: String, Codable { case paragraph, bullet, task }

struct TextRun: Codable, Equatable {
    var text: String
    var bold = false
    var italic = false
    var strikethrough = false
    var pointSize: Double? = nil
    var highlighted = false

    init(text: String, bold: Bool = false, italic: Bool = false, strikethrough: Bool = false,
         pointSize: Double? = nil, highlighted: Bool = false) {
        self.text = text
        self.bold = bold
        self.italic = italic
        self.strikethrough = strikethrough
        self.pointSize = pointSize
        self.highlighted = highlighted
    }

    private enum CodingKeys: String, CodingKey { case text, bold, italic, strikethrough, pointSize, highlighted }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        text = try values.decode(String.self, forKey: .text)
        bold = try values.decodeIfPresent(Bool.self, forKey: .bold) ?? false
        italic = try values.decodeIfPresent(Bool.self, forKey: .italic) ?? false
        strikethrough = try values.decodeIfPresent(Bool.self, forKey: .strikethrough) ?? false
        pointSize = try values.decodeIfPresent(Double.self, forKey: .pointSize).map { min(72, max(8, $0)) }
        highlighted = try values.decodeIfPresent(Bool.self, forKey: .highlighted) ?? false
    }
}

struct NoteBlock: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var kind: BlockKind = .paragraph
    var state: TaskState = .pending
    var runs: [TextRun] = []
    var level = 0
    var collapsed = false
    var markerPointSize: Double? = nil
    var text: String { runs.map(\.text).joined() }
    var usesSquareMarker: Bool { level >= 2 }
    var isResolved: Bool { kind == .task && state != .pending }

    init(id: UUID = UUID(), kind: BlockKind = .paragraph, state: TaskState = .pending,
         runs: [TextRun] = [], level: Int = 0, collapsed: Bool = false, markerPointSize: Double? = nil) {
        self.id = id; self.kind = kind; self.state = state; self.runs = runs
        self.level = max(0, level); self.collapsed = collapsed; self.markerPointSize = markerPointSize
    }
    private enum CodingKeys: String, CodingKey { case id, kind, state, runs, level, collapsed, markerPointSize }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        kind = try values.decode(BlockKind.self, forKey: .kind)
        state = try values.decode(TaskState.self, forKey: .state)
        runs = try values.decode([TextRun].self, forKey: .runs)
        level = max(0, try values.decodeIfPresent(Int.self, forKey: .level) ?? 0)
        collapsed = try values.decodeIfPresent(Bool.self, forKey: .collapsed) ?? false
        markerPointSize = try values.decodeIfPresent(Double.self, forKey: .markerPointSize).map { min(72, max(8, $0)) }
    }
}

enum NoteOutline {
    // Folded descendants participate too. Resolve from leaves to roots so
    // completing the last leaf can complete every task ancestor in one pass.
    static func completingParents(_ blocks: [NoteBlock]) -> [NoteBlock] {
        var result = blocks
        for index in result.indices.reversed() where result[index].kind == .task {
            let descendants = result.dropFirst(index + 1).prefix { $0.level > result[index].level }.filter { $0.kind == .task }
            guard !descendants.isEmpty else { continue }
            if descendants.allSatisfy({ $0.state == .completed }) { result[index].state = .completed }
            else if result[index].state == .completed { result[index].state = .pending }
        }
        return result
    }

    static func children(of id: UUID, in blocks: [NoteBlock]) -> [NoteBlock] {
        guard let index = blocks.firstIndex(where: { $0.id == id }) else { return [] }
        return Array(blocks.dropFirst(index + 1).prefix { $0.level > blocks[index].level })
    }
    static func visible(_ blocks: [NoteBlock]) -> [NoteBlock] {
        var hiddenLevel: Int?
        return blocks.filter { block in
            if let level = hiddenLevel, block.level > level { return false }
            hiddenLevel = block.collapsed ? block.level : nil
            return true
        }
    }

    // Edits operate on the visible projection. Attach hidden children back to
    // their stable parent IDs before saving; deleting a folded parent promotes
    // its children rather than silently deleting unseen content.
    static func merging(_ visible: [NoteBlock], into source: [NoteBlock]) -> [NoteBlock] {
        var hidden: [UUID: [NoteBlock]] = [:]
        for parent in Self.visible(source) where parent.collapsed {
            hidden[parent.id] = children(of: parent.id, in: source)
        }
        var result: [NoteBlock] = []
        var used = Set<UUID>()
        for block in visible {
            result.append(block); used.insert(block.id)
            if let children = hidden.removeValue(forKey: block.id) {
                for child in children where !used.contains(child.id) { result.append(child); used.insert(child.id) }
            }
        }
        for parent in source where hidden[parent.id] != nil {
            for child in hidden[parent.id]! where !used.contains(child.id) {
                var promoted = child; promoted.level = max(0, child.level - parent.level - 1)
                result.append(promoted); used.insert(child.id)
            }
        }
        if !result.isEmpty { result[0].level = 0 }
        return result
    }
}

struct NoteDocument: Codable, Equatable {
    var schemaVersion = 1
    var day: String
    var revision = 0
    var updatedAt = Date()
    var blocks: [NoteBlock] = []
    // Records the source task IDs, so carrying tasks forward is idempotent.
    var carriedTaskIDs: [UUID] = []
    var taskCount: Int { blocks.filter { $0.kind == .task }.count }
    var completedCount: Int { blocks.filter { $0.kind == .task && $0.state == .completed }.count }

    static func empty(day: String) -> NoteDocument { NoteDocument(day: day) }
    static func example(day: String) -> NoteDocument {
        NoteDocument(day: day, blocks: [
            NoteBlock(runs: [TextRun(text: "今天最重要的事", bold: true)]),
            NoteBlock(runs: [TextRun(text: "留一点空间，写下今天的想法。")]),
            NoteBlock(kind: .task, runs: [TextRun(text: "写下第一件待办")]),
            NoteBlock(kind: .task, state: .completed, runs: [TextRun(text: "给自己留一张便笺")]),
            NoteBlock(runs: []),
            NoteBlock(runs: [TextRun(text: "随手记录", bold: true)]),
            NoteBlock(kind: .bullet, runs: [TextRun(text: "想法、安排、灵感，都可以写在这里。")])
        ])
    }
}

enum DayKey {
    static func offset(_ key: String, by days: Int, calendar: Calendar = .current) -> String? {
        guard let date = date(key, calendar: calendar),
              let result = calendar.date(byAdding: .day, value: days, to: date) else { return nil }
        return string(result, calendar: calendar)
    }
    static func string(_ date: Date = Date(), calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }
    static func date(_ key: String, calendar: Calendar = .current) -> Date? {
        let values = key.split(separator: "-").compactMap { Int($0) }
        guard values.count == 3 else { return nil }
        let result = calendar.date(from: DateComponents(year: values[0], month: values[1], day: values[2], hour: 12))
        guard let result, string(result, calendar: calendar) == key else { return nil }
        return result
    }
    static func isValid(_ key: String) -> Bool {
        key.count == 10 && key.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil && date(key) != nil
    }
    static func title(_ key: String) -> String {
        guard let date = date(key) else { return key }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = key.prefix(4) == string().prefix(4) ? "M月d日 EEEE" : "yyyy年M月d日 EEEE"
        return formatter.string(from: date)
    }
}

enum NoteError: LocalizedError {
    case invalidDay, sharedContainerUnavailable, unsupportedVersion, damagedFile(String), storage(String)
    var errorDescription: String? {
        switch self {
        case .invalidDay: return "便笺日期无效。"
        case .sharedContainerUnavailable: return "无法访问共享便笺。请检查主应用和小组件的 App Group 与签名配置。"
        case .unsupportedVersion: return "这份便笺由较新版本创建，当前版本不会覆盖它。"
        case .damagedFile(let name): return "便笺文件无法读取：\(name)。原文件已保留，请从备份恢复。"
        case .storage(let reason): return "保存失败：\(reason)"
        }
    }
}

struct NoteTemplate: Codable, Equatable, Identifiable {
    var id = UUID()
    var name: String
    var blocks: [NoteBlock]

    static var dailyGroups: NoteTemplate {
        NoteTemplate(id: UUID(uuidString: "D79CA30E-3DCF-45AA-B56E-A3C51D42918A")!, name: "上午 / 下午 / 晚上", blocks:
            ["上午", "下午", "晚上"].flatMap { title in
                [NoteBlock(kind: .bullet, runs: [TextRun(text: title, bold: true)]), NoteBlock(kind: .task, level: 1)]
            })
    }

    func instantiate() -> [NoteBlock] {
        blocks.map { block in
            var copy = block
            copy.id = UUID()
            copy.state = .pending
            copy.collapsed = false
            return copy
        }
    }
}
