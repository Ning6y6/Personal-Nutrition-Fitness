import FoodDecisionCore
import SwiftData
import SwiftUI

struct GoalSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.scenePhase) private var scenePhase

    let onSaved: () -> Void

    @State private var draft = GoalInputDraft()
    @State private var effectiveDate: Date
    @State private var minimumSelectableDate: Date
    @State private var source: GoalSource = .selfSelected
    @State private var sourceNote = ""
    @State private var timeZoneIdentifier = TimeZone.current.identifier
    @State private var dismissalGuard: FormDismissalGuard
    @State private var baseline: GoalHistoryBaseline?
    @State private var pendingRequest: GoalVersionSaveRequest?
    @State private var hasLoaded = false
    @State private var isUsingLegacyCurrent = false
    @State private var legacyNeedsConfirmation = false
    @State private var hasFutureVersions = false
    @State private var loadError: Error?
    @State private var saveError: Error?
    @State private var isSaving = false
    @State private var clockRevision: UInt = 0
    @FocusState private var focusedField: GoalField?

    init(onSaved: @escaping () -> Void) {
        self.onSaved = onSaved
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let start = calendar.startOfDay(for: .now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: start) ?? .now
        _effectiveDate = State(initialValue: tomorrow)
        _minimumSelectableDate = State(initialValue: start)
        _dismissalGuard = State(initialValue: FormDismissalGuard(baseline: .goalHistory(
            draft: GoalInputDraft(), effectiveDate: tomorrow, source: .selfSelected,
            sourceNote: "", timeZoneIdentifier: TimeZone.current.identifier
        )))
    }

    private var decimalSeparator: String { Locale.current.decimalSeparator ?? "." }

    private var snapshot: FormDraftSnapshot {
        .goalHistory(draft: draft, effectiveDate: effectiveDate, source: source,
                     sourceNote: sourceNote, timeZoneIdentifier: timeZoneIdentifier)
    }

    private var effectiveDay: GoalDay? {
        try? GoalDay(containing: effectiveDate, timeZoneIdentifier: timeZoneIdentifier)
    }

    private var today: GoalDay? {
        _ = clockRevision
        return try? GoalDay(containing: .now, timeZoneIdentifier: timeZoneIdentifier)
    }

    private var dateIsValid: Bool {
        guard let effectiveDay, let today else { return false }
        return effectiveDay >= today
    }

    private var canSave: Bool {
        guard hasLoaded, !isSaving, loadError == nil, baseline != nil,
              dateIsValid, let effectiveDay,
              let start = try? effectiveDay.start(in: timeZoneIdentifier) else { return false }
        if source == .userProvidedReference && sourceNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return false }
        return (try? draft.validGoal(id: UUID(), effectiveFrom: start, decimalSeparator: decimalSeparator)) != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                if loadError != nil {
                    Section {
                        Label("无法读取已保存目标，未载入默认值。", systemImage: "exclamationmark.triangle")
                        Button("重试读取") { loadGoalOnce() }
                            .disabled(!dismissalGuard.canLoadInitialValues(comparedTo: snapshot))
                        if !dismissalGuard.canLoadInitialValues(comparedTo: snapshot) {
                            Text("已有未保存输入，重试不会覆盖它。请取消并确认放弃后，再重新打开目标页。")
                                .font(.footnote)
                        }
                    }
                }
                if isUsingLegacyCurrent {
                    Section {
                        Label("沿用旧安装当前目标", systemImage: "clock.badge.questionmark")
                        Text("旧目标的来源与历史生效时间未知。此次重新确认会建立第一个已知版本，过去不会按当前目标补写。")
                            .font(.footnote)
                    }
                }
                if legacyNeedsConfirmation {
                    Section {
                        Label("旧目标需重新确认", systemImage: "exclamationmark.triangle")
                        Text("旧数据含无效值或有多个无法判定的当前目标，原记录保留。请明确填写并确认一个新版本；系统不会自行选择或改写旧数据。")
                            .font(.footnote)
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
                    // Keep the lower bound stable while editing. A midnight must not
                    // silently move an expired selection; save validation asks for a new day.
                    DatePicker("生效日期", selection: $effectiveDate, in: minimumSelectableDate..., displayedComponents: .date)
                        .accessibilityIdentifier("goal.effectiveDate")
                    if let effectiveDay {
                        Text("将于 \(GoalVersionDetailView.dayText(effectiveDay)) 生效")
                            .font(.footnote)
                            .accessibilityIdentifier("goal.effectiveSummary")
                    }
                    HStack {
                        Button("今天生效") { selectEffectiveDate(offset: 0) }
                            .accessibilityIdentifier("goal.effectiveToday")
                        Spacer()
                        Button("明天生效") { selectEffectiveDate(offset: 1) }
                            .accessibilityIdentifier("goal.effectiveTomorrow")
                    }
                    .buttonStyle(.borderless)
                    if !dateIsValid {
                        Label("生效日期已早于今天，请重新选择日期并确认。", systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                    }
                } header: {
                    Text("生效安排")
                } footer: {
                    Text("默认明天生效。选择今天会用于今天整日；同日修改以最后确认的版本为准。日期跟随查看时的当地日期。")
                    if hasFutureVersions { Text("已有未来安排仍然保留，到各自生效日期时应用。") }
                }
                Section {
                    Picker("目标来源", selection: $source) {
                        Text("自行选择").tag(GoalSource.selfSelected)
                        Text("参考已有建议").tag(GoalSource.userProvidedReference)
                    }
                    .pickerStyle(.menu)
                    .accessibilityIdentifier("goal.source")
                    TextField(source == .userProvidedReference ? "来源说明（必填）" : "来源说明（可选）", text: $sourceNote, axis: .vertical)
                        .focused($focusedField, equals: .sourceNote)
                        .accessibilityIdentifier("goal.sourceNote")
                } header: {
                    Text("来源")
                } footer: {
                    Text("来源由你提供。系统不会核实或生成医疗建议。")
                }
                Section {
                    Toggle("我已核对并确认预算、目标与上限", isOn: $draft.isConfirmed)
                } footer: {
                    Text("请同时核对生效日期与来源。修改任一内容后需要重新确认。小数分隔符为“\(decimalSeparator)”，请勿输入千分位或单位。")
                }
            }
            .accessibilityIdentifier("goal.form")
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("每日预算与目标")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消", role: .cancel, action: cancelEditing)
                        .disabled(isSaving)
                        .confirmationDialog("放弃未保存的修改？", isPresented: $dismissalGuard.isConfirmingDiscard, titleVisibility: .visible) {
                            Button("放弃修改", role: .destructive) { dismiss() }
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
                        .accessibilityIdentifier("goal.keyboardDone")
                }
            }
            .task { loadGoalOnce() }
            .onChange(of: [draft.energyKcal, draft.proteinGrams, draft.carbohydrateGrams, draft.fatGrams, draft.saturatedFatLimitGrams, draft.fibreGrams]) { invalidateConfirmation() }
            .onChange(of: effectiveDate) { invalidateConfirmation() }
            .onChange(of: source) { invalidateConfirmation() }
            .onChange(of: sourceNote) { invalidateConfirmation() }
            .onChange(of: scenePhase) { if scenePhase == .active { refreshClock() } }
            .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged).receive(on: RunLoop.main)) { _ in refreshClock() }
            .onReceive(NotificationCenter.default.publisher(for: .NSSystemClockDidChange).receive(on: RunLoop.main)) { _ in refreshClock() }
            .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange).receive(on: RunLoop.main)) { _ in refreshClock() }
            .alert("无法保存目标", isPresented: Binding(
                get: { saveError != nil }, set: { if !$0 { saveError = nil } }
            )) {
                Button("好", role: .cancel) {}
            } message: {
                Text(saveMessage)
            }
        }
        .interactiveDismissDisabled(isSaving || dismissalGuard.hasUnsavedChanges(comparedTo: snapshot))
        .presentationDetents([.large])
    }

    private var minimumEffectiveDate: Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .current
        return calendar.startOfDay(for: .now)
    }

    private var saveMessage: String {
        // Input errors describe fields; arbitrary persistence errors can include private paths.
        if let error = saveError as? GoalInputError { return error.localizedDescription }
        if let error = saveError as? GoalVersionSaveCommandError { return error.localizedDescription }
        if let error = saveError as? GoalHistoryError { return error.localizedDescription }
        return "此次目标未保存，输入仍保留。请检查生效日期、来源和确认状态后重试；若已保存目标发生变化，请重新打开并核对。"
    }

    private func selectEffectiveDate(offset: Int) {
        focusedField = nil
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .current
        if let date = calendar.date(byAdding: .day, value: offset, to: minimumEffectiveDate) { effectiveDate = date }
    }

    private func invalidateConfirmation() {
        draft.isConfirmed = false
        pendingRequest = nil
    }

    private func refreshClock() {
        let newZone = TimeZone.current.identifier
        if newZone != timeZoneIdentifier {
            let previousDay = effectiveDay
            timeZoneIdentifier = newZone
            if let previousDay, let date = try? previousDay.start(in: newZone) {
                minimumSelectableDate = min(min(minimumSelectableDate, date), minimumEffectiveDate)
                effectiveDate = date
            }
            invalidateConfirmation()
        }
        clockRevision &+= 1
        if !dateIsValid { invalidateConfirmation() }
    }

    private func cancelEditing() {
        focusedField = nil
        if dismissalGuard.requestCancellation(comparedTo: snapshot) { dismiss() }
    }

    @ViewBuilder
    private func goalField(_ title: String, text: Binding<String>, field: GoalField, optional: Bool = false) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading) {
                Text(title).accessibilityHidden(true)
                goalInput(text: text, field: field, optional: optional).accessibilityLabel(title)
            }
            .fixedSize(horizontal: false, vertical: true)
        } else {
            HStack {
                Text(title).accessibilityHidden(true)
                goalInput(text: text, field: field, optional: optional).accessibilityLabel(title)
            }
        }
    }

    private func goalInput(text: Binding<String>, field: GoalField, optional: Bool) -> some View {
        TextField(optional ? "未设置" : "请输入", text: text)
            .multilineTextAlignment(dynamicTypeSize.isAccessibilitySize ? .leading : .trailing)
            .keyboardType(.decimalPad)
            .focused($focusedField, equals: field)
            .submitLabel(.done)
            .onSubmit { focusedField = nil }
            .accessibilityIdentifier("goal.\(field.rawValue)")
    }

    private func loadGoalOnce() {
        guard !hasLoaded, dismissalGuard.canLoadInitialValues(comparedTo: snapshot), let today else { return }
        do {
            let read = try GoalHistoryReader.read(container: modelContext.container, day: today, allowLegacyCurrent: true)
            if let profile = read.currentProfile { draft = GoalInputDraft(existingGoal: profile, decimalSeparator: decimalSeparator) }
            if let selected = read.selected {
                source = selected.source
                sourceNote = selected.sourceNote ?? ""
            }
            baseline = read.baseline
            isUsingLegacyCurrent = read.selected == nil && read.legacyCurrent != nil
            legacyNeedsConfirmation = read.legacyNeedsConfirmation
            hasFutureVersions = read.versions.contains { $0.effectiveDay > today }
            draft.isConfirmed = false
            dismissalGuard.resetBaseline(to: snapshot)
            hasLoaded = true
            loadError = nil
        } catch {
            loadError = error
        }
    }

    private func saveGoal() {
        guard canSave, let baseline, let effectiveDay else { return }
        focusedField = nil
        isSaving = true
        do {
            let request: GoalVersionSaveRequest
            if let pendingRequest {
                request = pendingRequest
            } else {
                request = GoalVersionSaveRequest(
                    draft: draft, effectiveDay: effectiveDay, source: source, sourceNote: sourceNote,
                    timeZoneIdentifier: timeZoneIdentifier, confirmedAt: .now, operationID: UUID(),
                    expectedBaseline: baseline, decimalSeparator: decimalSeparator
                )
                pendingRequest = request
            }
            _ = try GoalVersionSaveCommand.save(request: request, container: modelContext.container)
            onSaved()
            dismiss()
        } catch {
            isSaving = false
            saveError = error
        }
    }
}

private enum GoalField: String, Hashable {
    case energy, protein, carbohydrate, fat, saturatedFat, fibre, sourceNote
}
