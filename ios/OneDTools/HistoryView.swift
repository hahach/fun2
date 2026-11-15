import SwiftUI
import UniformTypeIdentifiers

// 历史页：列表展示（时间/页/输入快照/主要输出）、滑动删除、
// 导出 = ShareLink 分享 history.json 文本、导入 = fileImporter（JSON/文本）合并。
struct HistoryView: View {
    @EnvironmentObject private var history: HistoryStore
    @State private var showImporter = false
    @State private var importMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if history.entries.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "tray")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        Text("暂无历史记录")
                            .foregroundColor(.secondary)
                        Text("在计算页点「存历史」保留结果")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                } else {
                    entryList
                }
            }
            .navigationTitle("历史")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    ShareLink(item: history.jsonText()) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .disabled(history.entries.isEmpty)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showImporter = true
                    } label: {
                        Image(systemName: "square.and.arrow.down")
                    }
                }
            }
            .fileImporter(isPresented: $showImporter,
                          allowedContentTypes: [UTType.json, UTType.plainText],
                          allowsMultipleSelection: false,
                          onCompletion: handleImport)
            .alert("导入结果", isPresented: messageBinding) {
                Button("好", role: .cancel) {}
            } message: {
                Text(importMessage ?? "")
            }
        }
    }

    private var entryList: some View {
        List {
            ForEach(history.entries) { entry in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(entry.page)
                            .font(.headline)
                        Spacer()
                        Text(entry.date.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Text(verbatim: joined(entry.inputs))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                    Text(verbatim: joined(entry.outputs))
                        .font(.footnote.monospacedDigit())
                        .lineLimit(3)
                }
                .padding(.vertical, 2)
            }
            .onDelete { offsets in
                history.remove(at: offsets)
            }
        }
    }

    private func joined(_ d: [String: String]) -> String {
        d.sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "　")
    }

    private var messageBinding: Binding<Bool> {
        Binding(get: { importMessage != nil },
                set: { if !$0 { importMessage = nil } })
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            importMessage = "读取失败：\(error.localizedDescription)"
        case .success(let urls):
            guard let url = urls.first else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                let data = try Data(contentsOf: url)
                let before = history.entries.count
                try history.importData(data)
                let added = history.entries.count - before
                importMessage = added > 0 ? "已合并 \(added) 条记录（上限 \(HistoryStore.cap) 条）"
                                          : "没有新记录（全部与现有条目重复）"
            } catch {
                importMessage = "导入失败：文件不是本 App 导出的历史 JSON"
            }
        }
    }
}
