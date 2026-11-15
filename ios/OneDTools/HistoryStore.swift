import Foundation

// 历史记录：Application Support/OneDTools/history.json 追加式存储。
// 条目 = {时间, 页, 输入快照, 主要输出}；上限 200 条（超出淘汰最旧）；
// 滑动删除即时落盘；导入 = 与现有记录按 id 去重合并后按时间倒序截断。
struct HistoryEntry: Codable, Identifiable, Equatable {
    var id = UUID()
    var date = Date()
    var page: String
    var inputs: [String: String]
    var outputs: [String: String]
}

final class HistoryStore: ObservableObject {
    static let cap = 200

    @Published private(set) var entries: [HistoryEntry] = []

    private var fileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("OneDTools", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("history.json")
    }

    init() {
        load()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let list = try? JSONDecoder().decode([HistoryEntry].self, from: data) else { return }
        entries = list
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(entries) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    /// 新记录置顶插入，超限淘汰最旧
    func add(page: String, inputs: [String: String], outputs: [String: String]) {
        entries.insert(HistoryEntry(page: page, inputs: inputs, outputs: outputs), at: 0)
        trim()
        persist()
    }

    /// 滑动删除（纯 Foundation 实现，本文件不依赖 SwiftUI 的 remove(atOffsets:) 扩展）
    func remove(at offsets: IndexSet) {
        var list = entries
        for index in offsets.sorted(by: >) where list.indices.contains(index) {
            list.remove(at: index)
        }
        entries = list
        persist()
    }

    /// 导入合并：按 id 去重，按时间倒序重排，截断到上限
    func importData(_ data: Data) throws {
        let incoming = try JSONDecoder().decode([HistoryEntry].self, from: data)
        let known = Set(entries.map(\.id))
        let fresh = incoming.filter { !known.contains($0.id) }
        guard !fresh.isEmpty else { return }
        entries = (entries + fresh).sorted { $0.date > $1.date }
        trim()
        persist()
    }

    /// 导出用 JSON 文本
    func jsonText() -> String {
        guard let data = try? JSONEncoder().encode(entries) else { return "[]" }
        return String(data: data, encoding: .utf8) ?? "[]"
    }

    private func trim() {
        if entries.count > Self.cap {
            entries.removeLast(entries.count - Self.cap)
        }
    }
}
