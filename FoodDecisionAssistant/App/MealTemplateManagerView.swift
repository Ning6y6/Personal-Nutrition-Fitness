import SwiftData
import SwiftUI

struct MealTemplateManagerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \PersistentMealTemplate.updatedAt, order: .reverse)
    private var templates: [PersistentMealTemplate]

    @State private var selectedTemplate: PersistentMealTemplate?
    @State private var templatePendingDeletion: PersistentMealTemplate?
    @State private var isShowingNewTemplate = false
    @State private var deletionError: Error?

    var body: some View {
        NavigationStack {
            Group {
                if templates.isEmpty {
                    ContentUnavailableView(
                        "暂无常用模板",
                        systemImage: "bookmark",
                        description: Text("从餐食详情保存，或点击右上角新建。")
                    )
                } else {
                    List(templates) { template in
                        Button {
                            selectedTemplate = template
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "bookmark.fill")
                                    .foregroundStyle(DesignTokens.accent)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(template.name)
                                        .font(.body.weight(.medium))
                                    Text("\(template.components.count) 项 · 已使用 \(template.useCount) 次")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                                    .accessibilityHidden(true)
                            }
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("template.manage.\(template.id.uuidString)")
                        .swipeActions {
                            Button("删除", systemImage: "trash") {
                                templatePendingDeletion = template
                            }
                            // This action requests confirmation; only the dialog
                            // performs a destructive deletion. Keep the row alive
                            // as the presentation source until then.
                            .tint(.red)
                            .accessibilityIdentifier("template.delete.\(template.id.uuidString)")
                        }
                        // The swipe action disappears after tapping. Keep the
                        // presentation anchored to its stable, matching row.
                        .confirmationDialog(
                            "确定删除“\(template.name)”吗？",
                            isPresented: Binding(
                                get: { templatePendingDeletion?.id == template.id },
                                set: { isPresented in
                                    if !isPresented, templatePendingDeletion?.id == template.id {
                                        templatePendingDeletion = nil
                                    }
                                }
                            ),
                            titleVisibility: .visible
                        ) {
                            Button("删除模板", role: .destructive) {
                                guard templatePendingDeletion?.id == template.id else { return }
                                deletePendingTemplate()
                            }
                            Button("取消", role: .cancel) {
                                guard templatePendingDeletion?.id == template.id else { return }
                                templatePendingDeletion = nil
                            }
                        } message: {
                            Text("只会删除模板，不会删除任何历史餐食。")
                        }
                    }
                    .accessibilityIdentifier("templates.list")
                }
            }
            .navigationTitle("常用模板")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("新建", systemImage: "plus") {
                        isShowingNewTemplate = true
                    }
                }
            }
            .sheet(isPresented: $isShowingNewTemplate) {
                MealTemplateEditorView()
            }
            .sheet(item: $selectedTemplate) { template in
                MealTemplateEditorView(template: template)
            }
            .alert(
                "无法删除模板",
                isPresented: Binding(
                    get: { deletionError != nil },
                    set: { if !$0 { deletionError = nil } }
                )
            ) {
                Button("好", role: .cancel) {}
            } message: {
                Text(deletionError?.localizedDescription ?? "请稍后再试。")
            }
        }
    }

    private func deletePendingTemplate() {
        guard let templatePendingDeletion else { return }

        do {
            modelContext.delete(templatePendingDeletion)
            try modelContext.save()
            self.templatePendingDeletion = nil
        } catch {
            modelContext.rollback()
            deletionError = error
        }
    }
}

#Preview {
    MealTemplateManagerView()
        .modelContainer(for: VersionedSchemaV2.models, inMemory: true)
}
