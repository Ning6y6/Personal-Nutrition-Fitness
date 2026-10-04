import FoodDecisionCore
import SwiftData
import SwiftUI

struct MealEntryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    private let mealToEdit: PersistentMealLog?

    @Query(sort: \PersistentFoodItem.name)
    private var foodItems: [PersistentFoodItem]

    @State private var title: String
    @State private var eatenAt: Date
    @State private var entryMethod: MealEntryMethod
    @State private var coverageStatus: MealCoverageStatus
    @State private var rows: [MealEntryRow]
    @State private var saveError: Error?
    @State private var seedImportError: Error?
    @State private var isShowingAdvancedOptions = false

    @FocusState private var focusedField: FocusedField?

    init(meal: PersistentMealLog? = nil) {
        mealToEdit = meal
        _title = State(initialValue: meal?.title ?? Self.defaultMealTitle())
        _eatenAt = State(initialValue: meal?.eatenAt ?? .now)
        _entryMethod = State(
            initialValue: meal.flatMap { MealEntryMethod(rawValue: $0.entryMethodRawValue) } ?? .weighed
        )
        _coverageStatus = State(
            initialValue: meal.flatMap { MealCoverageStatus(rawValue: $0.coverageStatusRawValue) }
                ?? .complete
        )
        _rows = State(
            initialValue: meal?.components
                .sorted { $0.sortIndex < $1.sortIndex }
                .map {
                    MealEntryRow(
                        foodItemID: $0.foodItemID,
                        weightGrams: $0.consumedWeightGrams
                    )
                } ?? []
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                mealDetailsSection
                componentsSection
                if !resolvedComponents.isEmpty {
                    nutritionPreviewSection
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(mealToEdit == nil ? "记录一餐" : "编辑餐食")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        saveMeal()
                    }
                    .disabled(!canSave)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完成") {
                        focusedField = nil
                    }
                }
            }
            .task(id: foodItems.count) {
                importSeedsAndPrepareFirstRow()
            }
            .alert(
                "无法保存餐食",
                isPresented: Binding(
                    get: { saveError != nil },
                    set: { if !$0 { saveError = nil } }
                )
            ) {
                Button("好", role: .cancel) {}
            } message: {
                Text(saveError?.localizedDescription ?? "请检查所有食物和重量。")
            }
            .alert(
                "无法载入食物库",
                isPresented: Binding(
                    get: { seedImportError != nil },
                    set: { if !$0 { seedImportError = nil } }
                )
            ) {
                Button("好", role: .cancel) {}
            } message: {
                Text(seedImportError?.localizedDescription ?? "")
            }
        }
    }

    private var mealDetailsSection: some View {
        Section {
            TextField("餐食名称", text: $title)
                .focused($focusedField, equals: .title)
                .submitLabel(.done)
                .onSubmit {
                    focusedField = nil
                }
            DatePicker("时间", selection: $eatenAt)
                .environment(\.locale, Locale(identifier: "zh_Hans_CN"))

            DisclosureGroup(isExpanded: $isShowingAdvancedOptions) {
                Picker("记录方式", selection: $entryMethod) {
                    Text("称重/包装数据").tag(MealEntryMethod.weighed)
                    Text("标准份量估算").tag(MealEntryMethod.standardPortionEstimate)
                }
                .pickerStyle(.menu)

                LabeledContent("证据等级", value: evidenceLabel)

                Picker("记录覆盖", selection: $coverageStatus) {
                    Text("完整").tag(MealCoverageStatus.complete)
                    Text("部分").tag(MealCoverageStatus.partial)
                    Text("临时").tag(MealCoverageStatus.incomplete)
                }
                .pickerStyle(.segmented)
            } label: {
                LabeledContent("更多记录选项", value: recordSummary)
            }
        } header: {
            Text("餐食信息")
        } footer: {
            Text(entryMethodDescription)
        }
    }

    private var componentsSection: some View {
        Section {
            if foodItems.isEmpty {
                ProgressView("正在准备个人食物库…")
            }

            ForEach($rows) { $row in
                VStack(alignment: .leading, spacing: 10) {
                    Picker("食物", selection: $row.foodItemID) {
                        Text("请选择").tag(UUID?.none)
                        if
                            let selectedID = row.foodItemID,
                            !foodItems.contains(where: { $0.id == selectedID })
                        {
                            Text("原食物已不可用，请重新选择")
                                .tag(Optional(selectedID))
                        }
                        ForEach(foodItems) { foodItem in
                            Text(foodItem.name).tag(Optional(foodItem.id))
                        }
                    }
                    .pickerStyle(.menu)

                    HStack {
                        TextField(
                            "重量",
                            value: $row.weightGrams,
                            format: .number.precision(.fractionLength(0...1))
                        )
                        .keyboardType(.decimalPad)
                        .focused($focusedField, equals: .weight(row.id))
                        Text("g")
                            .foregroundStyle(.secondary)
                    }

                    if let foodItem = foodItem(for: row.foodItemID) {
                        Text("营养来源：\(foodSourceName(foodItem.source))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .onDelete(perform: deleteRows)

            Button {
                addRow()
            } label: {
                Label("添加食物", systemImage: "plus.circle.fill")
            }
            .disabled(foodItems.isEmpty)
        } header: {
            Text("食物分项")
        } footer: {
            Text("请选择与实际称重状态一致的条目，例如生肉用生重条目，熟米饭用熟重条目；油和酱汁需要单独添加。")
        }
    }

    private var nutritionPreviewSection: some View {
        Section {
            nutrientRow("热量", value: previewNutrients.energyKcal, unit: "kcal")
            nutrientRow("蛋白质", value: previewNutrients.proteinGrams, unit: "g")
            nutrientRow("碳水化合物", value: previewNutrients.carbohydrateGrams, unit: "g")
            nutrientRow("脂肪", value: previewNutrients.fatGrams, unit: "g")
            nutrientRow("饱和脂肪", value: previewNutrients.saturatedFatGrams, unit: "g")

            if let fibre = previewNutrients.fibreGrams {
                nutrientRow("纤维", value: fibre, unit: "g")
            } else {
                LabeledContent("纤维", value: "—")
            }
        } header: {
            Text("本餐营养预览")
        } footer: {
            if hasIncompleteRows {
                Text("选择食物并输入大于 0 克的重量后才能保存。")
            } else if previewNutrients.fibreGrams == nil {
                Text("至少一个分项缺少可靠纤维数据，因此本餐纤维不显示精确合计。")
            }
        }
    }

    private var resolvedComponents: [MealComponent] {
        rows.compactMap { row in
            guard
                let foodItem = foodItem(for: row.foodItemID),
                let weight = row.weightGrams,
                weight > 0
            else {
                return nil
            }

            return try? MealComponent(
                id: row.id,
                foodItem: foodItem.domainModel,
                consumedWeightGrams: weight
            )
        }
    }

    private var previewNutrients: NutrientValues {
        NutrientValues.sum(resolvedComponents.map(\.nutrients))
    }

    private var hasIncompleteRows: Bool {
        rows.isEmpty || resolvedComponents.count != rows.count
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !hasIncompleteRows
    }

    private var evidenceLabel: String {
        switch entryMethod.evidenceGrade {
        case .a: "A · 高"
        case .b: "B · 中"
        case .c: "C · 已确认照片"
        case .d: "D · 草稿"
        }
    }

    private var entryMethodDescription: String {
        switch entryMethod {
        case .weighed:
            "适用于厨房秤、包装净重或餐厅公布数据，保存为证据 A。"
        case .standardPortionEstimate:
            "适用于个人模板、标准份量或同店同菜经验值，保存为证据 B。"
        }
    }

    private var recordSummary: String {
        let method = entryMethod == .weighed ? "称重" : "估算"
        let coverage: String
        switch coverageStatus {
        case .complete: coverage = "完整"
        case .partial: coverage = "部分"
        case .incomplete: coverage = "临时"
        }
        return "\(method) · \(evidenceLabel.prefix(1)) · \(coverage)"
    }

    private func nutrientRow(_ name: String, value: Double, unit: String) -> some View {
        LabeledContent(
            name,
            value: "\(value.formatted(.number.precision(.fractionLength(0...1)))) \(unit)"
        )
    }

    private func foodItem(for id: UUID?) -> PersistentFoodItem? {
        guard let id else { return nil }
        return foodItems.first { $0.id == id }
    }

    private func foodSourceName(_ source: String) -> String {
        source.components(separatedBy: " · ").first ?? source
    }

    private func importSeedsAndPrepareFirstRow() {
        do {
            try SeedFoodCatalog.importIfNeeded(into: modelContext)
            if rows.isEmpty, !foodItems.isEmpty {
                rows = [MealEntryRow()]
            }
        } catch {
            seedImportError = error
        }
    }

    private func addRow() {
        rows.append(MealEntryRow())
    }

    private func deleteRows(at offsets: IndexSet) {
        rows.remove(atOffsets: offsets)
    }

    private func saveMeal() {
        do {
            let meal = try MealLog(
                id: mealToEdit?.id ?? UUID(),
                eatenAt: eatenAt,
                title: title,
                entryMethod: entryMethod,
                coverageStatus: coverageStatus,
                components: resolvedComponents,
                healthKitSyncVersion: mealToEdit?.healthKitSyncVersion ?? 1
            )
            if let mealToEdit {
                mealToEdit.update(from: meal, in: modelContext)
            } else {
                modelContext.insert(PersistentMealLog(domain: meal))
            }
            try modelContext.save()
            dismiss()
        } catch {
            modelContext.rollback()
            saveError = error
        }
    }

    private static func defaultMealTitle(date: Date = .now) -> String {
        switch Calendar.current.component(.hour, from: date) {
        case 5..<11: "早餐"
        case 11..<15: "午餐"
        case 15..<18: "加餐"
        case 18..<23: "晚餐"
        default: "餐食"
        }
    }
}

private enum FocusedField: Hashable {
    case title
    case weight(UUID)
}

private struct MealEntryRow: Identifiable {
    let id: UUID
    var foodItemID: UUID?
    var weightGrams: Double?

    init(id: UUID = UUID(), foodItemID: UUID? = nil, weightGrams: Double? = nil) {
        self.id = id
        self.foodItemID = foodItemID
        self.weightGrams = weightGrams
    }
}

#Preview {
    MealEntryView()
        .modelContainer(for: VersionedSchemaV1.models, inMemory: true)
}
