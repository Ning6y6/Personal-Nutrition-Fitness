import FoodDecisionCore
import SwiftData
import SwiftUI

struct MealHistoryView: View {
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \PersistentMealLog.eatenAt, order: .reverse)
    private var meals: [PersistentMealLog]

    @State private var selectedMeal: PersistentMealLog?

    var body: some View {
        NavigationStack {
            Group {
                if meals.isEmpty {
                    ContentUnavailableView(
                        "暂无历史餐食",
                        systemImage: "fork.knife",
                        description: Text("保存餐食后会在这里按时间显示。")
                    )
                } else {
                    List(meals) { meal in
                        Button {
                            selectedMeal = meal
                        } label: {
                            MealSummaryRow(meal: meal, showsDate: true)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("查看、编辑或删除这条餐食记录")
                    }
                }
            }
            .navigationTitle("历史餐食")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
            .sheet(item: $selectedMeal) { meal in
                MealDetailView(meal: meal)
            }
        }
    }
}

struct MealSummaryRow: View {
    let meal: PersistentMealLog
    var showsDate = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "fork.knife.circle.fill")
                .font(.title2)
                .foregroundStyle(.green)

            VStack(alignment: .leading, spacing: 3) {
                Text(meal.title)
                    .font(.subheadline.weight(.semibold))
                Text(meal.eatenAt, format: dateFormat)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text("\(meal.energyKcal.formatted(.number.precision(.fractionLength(0)))) kcal")
                    .font(.subheadline)
                    .contentTransition(.numericText())
                Text("\(meal.evidenceLabel) · \(meal.coverageLabel)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .contentShape(.rect)
    }

    private var dateFormat: Date.FormatStyle {
        showsDate
            ? .dateTime.month(.abbreviated).day().hour().minute()
            : .dateTime.hour().minute()
    }
}

struct MealDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let meal: PersistentMealLog

    @State private var isShowingEdit = false
    @State private var isConfirmingDelete = false
    @State private var deletionError: Error?
    @State private var templateSeed: MealLog?
    @State private var templatePreparationError: Error?

    var body: some View {
        NavigationStack {
            Form {
                Section("餐食信息") {
                    LabeledContent("名称", value: meal.title)
                    LabeledContent("时间") {
                        Text(meal.eatenAt, format: .dateTime.year().month().day().hour().minute())
                    }
                    LabeledContent("记录方式", value: meal.entryMethodLabel)
                    LabeledContent("证据等级", value: meal.evidenceLabel)
                    LabeledContent("记录覆盖", value: meal.coverageLabel)
                }

                Section("食物分项") {
                    ForEach(meal.components.sorted { $0.sortIndex < $1.sortIndex }) { component in
                        LabeledContent(component.foodName) {
                            Text(
                                "\(component.consumedWeightGrams.formatted(.number.precision(.fractionLength(0...1)))) \(component.unit)"
                            )
                        }
                    }
                }

                Section("营养合计") {
                    nutrientRow("热量", value: meal.energyKcal, unit: "kcal")
                    nutrientRow("蛋白质", value: meal.proteinGrams, unit: "g")
                    nutrientRow("碳水化合物", value: meal.carbohydrateGrams, unit: "g")
                    nutrientRow("脂肪", value: meal.fatGrams, unit: "g")
                    nutrientRow("饱和脂肪", value: meal.saturatedFatGrams, unit: "g")
                    if let fibre = meal.fibreGrams {
                        nutrientRow("纤维", value: fibre, unit: "g")
                    } else {
                        LabeledContent("纤维", value: "—")
                    }
                }

                Section {
                    Button("保存为常用模板", systemImage: "bookmark") {
                        prepareTemplateSeed()
                    }
                    Button("删除餐食", systemImage: "trash", role: .destructive) {
                        isConfirmingDelete = true
                    }
                }
            }
            .navigationTitle("餐食详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("编辑") {
                        isShowingEdit = true
                    }
                }
            }
            .sheet(isPresented: $isShowingEdit) {
                MealEntryView(meal: meal)
            }
            .sheet(item: $templateSeed) { sourceMeal in
                MealTemplateEditorView(sourceMeal: sourceMeal)
            }
            .confirmationDialog(
                "确定删除“\(meal.title)”吗？",
                isPresented: $isConfirmingDelete,
                titleVisibility: .visible
            ) {
                Button("删除餐食", role: .destructive) {
                    deleteMeal()
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("删除后无法撤销，今日汇总会立即重算。")
            }
            .alert(
                "无法删除餐食",
                isPresented: Binding(
                    get: { deletionError != nil },
                    set: { if !$0 { deletionError = nil } }
                )
            ) {
                Button("好", role: .cancel) {}
            } message: {
                Text(deletionError?.localizedDescription ?? "请稍后再试。")
            }
            .alert(
                "无法建立模板",
                isPresented: Binding(
                    get: { templatePreparationError != nil },
                    set: { if !$0 { templatePreparationError = nil } }
                )
            ) {
                Button("好", role: .cancel) {}
            } message: {
                Text(templatePreparationError?.localizedDescription ?? "请稍后再试。")
            }
        }
    }

    private func nutrientRow(_ name: String, value: Double, unit: String) -> some View {
        LabeledContent(
            name,
            value: "\(value.formatted(.number.precision(.fractionLength(0...1)))) \(unit)"
        )
    }

    private func deleteMeal() {
        do {
            modelContext.delete(meal)
            try modelContext.save()
            dismiss()
        } catch {
            modelContext.rollback()
            deletionError = error
        }
    }

    private func prepareTemplateSeed() {
        do {
            templateSeed = try meal.domainModel()
        } catch {
            templatePreparationError = error
        }
    }
}

private extension PersistentMealLog {
    var evidenceLabel: String {
        switch EstimateEvidenceGrade(rawValue: estimateEvidenceGradeRawValue) {
        case .a: "A · 高"
        case .b: "B · 中"
        case .c: "C · 已确认照片"
        case .d, .none: "D · 草稿"
        }
    }

    var coverageLabel: String {
        switch MealCoverageStatus(rawValue: coverageStatusRawValue) {
        case .complete: "完整"
        case .partial: "部分"
        case .incomplete, .none: "临时"
        }
    }

    var entryMethodLabel: String {
        switch MealEntryMethod(rawValue: entryMethodRawValue) {
        case .weighed: "称重/包装数据"
        case .standardPortionEstimate: "标准份量估算"
        case .none: "未知"
        }
    }
}

#Preview {
    MealHistoryView()
        .modelContainer(for: VersionedSchemaV1.models, inMemory: true)
}
