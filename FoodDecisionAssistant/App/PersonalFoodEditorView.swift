import FoodDecisionCore
import SwiftData
import SwiftUI

struct PersonalFoodEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private let isEditing: Bool
    private let onSaved: (FoodItem) -> Void

    @State private var formState: PersonalFoodFormState
    @State private var loadError: String?
    @State private var saveError: String?
    @State private var isSaving = false
    @State private var isConfirmingDiscard = false
    @FocusState private var focusedField: Field?

    init(
        food: FoodItem? = nil,
        initialName: String = "",
        onSaved: @escaping (FoodItem) -> Void
    ) {
        isEditing = food != nil
        self.onSaved = onSaved
        do {
            if let food {
                _formState = State(initialValue: try PersonalFoodFormState(originalFood: food))
            } else {
                _formState = State(initialValue: PersonalFoodFormState(initialName: initialName))
            }
        } catch {
            // Keep an invalid existing record read-only rather than replacing it
            // with a fresh editable draft or guessing its provenance.
            _formState = State(initialValue: PersonalFoodFormState())
            _loadError = State(initialValue: "这项食物无法作为个人食物卡编辑。原记录未修改，请返回后核对。")
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                if let loadError {
                    Section {
                        Label(loadError, systemImage: "exclamationmark.triangle")
                    }
                } else {
                    informationSection
                    nutritionSection
                    sourceSection
                    if formState.hasUnsavedChanges, let validationMessage {
                        Section {
                            Label(validationMessage, systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("personalFood.validation")
                        }
                    }
                }
            }
            .disabled(isSaving)
            .accessibilityIdentifier("personalFood.form")
            .scrollDismissesKeyboard(.interactively)
            .formKeyboardCompletion(
                isPresented: focusedField != nil,
                identifier: "personalFood.keyboardDone"
            ) { focusedField = nil }
            .navigationTitle(isEditing ? "编辑我的食物" : "新建我的食物")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消", role: .cancel, action: cancelEditing)
                        .disabled(isSaving)
                        .accessibilityIdentifier("personalFood.cancel")
                        .confirmationDialog("放弃未保存的修改？", isPresented: $isConfirmingDiscard, titleVisibility: .visible) {
                            Button("放弃修改", role: .destructive) { dismiss() }
                            Button("继续编辑") {}
                        } message: {
                            Text("本次输入尚未保存，放弃后无法恢复。")
                        }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存", action: saveFood)
                        .disabled(!canSave)
                        .accessibilityIdentifier("personalFood.save")
                }
            }
            .alert("无法保存食物", isPresented: Binding(
                get: { saveError != nil },
                set: { if !$0 { saveError = nil } }
            )) {
                Button("好", role: .cancel) {}
            } message: {
                Text(saveError ?? "此次食物未保存，输入仍保留，请重试。")
            }
        }
        .interactiveDismissDisabled(isSaving || (loadError == nil && formState.hasUnsavedChanges))
        .presentationDetents([.large])
    }

    private var informationSection: some View {
        Section("食物信息") {
            textField("名称", placeholder: "请输入食物名称", text: $formState.draft.name, field: .name)
            Picker("分类", selection: $formState.draft.category) {
                ForEach(FoodCategory.allCases, id: \.self) { category in
                    Text(categoryTitle(category)).tag(category)
                }
            }
            .accessibilityIdentifier("personalFood.category")
        }
    }

    private var nutritionSection: some View {
        Section {
            nutrientField("热量", unit: "kcal", text: $formState.draft.energyKcal, field: .energy)
            nutrientField("脂肪", text: $formState.draft.fatGrams, field: .fat)
            nutrientField("饱和脂肪", text: $formState.draft.saturatedFatGrams, field: .saturatedFat)
            nutrientField("碳水化合物", text: $formState.draft.carbohydrateGrams, field: .carbohydrate)
            nutrientField("糖", text: $formState.draft.sugarGrams, field: .sugar)
            nutrientField("蛋白质", text: $formState.draft.proteinGrams, field: .protein)
            nutrientField("盐", text: $formState.draft.saltGrams, field: .salt)
            nutrientField("膳食纤维（可选）", text: $formState.draft.fibreGrams, field: .fibre, optional: true)
        } header: {
            Text("每 100 g 营养")
        } footer: {
            Text("七项必填；没有含量也请明确输入 0。纤维留空表示未知。当前仅按克记录，请填写每 100 g 标签值，不能直接填写每 100 ml、每份或每勺数值。")
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var sourceSection: some View {
        Section {
            TextField("包装名称或依据（可选）", text: $formState.draft.sourceNote, axis: .vertical)
                .focused($focusedField, equals: .sourceNote)
                .accessibilityLabel("来源说明（可选）")
                .accessibilityIdentifier("personalFood.sourceNote")
        } header: {
            Text("来源说明")
        } footer: {
            Text("用户手动录入。保存食物卡不会记录摄入；记餐时需另外选择食物并填写克重。")
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func textField(_ title: String, placeholder: String, text: Binding<String>, field: Field) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading) {
                Text(title).accessibilityHidden(true)
                TextField(placeholder, text: text)
                    .accessibilityLabel(title)
                    .focused($focusedField, equals: field)
                    .submitLabel(.done)
                    .onSubmit { focusedField = nil }
                    .accessibilityIdentifier("personalFood.\(field.rawValue)")
            }
            .fixedSize(horizontal: false, vertical: true)
        } else {
            HStack {
                Text(title).accessibilityHidden(true)
                TextField(placeholder, text: text)
                    .accessibilityLabel(title)
                    .multilineTextAlignment(.trailing)
                    .focused($focusedField, equals: field)
                    .submitLabel(.done)
                    .onSubmit { focusedField = nil }
                    .accessibilityIdentifier("personalFood.\(field.rawValue)")
            }
        }
    }

    @ViewBuilder
    private func nutrientField(_ title: String, unit: String = "g", text: Binding<String>, field: Field, optional: Bool = false) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading) {
                Text("\(title) (\(unit))").accessibilityHidden(true)
                nutrientInput(text: text, title: title, unit: unit, field: field, optional: optional)
            }
            .fixedSize(horizontal: false, vertical: true)
        } else {
            HStack {
                Text(title).accessibilityHidden(true)
                nutrientInput(text: text, title: title, unit: unit, field: field, optional: optional)
                    .multilineTextAlignment(.trailing)
                Text(unit).foregroundStyle(.secondary).accessibilityHidden(true)
            }
        }
    }

    private func nutrientInput(text: Binding<String>, title: String, unit: String, field: Field, optional: Bool) -> some View {
        // Preserve incomplete and invalid strings; a numeric binding would lose
        // inputs such as "." or "<0.1" before validation and cancellation checks.
        TextField(optional ? "未知" : "请输入", text: text)
            .keyboardType(.decimalPad)
            .focused($focusedField, equals: field)
            .accessibilityLabel("\(title) (\(unit))")
            .accessibilityIdentifier("personalFood.\(field.rawValue)")
    }

    private var validationMessage: String? {
        do {
            _ = try formState.validFood()
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    private var canSave: Bool {
        !isSaving && loadError == nil && validationMessage == nil
    }

    private func cancelEditing() {
        focusedField = nil
        if loadError != nil || !formState.hasUnsavedChanges {
            dismiss()
        } else {
            isConfirmingDiscard = true
        }
    }

    private func saveFood() {
        guard canSave else { return }
        focusedField = nil
        isSaving = true
        defer { isSaving = false }
        do {
            let request = try formState.request()
            let saved = try PersonalFoodSaveCommand.save(request: request, container: modelContext.container)
            onSaved(saved)
            dismiss()
        } catch let error as PersonalFoodSaveCommandError {
            saveError = error.localizedDescription
        } catch let error as PersonalFoodIdentityError {
            saveError = error.localizedDescription
        } catch {
            // Framework errors can contain a private file path. Keep the error
            // visible without exposing it or replacing the user's raw input.
            saveError = "此次食物未保存，输入仍保留。请核对完整数值后重试。"
        }
    }

    private func categoryTitle(_ category: FoodCategory) -> String {
        switch category {
        case .proteinMain: "蛋白质主食材"
        case .stapleGrain: "主食与谷物"
        case .mixedMeal: "混合餐食"
        case .snackDessert: "零食与甜点"
        case .beverage: "饮品"
        case .oil: "油脂"
        case .sauce: "调味品"
        }
    }

    private enum Field: String, Hashable {
        case name, energy, fat, saturatedFat, carbohydrate, sugar, protein, salt, fibre, sourceNote
    }
}
