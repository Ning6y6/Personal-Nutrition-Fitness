import FoodDecisionCore
import SwiftData
import SwiftUI

struct MealTemplateEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @Query(sort: \PersistentFoodItem.name)
    private var foodItems: [PersistentFoodItem]

    private let templateToEdit: PersistentMealTemplate?

    @State private var name: String
    @State private var rows: [MealFormComponentDraft]
    @State private var dismissalGuard: FormDismissalGuard
    @State private var saveError: Error?
    @State private var catalogImportError: Error?
    @State private var catalogImportFailed = false
    @State private var catalogConflictCount = 0
    @State private var hasAttemptedCatalogImport = false
    @State private var navigationPath = NavigationPath()
    @State private var componentEditMode = EditMode.inactive

    @FocusState private var focusedField: TemplateFocusedField?

    init(
        template: PersistentMealTemplate? = nil,
        sourceMeal: MealLog? = nil
    ) {
        precondition(template == nil || sourceMeal == nil, "A template editor accepts one source only.")
        templateToEdit = template
        let initialName = template?.name ?? sourceMeal?.title ?? ""
        let components: [MealEntryDraftComponent]

        if let template {
            components = template.components
                .sorted { $0.sortIndex < $1.sortIndex }
                .map {
                    MealEntryDraftComponent(
                        id: $0.id,
                        foodItemID: $0.foodItemID,
                        foodName: $0.foodName,
                        weightGrams: $0.defaultWeightGrams
                    )
                }
        } else if let sourceMeal {
            components = sourceMeal.components.map {
                MealEntryDraftComponent(
                    foodItemID: $0.foodItemID,
                    foodName: $0.foodName,
                    weightGrams: $0.consumedWeightGrams
                )
            }
        } else {
            components = []
        }
        let initialRows = components.isEmpty
            ? [MealFormComponentDraft()]
            : components.map { MealFormComponentDraft(component: $0) }
        _name = State(initialValue: initialName)
        _rows = State(initialValue: initialRows)
        _dismissalGuard = State(initialValue: FormDismissalGuard(
            baseline: .template(name: initialName, components: initialRows),
            allowsEmptyNewDraftCancellation: template == nil && sourceMeal == nil
        ))
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            Form {
                Section("模板信息") {
                    templateNameField
                }

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
                        VStack(alignment: .leading, spacing: 10) {
                            NativeFoodMenuRow(
                                selectedName: foodItems.first(where: { $0.id == row.foodItemID })?.name
                                    ?? (row.foodItemID == nil ? "请选择" : "原食物已不可用，请重新选择"),
                                identifier: "template.food.\(row.id.uuidString)"
                            ) {
                                openFoodSelection(for: row.id)
                            }

                            weightField(for: $row)
                        }
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    .onDelete(perform: deleteRows)

                    Button("添加食物", systemImage: "plus.circle.fill") {
                        rows.append(MealFormComponentDraft())
                    }
                    .disabled(foodItems.isEmpty)
                } header: {
                    ComponentEditingHeader(
                        title: "默认分项", isEditing: componentEditMode.isEditing,
                        identifier: "template.components.edit", toggleEditing: toggleComponentEditing
                    )
                } footer: {
                    Text("模板只保存食物和默认克重。每次使用时会按当前食物库重新计算营养。")
                }
            }
            .environment(\.editMode, $componentEditMode)
            .accessibilityIdentifier("template.form")
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(templateToEdit == nil ? "新建常用模板" : "编辑常用模板")
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
                            saveTemplate()
                        }
                        .disabled(!canSave)
                    }
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("完成") {
                            focusedField = nil
                        }
                        .accessibilityIdentifier("template.keyboardDone")
                    }
                }
            }
            .navigationDestination(for: FoodSelectionRoute.self) { route in
                foodSelection(for: route.rowID)
            }
            .navigationDestination(for: FoodDetailRoute.self) { route in
                FoodInformationView(foodID: route.foodID)
            }
            .task {
                if !hasAttemptedCatalogImport { prepareFoodCatalog() }
            }
            .alert(
                "无法保存模板",
                isPresented: Binding(
                    get: { saveError != nil },
                    set: { if !$0 { saveError = nil } }
                )
            ) {
                Button("好", role: .cancel) {}
            } message: {
                Text(saveError?.localizedDescription ?? "请检查所有食物和默认重量。")
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

    @ViewBuilder
    private var templateNameField: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading) {
                Text("模板名称")
                    .accessibilityHidden(true)
                templateNameInput
                    .accessibilityLabel("模板名称")
            }
            .fixedSize(horizontal: false, vertical: true)
        } else {
            HStack {
                Text("模板名称")
                    .accessibilityHidden(true)
                templateNameInput
                    .accessibilityLabel("模板名称")
            }
        }
    }

    private var templateNameInput: some View {
        TextField("请输入", text: $name)
            .multilineTextAlignment(dynamicTypeSize.isAccessibilitySize ? .leading : .trailing)
            .focused($focusedField, equals: .name)
            .submitLabel(.done)
            .onSubmit { focusedField = nil }
            .accessibilityIdentifier("template.name")
    }

    @ViewBuilder
    private func weightField(for row: Binding<MealFormComponentDraft>) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading) {
                Text("默认重量 (g)")
                    .accessibilityHidden(true)
                weightInput(for: row)
                    .accessibilityLabel("默认重量 (g)")
            }
            .fixedSize(horizontal: false, vertical: true)
        } else {
            HStack {
                Text("默认重量")
                    .accessibilityHidden(true)
                weightInput(for: row)
                    .accessibilityLabel("默认重量 (g)")
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
            .accessibilityIdentifier("template.weight.\(row.wrappedValue.id.uuidString)")
    }

    private var draftSnapshot: FormDraftSnapshot {
        .template(name: name, components: rows)
    }

    private func cancelEditing() {
        focusedField = nil
        if dismissalGuard.requestCancellation(comparedTo: draftSnapshot) { dismiss() }
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !rows.isEmpty
            && rows.allSatisfy { row in
                guard let foodItemID = row.foodItemID else { return false }
                return foodItems.contains { $0.id == foodItemID }
                    && (row.weightGrams?.isFinite == true)
                    && (row.weightGrams ?? 0) > 0
            }
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

    private func toggleComponentEditing() {
        focusedField = nil
        withAnimation {
            componentEditMode = componentEditMode.isEditing ? .inactive : .active
        }
    }

    private func openFoodSelection(for rowID: UUID) {
        focusedField = nil
        componentEditMode = .inactive
        navigationPath.append(FoodSelectionRoute(rowID: rowID))
    }

    @ViewBuilder
    private func foodSelection(for rowID: UUID) -> some View {
        if let row = rows.first(where: { $0.id == rowID }) {
            FoodSelectionView(
                selectedFoodID: row.foodItemID,
                onSelect: { foodID in
                    FoodSelectionDraftUpdate.apply(foodID: foodID, to: rowID, rows: &rows)
                },
                onShowInformation: { foodID in
                    navigationPath.append(FoodDetailRoute(foodID: foodID))
                }
            )
        } else {
            ContentUnavailableView("食物分项已移除", systemImage: "fork.knife", description: Text("请返回表单继续编辑。"))
        }
    }

    private func deleteRows(at offsets: IndexSet) {
        focusedField = nil
        rows.remove(atOffsets: offsets)
    }

    private func saveTemplate() {
        do {
            let components = try rows.map { row in
                guard
                    let foodItemID = row.foodItemID,
                    let food = foodItems.first(where: { $0.id == foodItemID }),
                    let weight = row.weightGrams
                else {
                    throw MealTemplateError.emptyComponents
                }
                _ = try food.domainModel
                return try MealTemplateComponent(
                    id: row.id,
                    foodItemID: food.id,
                    foodName: food.name,
                    defaultWeightGrams: weight,
                    unit: food.unit
                )
            }
            let template = try MealTemplate(
                id: templateToEdit?.id ?? UUID(),
                name: name,
                createdAt: templateToEdit?.createdAt ?? .now,
                updatedAt: .now,
                lastUsedAt: templateToEdit?.lastUsedAt,
                useCount: templateToEdit?.useCount ?? 0,
                components: components
            )

            if let templateToEdit {
                try templateToEdit.update(from: template, in: modelContext)
            } else {
                modelContext.insert(PersistentMealTemplate(domain: template))
            }
            try modelContext.save()
            dismiss()
        } catch {
            modelContext.rollback()
            saveError = error
        }
    }
}

private enum TemplateFocusedField: Hashable {
    case name
    case weight(UUID)
}

#Preview {
    MealTemplateEditorView()
        .modelContainer(for: VersionedSchemaV2.models, inMemory: true)
}
