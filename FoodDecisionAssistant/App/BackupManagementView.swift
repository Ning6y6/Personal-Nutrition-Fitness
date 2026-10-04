import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct BackupManagementView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var document = BackupFileDocument()
    @State private var isExporting = false
    @State private var isImporting = false
    @State private var summary: LocalStoreBackupSummary?
    @State private var resultMessage: String?
    @State private var operationError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("包含目标、食品、历史营养快照、模板、照片估算和校准的已保存数据。备份含个人健康信息，请保存在你控制的位置，不要上传GitHub。")
                    Button("导出全量备份", systemImage: "square.and.arrow.up", action: exportBackup)
                    Button("验证备份恢复", systemImage: "arrow.counterclockwise") {
                        isImporting = true
                    }
                } header: {
                    Text("数据保护")
                } footer: {
                    Text("当前切片将备份恢复到独立文件库并校验，不覆盖现用库。正式切换恢复库将在启动恢复切片提供。相册原图、API Key和签名材料不包含在备份中。")
                }

                if let summary {
                    Section("最近验证") {
                        LabeledContent("记录总数", value: "\(summary.totalRecords)")
                        ForEach(LocalStoreBackupEntityKind.allCases, id: \.self) { kind in
                            LabeledContent(kind.displayName, value: "\(summary.counts[kind, default: 0])")
                        }
                        if !summary.imageWarnings.isEmpty {
                            Label("\(summary.imageWarnings.count)个图片引用未包含可恢复图片；餐食数据仍已保存。", systemImage: "photo.badge.exclamationmark")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                if let resultMessage {
                    Section {
                        Label(resultMessage, systemImage: "checkmark.circle")
                    }
                }
            }
            .navigationTitle("本地备份")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .fileExporter(
                isPresented: $isExporting, document: document, contentType: .json,
                defaultFilename: "ShiHeng-backup"
            ) { result in
                switch result {
                case .success:
                    resultMessage = "备份已导出；请妥善保存文件。"
                case .failure(let error):
                    operationError = error.localizedDescription
                }
            }
            .fileImporter(isPresented: $isImporting, allowedContentTypes: [.json]) { result in
                switch result {
                case .success(let url): verifyBackup(at: url)
                case .failure(let error): operationError = error.localizedDescription
                }
            }
            .alert("备份操作未完成", isPresented: Binding(
                get: { operationError != nil },
                set: { if !$0 { operationError = nil } }
            )) {
                Button("好", role: .cancel) {}
            } message: {
                Text(operationError ?? "现有数据没有被覆盖。")
            }
        }
    }

    private func exportBackup() {
        resultMessage = nil
        do {
            let data = try LocalStoreBackupService.export(from: modelContext.container)
            summary = try LocalStoreBackupService.inspect(data: data)
            document = BackupFileDocument(data: data)
            isExporting = true
        } catch {
            operationError = error.localizedDescription
        }
    }

    private func verifyBackup(at url: URL) {
        resultMessage = nil
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            // Bound input before reading; selected files are untrusted, even offline.
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= 64 * 1024 * 1024 else { throw CocoaError(.fileReadTooLarge) }
            let data = try Data(contentsOf: url)
            let directory = URL.applicationSupportDirectory.appending(path: "BackupVerification", directoryHint: .isDirectory)
            _ = try LocalStoreBackupService.stageRestore(data: data, directory: directory)
            summary = try LocalStoreBackupService.inspect(data: data)
            resultMessage = "已在独立文件库恢复并核对，现用数据未改变。"
        } catch {
            operationError = error.localizedDescription
        }
    }
}
