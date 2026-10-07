import FoodDecisionCore
import SwiftData
import SwiftUI

struct GoalSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let onSaved: () -> Void

    @State private var draft = GoalInputDraft()
    @State private var dismissalGuard = FormDismissalGuard(baseline: .goal(GoalInputDraft()))
    @State private var existingID: UUID?
    @State private var effectiveFrom = Date.now
    @State private var hasLoaded = false
    @State private var hasInvalidStoredGoal = false
    @State private var loadError: Error?
    @State private var saveError: Error?
    @State private var isSaving = false
    @FocusState private var focusedField: GoalField?

    private var decimalSeparator: String { Locale.current.decimalSeparator ?? "." }

    private var canSave: Bool {
        hasLoaded && !isSaving && loadError == nil
            && (try? draft.validGoal(id: existingID ?? UUID(), effectiveFrom: effectiveFrom, decimalSeparator: decimalSeparator)) != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                if let loadError {
                    Section {
                        Label("无法读取已保存目标，未载入默认值。", systemImage: "exclamationmark.triangle")
                        Text(loadError.localizedDescription).font(.footnote)
                        Button("重试读取") { loadGoalOnce() }
                            .disabled(!dismissalGuard.canLoadInitialValues(comparedTo: .goal(draft)))
                        if !dismissalGuard.canLoadInitialValues(comparedTo: .goal(draft)) {
                            Text("已有未保存输入，重试不会覆盖它。请取消并确认放弃后，再重新打开目标页。")
                                .font(.footnote)
                        }
                    }
                }
                if hasInvalidStoredGoal {
                    Section {
                        Label("原目标含无效值，已保留并显示；请修改后重新确认。", systemImage: "exclamationmark.triangle")
                    }
                }
                Section {
                    goalField("热量预算 (kcal)", text: $draft.energyKcal, field: .energy)
                } header: {
                    Text("热量预算")
                } footer: {
                    Text("请填写你主动选择的目标，不使用未经确认的示例值。")
                }
                Section("营养预算与目标") {
                    goalField("蛋白质目标 (g)", text: $draft.proteinGrams, field: .protein)
                    goalField("碳水预算 (g)", text: $draft.carbohydrateGrams, field: .carbohydrate)
                    goalField("脂肪预算 (g)", text: $draft.fatGrams, field: .fat)
                }
                Section {
                    goalField("饱和脂肪上限 (g)", text: $draft.saturatedFatLimitGrams, field: .saturatedFat, optional: true)
                    goalField("纤维目标 (g)", text: $draft.fibreGrams, field: .fibre, optional: true)
                } header: {
                    Text("可选上限与目标")
                } footer: {
                    Text("留空表示未设置，不代表 0。系统不会自动生成医疗阈值；如依据医嘱，请使用已确认的数值。")
                }
                Section {
                    Toggle("我已核对并确认预算、目标与上限", isOn: $draft.isConfirmed)
                } footer: {
                    Text("修改任一数值后需要重新确认。小数分隔符为“\(decimalSeparator)”，请勿输入千分位或单位。")
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("每日预算与目标")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消", action: cancelEditing)
                        .disabled(isSaving)
                        .confirmationDialog("放弃未保存的修改？", isPresented: $dismissalGuard.isConfirmingDiscard, titleVisibility: .visible) {
                            Button("放弃修改", role: .destructive) { dismiss() }
                            // Popovers omit role.cancel; keep the safe exit explicitly visible.
                            Button("继续编辑") {}
                        } message: {
                            Text("本次输入尚未保存，放弃后无法恢复。")
                        }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { saveGoal() }.disabled(!canSave)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完成") { focusedField = nil }
                }
            }
            .task { loadGoalOnce() }
            .onChange(of: [draft.energyKcal, draft.proteinGrams, draft.carbohydrateGrams, draft.fatGrams, draft.saturatedFatLimitGrams, draft.fibreGrams]) {
                draft.isConfirmed = false
            }
            .alert("无法保存目标", isPresented: Binding(
                get: { saveError != nil }, set: { if !$0 { saveError = nil } }
            )) {
                Button("好", role: .cancel) {}
            } message: {
                Text(saveError?.localizedDescription ?? "请检查输入并重试。")
            }
        }
        .interactiveDismissDisabled(isSaving || dismissalGuard.hasUnsavedChanges(comparedTo: .goal(draft)))
    }

    private func cancelEditing() {
        focusedField = nil
        if dismissalGuard.requestCancellation(comparedTo: .goal(draft)) { dismiss() }
    }

    private func goalField(_ title: String, text: Binding<String>, field: GoalField, optional: Bool = false) -> some View {
        LabeledContent(title) {
            TextField(optional ? "未设置" : "请输入", text: text)
                .multilineTextAlignment(.trailing)
                .keyboardType(.decimalPad)
                .focused($focusedField, equals: field)
                .submitLabel(.done)
                .onSubmit { focusedField = nil }
                .accessibilityLabel(title)
        }
    }

    private func loadGoalOnce() {
        guard !hasLoaded, dismissalGuard.canLoadInitialValues(comparedTo: .goal(draft)) else { return }
        do {
            let reader = ModelContext(modelContext.container)
            reader.autosaveEnabled = false
            let descriptor = FetchDescriptor<PersistentGoalProfile>(sortBy: [SortDescriptor(\.effectiveFrom, order: .reverse)])
            if let row = try reader.fetch(descriptor).first {
                existingID = row.id
                effectiveFrom = row.effectiveFrom
                // Read raw values so invalid legacy data is visible and can be corrected.
                draft.energyKcal = number(row.energyKcal)
                draft.proteinGrams = number(row.proteinGrams)
                draft.carbohydrateGrams = number(row.carbohydrateGrams)
                draft.fatGrams = number(row.fatGrams)
                draft.saturatedFatLimitGrams = row.saturatedFatLimitGrams.map(number) ?? ""
                draft.fibreGrams = row.fibreGrams.map(number) ?? ""
                hasInvalidStoredGoal = (try? row.domainModel) == nil
            }
            draft.isConfirmed = false
            dismissalGuard.resetBaseline(to: .goal(draft))
            hasLoaded = true
            loadError = nil
        } catch {
            loadError = error
        }
    }

    private func number(_ value: Double) -> String {
        // Round-trippable Double text; no grouping or arbitrary display rounding.
        String(value).replacingOccurrences(of: ".", with: decimalSeparator)
    }

    private func saveGoal() {
        guard !isSaving, hasLoaded, loadError == nil else { return }
        focusedField = nil
        isSaving = true
        do {
            _ = try GoalSaveCommand.save(
                draft: draft, existingID: existingID, effectiveFrom: effectiveFrom,
                container: modelContext.container, decimalSeparator: decimalSeparator
            )
            onSaved()
            dismiss()
        } catch {
            isSaving = false
            saveError = error
        }
    }
}

private enum GoalField: Hashable {
    case energy, protein, carbohydrate, fat, saturatedFat, fibre
}
