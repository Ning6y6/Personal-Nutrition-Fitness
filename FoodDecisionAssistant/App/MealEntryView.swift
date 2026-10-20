import FoodDecisionCore
import SwiftData
import SwiftUI

struct MealEntryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appDateDisplay) private var dateDisplay
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private let mealToEdit: PersistentMealLog?
    private let sourceTemplateID: UUID?
    @State private var editState: MealEditFormState?
    private let onSaved: () -> Void

    @Query(sort: \PersistentFoodItem.name)
    private var foodItems: [PersistentFoodItem]

    @State private var title: String
    @State private var eatenAt: Date
    @State private var entryMethod: MealEntryMethod
    @State private var coverageStatus: MealCoverageStatus
    @State private var rows: [MealFormComponentDraft]
    @State private var dismissalGuard: FormDismissalGuard
    @State private var saveError: Error?
    @State private var catalogImportError: Error?
    @State private var catalogImportFailed = false
    @State private var catalogConflictCount = 0
    @State private var hasAttemptedCatalogImport = false
    @State private var navigationPath = NavigationPath()
    @State private var pendingRemovalID: UUID?
    @State private var isShowingAdvancedOptions = false

    @FocusState private var focusedField: FocusedField?

    init(
        meal: PersistentMealLog? = nil,
        draft: MealEntryDraft? = nil,
        onSaved: @escaping () -> Void = {}
    ) {
        precondition(meal == nil || draft == nil, "An entry cannot edit a meal and load a draft together.")
        mealToEdit = meal
        sourceTemplateID = draft?.sourceTemplateID
        self.onSaved = onSaved
        let initialTitle = meal?.title ?? draft?.title ?? Self.defaultMealTitle()
        let initialDate = meal?.eatenAt ?? draft?.eatenAt ?? .now
        let initialMethod = meal.flatMap { MealEntryMethod(rawValue: $0.entryMethodRawValue) }
            ?? draft?.entryMethod ?? .weighed
        let initialCoverage = meal.flatMap { MealCoverageStatus(rawValue: $0.coverageStatusRawValue) }
            ?? draft?.coverageStatus ?? .complete
        let components = meal?.components
            .sorted { ($0.sortIndex, $0.id.uuidString) < ($1.sortIndex, $1.id.uuidString) }
            .map {
                MealEntryDraftComponent(
                    id: $0.id,
                    foodItemID: $0.foodItemID,
                    foodName: $0.foodName,
                    weightGrams: $0.consumedWeightGrams
                )
            } ?? draft?.components ?? []
        // Prepare the default empty row before capturing the baseline, not in a later task.
        let initialRows = components.isEmpty && meal == nil
            ? [MealFormComponentDraft()]
            : components.map { MealFormComponentDraft(component: $0) }
        _editState = State(initialValue: meal.map {
            MealEditFormState(
                baseline: MealEditSnapshot.capture($0), initialRows: initialRows,
                initialTitle: initialTitle, initialDate: initialDate,
                initialMethod: initialMethod, initialCoverage: initialCoverage
            )
        })
        _title = State(initialValue: initialTitle)
        _eatenAt = State(initialValue: initialDate)
        _entryMethod = State(initialValue: initialMethod)
        _coverageStatus = State(initialValue: initialCoverage)
        _rows = State(initialValue: initialRows)
        _dismissalGuard = State(initialValue: FormDismissalGuard(
            baseline: .meal(title: initialTitle, eatenAt: initialDate, entryMethod: initialMethod,
                            coverageStatus: initialCoverage, components: initialRows),
            allowsEmptyNewDraftCancellation: meal == nil && draft == nil
        ))
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            Form {
                mealDetailsSection
                componentsSection
                if let nutrients = previewNutrients, !resolvedComponents.isEmpty || isPreservingStoredComponents {
                    nutritionPreviewSection(nutrients)
                } else if !resolvedComponents.isEmpty || isPreservingStoredComponents {
                    Section {
                        Label(isPreservingStoredComponents
                              ? "原营养数据有异常；未改分项时仅保存记录信息，原值保持。"
                              : "营养合计超出可计算范围，请检查重量；不能保存。", systemImage: "exclamationmark.triangle")
                    }
                }
            }
            .accessibilityIdentifier("meal.form")
            .onAppear(perform: finishPendingRemoval)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(mealToEdit == nil ? "记录一餐" : "编辑餐食")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if navigationPath.isEmpty {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消", role: .cancel, action: cancelEditing)
                            .confirmationDialog("放弃未保存的修改？", isPresented: $dismissalGuard.isConfirmingDiscard, titleVisibility: .visible) {
                                Button("放弃修改", role: .destructive) { dismiss() }
                                // Popovers omit role.cancel; keep the safe exit explicitly visible.
                                Button("继续编辑") {}
                            } message: {
                                Text("本次输入尚未保存，放弃后无法恢复。")
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
                        .accessibilityIdentifier("meal.keyboardDone")
                    }
                }
            }
            .navigationDestination(for: FoodSelectionRoute.self) { route in
                foodSelection(for: route)
            }
            .navigationDestination(for: FoodDetailRoute.self) { route in
                FoodInformationView(foodID: route.foodID)
            }
            .task {
                if !hasAttemptedCatalogImport { prepareFoodCatalog() }
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
                    get: { catalogImportError != nil },
                    set: { if !$0 { catalogImportError = nil } }
                )
            ) {
                Button("好", role: .cancel) {}
            } message: {
                Text(catalogImportError?.localizedDescription ?? "")
            }
        }
        .interactiveDismissDisabled(dismissalGuard.hasChangesRequiringDiscard(comparedTo: draftSnapshot))
        .presentationDetents([.large])
    }

    private var draftSnapshot: FormDraftSnapshot {
        .meal(title: title, eatenAt: eatenAt, entryMethod: entryMethod,
              coverageStatus: coverageStatus, components: rows)
    }

    private func cancelEditing() {
        focusedField = nil
        if dismissalGuard.requestCancellation(comparedTo: draftSnapshot) { dismiss() }
    }

    private var mealDetailsSection: some View {
        Section {
            mealNameField
            mealDatePicker

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

    @ViewBuilder
    private var mealNameField: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading) {
                Text("餐食名称")
                    .accessibilityHidden(true)
                mealNameInput
                    .accessibilityLabel("餐食名称")
            }
            .fixedSize(horizontal: false, vertical: true)
        } else {
            HStack {
                Text("餐食名称")
                    .accessibilityHidden(true)
                mealNameInput
                    .accessibilityLabel("餐食名称")
            }
        }
    }

    private var mealNameInput: some View {
        TextField("请输入", text: $title)
            .multilineTextAlignment(dynamicTypeSize.isAccessibilitySize ? .leading : .trailing)
            .focused($focusedField, equals: .title)
            .submitLabel(.done)
            .onSubmit { focusedField = nil }
            .accessibilityIdentifier("meal.name")
    }

    @ViewBuilder
    private var mealDatePicker: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading) {
                // Keep a visible heading without duplicating the picker's
                // native accessibility label. Its date/time binding is shared.
                Text("时间")
                    .accessibilityHidden(true)
                DatePicker("时间", selection: $eatenAt)
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .accessibilityIdentifier("meal.time")
            }
            .environment(\.locale, dateDisplay.locale)
            .environment(\.calendar, dateDisplay.calendar)
            .environment(\.timeZone, dateDisplay.timeZone)
        } else {
            DatePicker("时间", selection: $eatenAt)
                .environment(\.locale, dateDisplay.locale)
                .environment(\.calendar, dateDisplay.calendar)
                .environment(\.timeZone, dateDisplay.timeZone)
                .accessibilityIdentifier("meal.time")
        }
    }

    private var componentsSection: some View {
        Section {
            FoodCatalogStatusView(
                isUnavailable: catalogImportFailed,
                conflictCount: catalogConflictCount,
                retry: prepareFoodCatalog
            )
            if foodItems.isEmpty && !catalogImportFailed {
                ProgressView("正在准备个人食物库…")
            }

            ForEach($rows) { $row in
                let rowID = row.id
                VStack(alignment: .leading, spacing: 10) {
                    NativeFoodMenuRow(
                        selectedName: selectedFoodName(for: row),
                        identifier: "meal.food.\(rowID.uuidString)",
                        onRemove: { removeRow(id: rowID) }
                    ) {
                        openFoodSelection(for: rowID)
                    }

                    weightField(for: $row)

                    if editState?.isOriginalFood(row) == true {
                        Text("营养依据：原记录快照")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if let foodItem = foodItem(for: row.foodItemID) {
                        Text("营养来源：\(foodSourceName(foodItem.source))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button("移除", systemImage: "trash", role: .destructive) {
                        removeRow(id: rowID)
                    }
                    .tint(.red)
                    .accessibilityIdentifier("meal.component.remove.\(rowID.uuidString)")
                }
            }

            Button("添加食物", action: addRow)
            .disabled(foodItems.isEmpty)
        } header: {
            Text("食物分项")
        } footer: {
            Text("请选择与实际称重状态一致的条目，例如生肉用生重条目，熟米饭用熟重条目；油和酱汁需要单独添加。")
        }
    }

    @ViewBuilder
    private func weightField(for row: Binding<MealFormComponentDraft>) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading) {
                Text("重量 (g)")
                    .accessibilityHidden(true)
                weightInput(for: row)
                    .accessibilityLabel("重量 (g)")
            }
            .fixedSize(horizontal: false, vertical: true)
        } else {
            HStack {
                Text("重量")
                    .accessibilityHidden(true)
                weightInput(for: row)
                    .accessibilityLabel("重量 (g)")
                Text("g")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
        }
    }

    private func weightInput(for row: Binding<MealFormComponentDraft>) -> some View {
        WeightTextField(
            text: row.weightText,
            isFocused: focusedField == .weight(row.wrappedValue.id)
        )
            .multilineTextAlignment(dynamicTypeSize.isAccessibilitySize ? .leading : .trailing)
            .focused($focusedField, equals: .weight(row.wrappedValue.id))
            .accessibilityIdentifier("meal.weight.\(row.wrappedValue.id.uuidString)")
    }

    private func nutritionPreviewSection(_ previewNutrients: NutrientValues) -> some View {
        Section {
            nutrientRow("热量", value: previewNutrients.energyKcal, unit: "kcal")
                .accessibilityIdentifier("meal.preview.energy")
            nutrientRow("蛋白质", value: previewNutrients.proteinGrams, unit: "g")
            nutrientRow("碳水化合物", value: previewNutrients.carbohydrateGrams, unit: "g")
            nutrientRow("脂肪", value: previewNutrients.fatGrams, unit: "g")
            nutrientRow("饱和脂肪", value: previewNutrients.saturatedFatGrams, unit: "g")

            if isPreservingStoredComponents && hasIncompleteRows {
                LabeledContent("纤维（原始快照）", value: previewNutrients.fibreGrams.map {
                    "\($0.formatted(.number.precision(.fractionLength(0...1)))) g"
                } ?? "未知")
            } else {
                FibreSummaryRow(summary: try? FibreIntakeSummary(snapshots: resolvedComponents.map(\.nutrients)))
            }
        } header: {
            Text("本餐营养预览")
        } footer: {
            if isPreservingStoredComponents && hasIncompleteRows {
                Text("当前显示原记录营养快照；异常分项保持，未重新计算。可保存记录信息，原异常状态不变。")
            } else if hasIncompleteRows {
                Text("当前仅预览已填有效分项；每项选择食物并输入大于0克的重量后才能保存。未填分项尚未计入上述数据。")
            } else if previewNutrients.fibreGrams == nil {
                Text("至少一个分项缺少可靠纤维数据，因此本餐纤维不显示精确合计。")
            }
        }
    }

    private var isPreservingStoredComponents: Bool {
        editState?.componentsAreUnchanged(rows) == true
    }

    private var resolvedComponents: [MealComponent] {
        rows.compactMap { row in
            if let editState { return try? editState.resolve(row, foods: foodItems) }
            guard
                let foodItem = foodItem(for: row.foodItemID),
                let weight = row.weightGrams,
                weight.isFinite, weight > 0
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

    private var previewNutrients: NutrientValues? {
        if let editState, editState.componentsAreUnchanged(rows) {
            return try? editState.baseline.nutrientSnapshot
        }
        return try? NutrientValues.sum(resolvedComponents.map(\.nutrients))
    }

    private var hasIncompleteRows: Bool {
        rows.isEmpty || resolvedComponents.count != rows.count
    }

    private var canSave: Bool {
        if let editState {
            guard let changes = try? editState.changes(
                title: title, eatenAt: eatenAt, entryMethod: entryMethod,
                coverageStatus: coverageStatus, rows: rows, foods: foodItems
            ) else { return false }
            if changes.title != nil && title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return false }
            if changes.eatenAt != nil && !eatenAt.timeIntervalSinceReferenceDate.isFinite { return false }
            return changes.components == nil || (!hasIncompleteRows && previewNutrients != nil)
        }
        return !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !hasIncompleteRows && previewNutrients != nil
    }

    private var evidenceLabel: String {
        let grade: EstimateEvidenceGrade?
        if let editState, entryMethod == editState.initialMethod {
            grade = EstimateEvidenceGrade(rawValue: editState.baseline.evidenceGradeRawValue)
        } else {
            grade = entryMethod.evidenceGrade
        }
        return switch grade {
        case .a: "A · 高"
        case .b: "B · 中"
        case .c: "C · 已确认照片"
        case .d: "D · 草稿"
        case nil: "未知"
        }
    }

    private var entryMethodDescription: String {
        if let editState, entryMethod == editState.initialMethod {
            return "修改名称、时间或克重时，保留原记录的营养依据与证据等级。"
        }
        return switch entryMethod {
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
            value: unit == "kcal"
                ? KcalDisplay.amount(value)
                : "\(value.formatted(.number.precision(.fractionLength(0...1)))) \(unit)"
        )
    }

    private func selectedFoodName(for row: MealFormComponentDraft) -> String {
        if editState?.isOriginalFood(row) == true { return row.foodName ?? "原记录食物" }
        return foodItem(for: row.foodItemID)?.name
            ?? (row.foodItemID == nil ? "请选择" : "原食物已不可用，请重新选择")
    }

    private func foodItem(for id: UUID?) -> PersistentFoodItem? {
        guard let id else { return nil }
        return foodItems.first { $0.id == id }
    }

    private func foodSourceName(_ source: String) -> String {
        source.components(separatedBy: " · ").first ?? source
    }

    private func prepareFoodCatalog() {
        hasAttemptedCatalogImport = true
        do {
            let result = try FoodCatalogImportCommand.importIfNeeded(into: modelContext.container)
            catalogConflictCount = result.conflictingIDs.count
            catalogImportFailed = false
            catalogImportError = nil
        } catch {
            catalogImportFailed = true
            catalogImportError = error
        }
    }

    private func openFoodSelection(for rowID: UUID) {
        guard let row = rows.first(where: { $0.id == rowID }) else { return }
        focusedField = nil
        navigationPath.append(FoodSelectionRoute(rowID: rowID, selectedFoodID: row.foodItemID))
    }

    private func foodSelection(for route: FoodSelectionRoute) -> some View {
        FoodSelectionView(
            selectedFoodID: route.selectedFoodID,
            removalLabel: "从本餐移除",
            onSelect: { foodID in
                FoodSelectionDraftUpdate.apply(foodID: foodID, to: route.rowID, rows: &rows)
            },
            onRemove: { removeFromSelection(id: route.rowID) },
            onShowInformation: { foodID in
                navigationPath.append(FoodDetailRoute(foodID: foodID))
            }
        )
    }

    private func addRow() {
        rows.append(MealFormComponentDraft())
    }

    private func removeRow(id: UUID) {
        focusedField = nil
        rows.removeAll { $0.id == id }
    }

    private func removeFromSelection(id: UUID) {
        focusedField = nil
        pendingRemovalID = id
        if !navigationPath.isEmpty { navigationPath.removeLast() }
    }

    private func finishPendingRemoval() {
        guard navigationPath.isEmpty, let id = pendingRemovalID else { return }
        pendingRemovalID = nil
        removeRow(id: id)
    }

    private func saveMeal() {
        if let editState {
            do {
                let changes = try editState.changes(
                    title: title, eatenAt: eatenAt, entryMethod: entryMethod,
                    coverageStatus: coverageStatus, rows: rows, foods: foodItems
                )
                try MealEditCommand.save(baseline: editState.baseline, changes: changes, in: modelContext.container)
                dismiss()
                onSaved()
            } catch {
                saveError = error
            }
            return
        }
        do {
            // Revalidate every draft row at the write boundary; never save a compacted subset.
            let components = try MealDraftValidation.components(from: rows.map(\.domainDraft), foods: foodItems)
            let meal = try MealLog(
                id: mealToEdit?.id ?? UUID(),
                eatenAt: eatenAt,
                title: title,
                entryMethod: entryMethod,
                coverageStatus: coverageStatus,
                components: components,
                healthKitSyncVersion: mealToEdit?.healthKitSyncVersion ?? 1
            )
            modelContext.insert(PersistentMealLog(domain: meal))
            if let sourceTemplateID {
                let templateID = sourceTemplateID
                let descriptor = FetchDescriptor<PersistentMealTemplate>(
                    predicate: #Predicate { $0.id == templateID }
                )
                try modelContext.fetch(descriptor).first?.markUsed(at: .now)
            }
            try modelContext.save()
            dismiss()
            onSaved()
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

#Preview {
    MealEntryView()
        .modelContainer(for: VersionedSchemaV2.models, inMemory: true)
}
