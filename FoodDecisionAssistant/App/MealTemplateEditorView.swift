import FoodDecisionCore
import SwiftData
import SwiftUI

struct MealTemplateEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \PersistentFoodItem.name)
    private var foodItems: [PersistentFoodItem]

    private let templateToEdit: PersistentMealTemplate?

    @State private var name: String
    @State private var rows: [MealEntryDraftComponent]
    @State private var saveError: Error?
    @State private var seedImportError: Error?

    @FocusState private var focusedField: TemplateFocusedField?

    init(
        template: PersistentMealTemplate? = nil,
        sourceMeal: MealLog? = nil
    ) {
        precondition(template == nil || sourceMeal == nil, "A template editor accepts one source only.")
        templateToEdit = template
        _name = State(initialValue: template?.name ?? sourceMeal?.title ?? "")

        if let template {
            _rows = State(
                initialValue: template.components
                    .sorted { $0.sortIndex < $1.sortIndex }
                    .map {
                        MealEntryDraftComponent(
                            id: $0.id,
                            foodItemID: $0.foodItemID,
                            foodName: $0.foodName,
                            weightGrams: $0.defaultWeightGrams
                        )
                    }
            )
        } else if let sourceMeal {
            _rows = State(
                initialValue: sourceMeal.components.map {
                    MealEntryDraftComponent(
                        foodItemID: $0.foodItemID,
                        foodName: $0.foodName,
                        weightGrams: $0.consumedWeightGrams
                    )
                }
            )
        } else {
            _rows = State(initialValue: [])
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("模板信息") {
                    TextField("模板名称", text: $name)
                        .focused($focusedField, equals: .name)
                        .submitLabel(.done)
                        .onSubmit { focusedField = nil }
                }

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
                                    "默认重量",
                                    value: $row.weightGrams,
                                    format: .number.precision(.fractionLength(0...1))
                                )
                                .keyboardType(.decimalPad)
                                .focused($focusedField, equals: .weight(row.id))
                                Text("g")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .onDelete(perform: deleteRows)

                    Button("添加食物", systemImage: "plus.circle.fill") {
                        rows.append(MealEntryDraftComponent())
                    }
                    .disabled(foodItems.isEmpty)
                } header: {
                    Text("默认分项")
                } footer: {
                    Text("模板只保存食物和默认克重。每次使用时会按当前食物库重新计算营养。")
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(templateToEdit == nil ? "新建常用模板" : "编辑常用模板")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
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
                }
            }
            .task(id: foodItems.count) {
                importSeedsAndPrepareFirstRow()
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

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !rows.isEmpty
            && rows.allSatisfy { row in
                guard let foodItemID = row.foodItemID else { return false }
                return foodItems.contains { $0.id == foodItemID }
                    && (row.weightGrams ?? 0) > 0
            }
    }

    private func importSeedsAndPrepareFirstRow() {
        do {
            try SeedFoodCatalog.importIfNeeded(into: modelContext)
            if rows.isEmpty, !foodItems.isEmpty {
                rows = [MealEntryDraftComponent()]
            }
        } catch {
            seedImportError = error
        }
    }

    private func deleteRows(at offsets: IndexSet) {
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
                templateToEdit.update(from: template, in: modelContext)
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
        .modelContainer(for: VersionedSchemaV1.models, inMemory: true)
}
