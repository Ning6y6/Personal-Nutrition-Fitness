import SwiftUI

/// This screen does not have a model context: a failed store is never replaced with an empty one.
struct StoreRecoveryView: View {
    let bootstrap: LocalStoreBootstrap
    @State private var isImporting = false
    @State private var isConfirmingRestore = false
    @State private var restoredURL: URL?
    @State private var summary: LocalStoreBackupSummary?
    @State private var operationError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label("本地数据暂时无法打开", systemImage: "externaldrive.badge.exclamationmark")
                        .font(.headline)
                    Text("原数据库仍保留。不会自动删除、重建空库或清除手机记录。此时不能保证能导出打不开的数据库；请使用以前保存的备份。")
                    Text(bootstrap.failure?.localizedDescription ?? "请重试或选择已保存的食衡JSON备份。")
                        .foregroundStyle(.secondary)
                    Button("重试打开", systemImage: "arrow.clockwise", action: bootstrap.retry)
                    Button("选择已有备份", systemImage: "doc.badge.arrow.up") { isImporting = true }
                }
                if let summary {
                    Section("备份验证结果") {
                        LabeledContent("记录数", value: "\(summary.totalRecords)")
                        Text("已在独立文件库恢复并重新打开核对。原数据库不会被覆盖，确认后切换到这个恢复库。")
                        if !summary.imageWarnings.isEmpty {
                            Text("\(summary.imageWarnings.count)个照片引用不含图片文件；图片无法从本备份恢复。")
                        }
                        Button("确认使用恢复库", systemImage: "arrow.triangle.2.circlepath") {
                            isConfirmingRestore = true
                        }
                    }
                }
            }
            .navigationTitle("数据恢复")
            .navigationBarTitleDisplayMode(.inline)
            .fileImporter(isPresented: $isImporting, allowedContentTypes: [.json]) { result in
                switch result {
                case .success(let url): verifyBackup(at: url)
                case .failure(let error): operationError = error.localizedDescription
                }
            }
            .confirmationDialog("切换到已验证的恢复库？", isPresented: $isConfirmingRestore, titleVisibility: .visible) {
                Button("使用恢复库", action: activateRestore)
                Button("取消", role: .cancel) {}
            } message: {
                Text("原数据库保留不动。今后记录会保存到恢复库；本操作不是向旧库合并数据。")
            }
            .alert("恢复未完成", isPresented: Binding(
                get: { operationError != nil },
                set: { if !$0 { operationError = nil } }
            )) {
                Button("好", role: .cancel) {}
            } message: { Text(operationError ?? "原数据库未改变。") }
        }
    }

    private func verifyBackup(at url: URL) {
        restoredURL = nil
        summary = nil
        do {
            let data = try BackupImportReader.read(from: url)
            let candidate = try LocalStoreBackupService.stageRestore(data: data, directory: bootstrap.restoreDirectory)
            summary = try LocalStoreBackupService.inspect(data: data)
            restoredURL = candidate
        } catch { operationError = error.localizedDescription }
    }

    private func activateRestore() {
        guard let restoredURL else { return }
        do { try bootstrap.activateRestoredStore(at: restoredURL) }
        catch { operationError = error.localizedDescription }
    }
}
