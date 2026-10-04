import FoodDecisionCore
import SwiftData
import SwiftUI

struct MealStartView: View {
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \PersistentMealLog.eatenAt, order: .reverse)
    private var mealLogs: [PersistentMealLog]

    @Query(sort: \PersistentMealTemplate.updatedAt, order: .reverse)
    private var templates: [PersistentMealTemplate]

    @State private var selectedDraft: MealEntryDraft?
    @State private var isShowingBlankEntry = false
    @State private var isShowingTemplateManager = false
    @State private var preparationError: Error?

    private var recentValidation: MealReadValidation {
        MealReadValidation(Array(mealLogs.prefix(30)))
    }

    private var recentMeals: [MealLog] {
        RecentMealSelector.select(from: recentValidation.meals)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        isShowingBlankEntry = true
                    } label: {
                        Label("空白记录", systemImage: "square.and.pencil")
                    }
                } footer: {
                    Text("从零选择食物和重量。")
                }

                Section("最近吃过") {
                    if !recentValidation.invalidRecordIDs.isEmpty || !recentValidation.draftRecordIDs.isEmpty {
                        Label("\(recentValidation.invalidRecordIDs.count)条旧记录需修复、\(recentValidation.draftRecordIDs.count)条草稿无法复用；可在今日页进入全部历史查看和编辑。", systemImage: "exclamationmark.triangle")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    if recentMeals.isEmpty {
                        Text("保存餐食后，这里会显示最多 6 个最近用过的组合。")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(recentMeals) { meal in
                            Button {
                                selectedDraft = MealEntryDraft(reusing: meal)
                            } label: {
                                MealReuseRow(
                                    title: meal.title,
                                    subtitle: componentSummary(meal.components.map(\.foodName)),
                                    trailing: "\(meal.nutrients.energyKcal.formatted(.number.precision(.fractionLength(0)))) kcal",
                                    systemImage: "clock.arrow.circlepath"
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("以证据 B 复用，并在保存前修改本次重量")
                        }
                    }
                }

                Section {
                    if templates.isEmpty {
                        Text("还没有常用菜模板，可从餐食详情保存或在这里新建。")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(templates) { template in
                            Button {
                                prepareDraft(from: template)
                            } label: {
                                MealReuseRow(
                                    title: template.name,
                                    subtitle: componentSummary(
                                        template.components
                                            .sorted { $0.sortIndex < $1.sortIndex }
                                            .map(\.foodName)
                                    ),
                                    trailing: "\(template.components.count) 项",
                                    systemImage: "bookmark.fill"
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("使用模板并在保存前修改本次重量")
                        }
                    }

                    Button("管理常用模板", systemImage: "slider.horizontal.3") {
                        isShowingTemplateManager = true
                    }
                } header: {
                    Text("个人常用菜")
                } footer: {
                    Text("复用会建立新餐食，不会修改原记录或模板。默认按证据 B 保存。")
                }
            }
            .navigationTitle("记录一餐")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $isShowingBlankEntry) {
                MealEntryView(onSaved: { dismiss() })
            }
            .sheet(item: $selectedDraft) { draft in
                MealEntryView(draft: draft, onSaved: { dismiss() })
            }
            .sheet(isPresented: $isShowingTemplateManager) {
                MealTemplateManagerView()
            }
            .alert(
                "无法使用模板",
                isPresented: Binding(
                    get: { preparationError != nil },
                    set: { if !$0 { preparationError = nil } }
                )
            ) {
                Button("好", role: .cancel) {}
            } message: {
                Text(preparationError?.localizedDescription ?? "请编辑模板后重试。")
            }
        }
    }

    private func prepareDraft(from template: PersistentMealTemplate) {
        do {
            selectedDraft = MealEntryDraft(template: try template.domainModel())
        } catch {
            preparationError = error
        }
    }

    private func componentSummary(_ names: [String]) -> String {
        names.prefix(3).joined(separator: "、") + (names.count > 3 ? "等" : "")
    }
}

private struct MealReuseRow: View {
    let title: String
    let subtitle: String
    let trailing: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .frame(width: 30)
                .foregroundStyle(.green)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body.weight(.medium))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Text(trailing)
                .font(.caption)
                .foregroundStyle(.secondary)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .contentShape(.rect)
    }
}

#Preview {
    MealStartView()
        .modelContainer(for: VersionedSchemaV1.models, inMemory: true)
}
