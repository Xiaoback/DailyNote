import Foundation
import Darwin

// Both the app and the extension use this store. Every read/modify/write is
// protected by the same interprocess lock; writes are atomic.
final class NoteStore {
    let root: URL
    private let fm = FileManager.default

    init(root: URL) throws {
        self.root = root
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        try fm.createDirectory(at: root.appendingPathComponent("Backups"), withIntermediateDirectories: true)
    }

    static func configured() throws -> NoteStore {
        if let override = ProcessInfo.processInfo.environment["DAILYNOTE_DATA_DIR"], !override.isEmpty {
            return try NoteStore(root: URL(fileURLWithPath: override, isDirectory: true))
        }
        // The command-line preview writes only inside this project.
        if let previewPath = Bundle.main.object(forInfoDictionaryKey: "DailyNotePreviewDataDirectory") as? String,
           !previewPath.isEmpty {
            return try NoteStore(root: URL(fileURLWithPath: previewPath, isDirectory: true))
        }
        #if DAILYNOTE_STANDALONE
        let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                  appropriateFor: nil, create: true)
        return try NoteStore(root: support.appendingPathComponent("DailyNote", isDirectory: true))
        #else
        guard let group = Bundle.main.object(forInfoDictionaryKey: "DailyNoteAppGroup") as? String,
              !group.isEmpty, !group.contains("$("),
              let container = fmContainer(group) else { throw NoteError.sharedContainerUnavailable }
        return try NoteStore(root: container.appendingPathComponent("DailyNote", isDirectory: true))
        #endif
    }

    private static func fmContainer(_ group: String) -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)
    }

    private func url(for day: String) throws -> URL {
        guard DayKey.isValid(day) else { throw NoteError.invalidDay }
        return root.appendingPathComponent("\(day).json")
    }

    private func locked<T>(_ action: () throws -> T) throws -> T {
        let path = root.appendingPathComponent(".store.lock").path
        let descriptor = Darwin.open(path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw NoteError.storage("无法打开存储锁。") }
        defer { Darwin.close(descriptor) }
        guard flock(descriptor, LOCK_EX) == 0 else { throw NoteError.storage("无法锁定存储。") }
        defer { flock(descriptor, LOCK_UN) }
        return try action()
    }

    private func read(_ day: String) throws -> NoteDocument {
        let file = try url(for: day)
        guard fm.fileExists(atPath: file.path) else { return .empty(day: day) }
        let data = try Data(contentsOf: file)
        var doc: NoteDocument
        do { doc = try JSONDecoder().decode(NoteDocument.self, from: data) }
        catch { throw NoteError.damagedFile(file.lastPathComponent) }
        guard doc.schemaVersion == 1 else { throw NoteError.unsupportedVersion }
        guard doc.day == day, Set(doc.blocks.map(\.id)).count == doc.blocks.count else {
            throw NoteError.damagedFile(file.lastPathComponent)
        }
        doc.blocks = NoteOutline.completingParents(doc.blocks)
        return doc
    }

    func load(_ day: String) throws -> NoteDocument { try locked { try read(day) } }

    private func write(_ doc: NoteDocument) throws {
        let file = try url(for: doc.day)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(doc)
        if fm.fileExists(atPath: file.path) {
            let folder = root.appendingPathComponent("Backups/\(doc.day)", isDirectory: true)
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            let backup = folder.appendingPathComponent("\(UUID().uuidString).json")
            try fm.copyItem(at: file, to: backup)
            let files = try fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.creationDateKey])
                .sorted { left, right in
                    let leftDate = (try? left.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date.distantPast
                    let rightDate = (try? right.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date.distantPast
                    return leftDate > rightDate
                }
            for old in files.dropFirst(20) { try fm.removeItem(at: old) }
        }
        try data.write(to: file, options: .atomic)
    }

    // Merge remote checkbox changes into a draft without discarding the user's typing.
    // An explicit local state change wins; otherwise the latest widget state wins.
    func save(_ draft: NoteDocument, basedOn base: NoteDocument) throws -> NoteDocument {
        guard draft.schemaVersion == 1 else { throw NoteError.unsupportedVersion }
        guard draft.day == base.day, Set(draft.blocks.map(\.id)).count == draft.blocks.count else {
            throw NoteError.storage("便笺结构无效。")
        }
        return try locked {
            let remote = try read(draft.day)
            var result = draft
            let original = Dictionary(uniqueKeysWithValues: base.blocks.map { ($0.id, $0) })
            let latest = Dictionary(uniqueKeysWithValues: remote.blocks.map { ($0.id, $0) })
            if remote.revision != base.revision {
                result.blocks = draft.blocks.map { block in
                    var merged = block
                    if block.kind == .task, let old = original[block.id], let current = latest[block.id],
                       current.kind == .task, block.state == old.state { merged.state = current.state }
                    if let old = original[block.id], let current = latest[block.id], block.collapsed == old.collapsed {
                        merged.collapsed = current.collapsed
                    }
                    return merged
                }
                result.carriedTaskIDs = Array(Set(result.carriedTaskIDs + remote.carriedTaskIDs))
            }
            result.blocks = NoteOutline.completingParents(result.blocks)
            result.revision = remote.revision + 1
            result.updatedAt = Date()
            try write(result)
            return result
        }
    }

    func setTask(day: String, id: UUID, state: TaskState) throws {
        try locked {
            var doc = try read(day)
            guard let index = doc.blocks.firstIndex(where: { $0.id == id && $0.kind == .task }) else { return }
            doc.blocks[index].state = state
            doc.blocks = NoteOutline.completingParents(doc.blocks)
            doc.revision += 1
            doc.updatedAt = Date()
            try write(doc)
        }
    }

    func setCollapsed(day: String, id: UUID, collapsed: Bool) throws {
        try locked {
            var doc = try read(day)
            guard let index = doc.blocks.firstIndex(where: { $0.id == id }),
                  !NoteOutline.children(of: id, in: doc.blocks).isEmpty else { return }
            doc.blocks[index].collapsed = collapsed
            doc.revision += 1
            doc.updatedAt = Date()
            try write(doc)
        }
    }

    func days() throws -> [String] {
        try locked {
            try fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "json" }
                .map { $0.deletingPathExtension().lastPathComponent }
                .filter(DayKey.isValid).sorted(by: >)
        }
    }

    func pendingBefore(_ day: String) throws -> [(String, NoteBlock)] {
        let previous = try days().filter { $0 < day }
        // Inspect only the latest existing day: old carried tasks must not reappear.
        guard let last = previous.first else { return [] }
        let current = try load(day)
        let carried = Set(current.carriedTaskIDs)
        return try load(last).blocks.filter {
            $0.kind == .task && $0.state == .pending && !carried.contains($0.id)
        }.map { (last, $0) }
    }

    func carryForward(to day: String) throws -> NoteDocument {
        try locked {
            let previous = try fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "json" }.map { $0.deletingPathExtension().lastPathComponent }
                .filter { DayKey.isValid($0) && $0 < day }.sorted(by: >)
            var current = try read(day)
            guard let last = previous.first else { return current }
            let tasks = try read(last).blocks.filter { $0.kind == .task && $0.state == .pending }
            for task in tasks where !current.carriedTaskIDs.contains(task.id) {
                var copy = task
                copy.id = UUID()
                copy.level = 0
                copy.collapsed = false
                current.blocks.append(copy)
                current.carriedTaskIDs.append(task.id)
            }
            current.revision += 1
            current.updatedAt = Date()
            try write(current)
            return current
        }
    }
}

extension NoteStore {
    func loadTemplates() throws -> [NoteTemplate] {
        try locked {
            let url = root.appendingPathComponent("templates.json")
            guard fm.fileExists(atPath: url.path) else { return [.dailyGroups] }
            do { return try JSONDecoder().decode([NoteTemplate].self, from: Data(contentsOf: url)) }
            catch { throw NoteError.damagedFile("templates.json") }
        }
    }

    func saveTemplates(_ templates: [NoteTemplate]) throws {
        try locked {
            let url = root.appendingPathComponent("templates.json")
            // Keep the previous library recoverable, including deleted templates.
            if fm.fileExists(atPath: url.path) {
                let old = try Data(contentsOf: url)
                _ = try JSONDecoder().decode([NoteTemplate].self, from: old)
                try old.write(to: root.appendingPathComponent("templates.previous.json"), options: .atomic)
            }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(templates).write(to: url, options: .atomic)
        }
    }
}
