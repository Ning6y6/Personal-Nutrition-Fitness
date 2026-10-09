import FoodDecisionCore
import SwiftData
import SwiftUI

struct MealHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Query(sort: \PersistentMealLog.eatenAt, order: .reverse)
    private var meals: [PersistentMealLog]

    @State private var selectedMeal: PersistentMealLog?
    @State private var editingMeal: PersistentMealLog?
    @State private var reuseDraft: MealEntryDraft?
    @State private var expansion: InlineMealExpansionState

    init(initialExpandedMealID: UUID? = nil) {
        _expansion = State(initialValue: InlineMealExpansionState(expandedMealID: initialExpandedMealID))
    }

    // Non-finite raw dates must not make NaN compare unequal on every render
    // and repeatedly collapse the row. This key never replaces stored dates.
    private var dateOrder: [Date?] {
        meals.map { $0.eatenAt.timeIntervalSince1970.isFinite ? $0.eatenAt : nil }
    }

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
                        MealExpandableRow(
                            meal: meal, isExpanded: expansion.expandedMealID == meal.id, showsDate: true,
                            onToggle: { toggleMeal(meal) }, onEdit: { editingMeal = meal },
                            onReuse: { reuseDraft = MealEntryDraft(reusing: $0) },
                            onDetails: { selectedMeal = meal }
                        )
                    }
                    .accessibilityIdentifier("meal.history")
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
            .sheet(item: $editingMeal) { meal in
                MealEntryView(meal: meal)
            }
            .sheet(item: $reuseDraft) { draft in
                MealEntryView(draft: draft)
            }
            .onChange(of: meals.map(\.id)) { expansion.prune(visibleIDs: meals.map(\.id)) }
            .onChange(of: dateOrder) { expansion.collapse() }
        }
    }

    private func toggleMeal(_ meal: PersistentMealLog) {
        withAnimation(reduceMotion ? nil : .default) { expansion.toggle(meal.id) }
    }
}

struct MealSummaryRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let meal: PersistentMealLog
    var showsDate = false
    var isExpanded: Bool? = nil
    var presentation: InlineMealPresentation? = nil

    var body: some View {
        let display = presentation ?? InlineMealPresentation(meal: meal)
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "fork.knife.circle.fill")
                .font(.title2)
                .foregroundStyle(DesignTokens.accent)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                Text(meal.title)
                    .font(.subheadline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Group {
                    if meal.eatenAt.timeIntervalSince1970.isFinite {
                        Text(meal.eatenAt, format: dateFormat)
                    } else {
                        Text("时间不可用")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 3) { summaryLabels(display) }
                } else {
                    HStack(alignment: .top) { summaryLabels(display) }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: isExpanded.map { $0 ? "chevron.up" : "chevron.down" } ?? "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .contentShape(.rect)
    }

    @ViewBuilder
    private func summaryLabels(_ display: InlineMealPresentation) -> some View {
        Text(display.energyText)
            .font(.subheadline)
            .contentTransition(.numericText())
        Text(display.status == .confirmed
            ? "\(meal.evidenceLabel) · \(meal.coverageLabel)"
            : display.status == .draft ? "未确认草稿 · 原始快照" : "需修复 · 原始快照")
            .font(.caption)
            .foregroundStyle(display.status == .confirmed ? AnyShapeStyle(.secondary) : AnyShapeStyle(DesignTokens.warningText))
            .fixedSize(horizontal: false, vertical: true)
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
        let validatedMeal = try? meal.domainModel()
        NavigationStack {
            Form {
                if validatedMeal == nil {
                    Section {
                        Label("这条记录尚未通过正式数据校验，不参与汇总或复用。原始信息保留，请检查分项后编辑保存。", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                }
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
                    if let validatedMeal {
                        FibreSummaryRow(summary: try? FibreIntakeSummary(snapshots: validatedMeal.components.map(\.nutrients)))
                    } else {
                        if let fibre = meal.fibreGrams {
                            nutrientRow("纤维（原始快照）", value: fibre, unit: "g")
                        } else {
                            LabeledContent("纤维（原始快照）", value: "未知")
                        }
                        Text("原记录未通过正式校验，未重新计算纤维小计。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
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
            .accessibilityIdentifier("meal.detail")
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
        case .d: "D · 草稿"
        case .none: "未知（\(estimateEvidenceGradeRawValue)）"
        }
    }

    var coverageLabel: String {
        switch MealCoverageStatus(rawValue: coverageStatusRawValue) {
        case .complete: "完整"
        case .partial: "部分"
        case .incomplete: "临时"
        case .none: "未知（\(coverageStatusRawValue)）"
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
