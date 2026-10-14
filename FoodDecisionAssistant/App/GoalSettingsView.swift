import FoodDecisionCore
import SwiftData
import SwiftUI

struct GoalSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appDateDisplay) private var dateDisplay
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
    @State private var saveState = GoalFormSaveState()
    @State private var isSourceExpanded = false
    @State private var isOtherDateExpanded = false
    @State private var savedGoalContext: String?
    @State private var hasLoaded = false
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

    private var datePickerCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = dateDisplay.locale
        calendar.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? dateDisplay.timeZone
        calendar.firstWeekday = dateDisplay.calendar.firstWeekday
        calendar.minimumDaysInFirstWeek = dateDisplay.calendar.minimumDaysInFirstWeek
        return calendar
    }

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
        var validationDraft = draft
        validationDraft.isConfirmed = true
        return (try? validationDraft.validGoal(id: UUID(), effectiveFrom: start, decimalSeparator: decimalSeparator)) != nil
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
                if let savedGoalContext, !legacyNeedsConfirmation {
                    Section {
                        Text(savedGoalContext)
                            .font(.footnote)
                            .accessibilityIdentifier("goal.savedContext")
                    }
                }
                if legacyNeedsConfirmation {
                    Section {
                        Label("旧目标需重新确认", systemImage: "exclamationmark.triangle")
                        Text(GoalContextPresentation.legacyNeedsConfirmationText)
                            .font(.footnote)
                    }
                }
                Section("热量预算") {
                    goalField("热量预算 (kcal)", text: $draft.energyKcal, field: .energy)
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
                    Text("留空表示未设置，不是 0。")
                }
                Section {
                    effectiveDateChoices
                    if let effectiveDay {
                        Text("\(GoalDatePresentation.text(for: effectiveDay, referenceDay: today, display: dateDisplay))生效")
                            .font(.footnote)
                            .accessibilityIdentifier("goal.effectiveSummary")
                    }
                    if isOtherDateExpanded {
                        // A stable lower bound prevents the picker silently advancing
                        // an expired civil date when the form stays open across midnight.
                        DatePicker("选择日期", selection: $effectiveDate, in: minimumSelectableDate..., displayedComponents: .date)
                            .environment(\.locale, dateDisplay.locale)
                            .environment(\.calendar, datePickerCalendar)
                            .environment(\.timeZone, datePickerCalendar.timeZone)
                            .accessibilityIdentifier("goal.effectiveDate")
                    }
                    if !dateIsValid {
                        Label("日期已早于今天，请重新选择。", systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                    }
                } header: {
                    Text("生效日期")
                } footer: {
                    if effectiveDay == today { Text("新目标用于今天整日。") }
                    if hasFutureVersions { Text("已有后续安排仍会按日期生效。") }
                }
                Section {
                    Button {
                        focusedField = nil
                        isSourceExpanded.toggle()
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("目标依据")
                                Text(sourceSummary)
                                    .font(.subheadline)
                                    .foregroundStyle(sourceNeedsNote ? .primary : .secondary)
                                    .accessibilityIdentifier("goal.sourceSummary")
                            }
                            .fixedSize(horizontal: false, vertical: true)
                            Spacer()
                            Image(systemName: isSourceExpanded ? "chevron.up" : "chevron.down")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .accessibilityHidden(true)
                        }
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityValue(isSourceExpanded ? "已展开" : "已收起")
                    .accessibilityIdentifier("goal.sourceDisclosure")
                    if isSourceExpanded {
                        Picker("目标来源", selection: $source) {
                            Text("自行选择").tag(GoalSource.selfSelected)
                            Text("参考已有建议").tag(GoalSource.userProvidedReference)
                        }
                        .pickerStyle(.menu)
                        .accessibilityIdentifier("goal.source")
                        TextField(source == .userProvidedReference ? "来源说明（必填）" : "来源说明（可选）", text: $sourceNote, axis: .vertical)
                            .focused($focusedField, equals: .sourceNote)
                            .accessibilityIdentifier("goal.sourceNote")
                        Text("仅记录依据，不影响目标计算。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
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
            .onChange(of: [draft.energyKcal, draft.proteinGrams, draft.carbohydrateGrams, draft.fatGrams, draft.saturatedFatLimitGrams, draft.fibreGrams]) { invalidatePendingSave() }
            .onChange(of: effectiveDate) { invalidatePendingSave() }
            .onChange(of: source) {
                invalidatePendingSave()
                if sourceNeedsNote { isSourceExpanded = true }
            }
            .onChange(of: dateDisplay) { refreshSavedGoalContext() }
            .onChange(of: sourceNote) { invalidatePendingSave() }
            .onChange(of: decimalSeparator) { invalidatePendingSave() }
            .onChange(of: isSourceExpanded) { if !isSourceExpanded { focusedField = nil } }
            .onReceive(NotificationCenter.default.publisher(for: NSLocale.currentLocaleDidChangeNotification).receive(on: RunLoop.main)) { _ in
                // Re-evaluate the parser. Only an actual separator change invalidates
                // an otherwise unchanged retry; Save also compares it synchronously.
                clockRevision &+= 1
            }
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

    private var sourceNeedsNote: Bool {
        source == .userProvidedReference && sourceNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var sourceSummary: String {
        let title = GoalVersionDetailView.sourceTitle(source)
        return sourceNeedsNote ? "\(title) · 需填写说明" : title
    }

    private var tomorrow: GoalDay? {
        try? today?.addingDays(1, timeZoneIdentifier: timeZoneIdentifier)
    }

    @ViewBuilder
    private var effectiveDateChoices: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading) { effectiveDateButtons }
        } else {
            HStack { effectiveDateButtons }
        }
    }

    @ViewBuilder
    private var effectiveDateButtons: some View {
        effectiveDayButton("今天", offset: 0, selected: !isOtherDateExpanded && effectiveDay == today, identifier: "goal.effectiveToday")
        effectiveDayButton("明天", offset: 1, selected: !isOtherDateExpanded && effectiveDay == tomorrow, identifier: "goal.effectiveTomorrow")
        Button("其他日期") {
            focusedField = nil
            isOtherDateExpanded.toggle()
        }
        .buttonStyle(.bordered)
        .tint(isOtherDateExpanded || (effectiveDay != today && effectiveDay != tomorrow) ? Color.accentColor : Color.secondary)
        .accessibilityValue(isOtherDateExpanded ? "已展开" : "已收起")
        .accessibilityIdentifier("goal.effectiveOther")
    }

    private func effectiveDayButton(_ title: String, offset: Int, selected: Bool, identifier: String) -> some View {
        Button(title) {
            isOtherDateExpanded = false
            selectEffectiveDate(offset: offset)
        }
        .buttonStyle(.bordered)
        .tint(selected ? Color.accentColor : Color.secondary)
        .accessibilityValue(selected ? "已选择" : "未选择")
        .accessibilityIdentifier(identifier)
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
        return "此次目标未保存，输入仍保留。请检查生效日期与来源后重试；若已保存目标发生变化，请重新打开并核对。"
    }

    private func selectEffectiveDate(offset: Int) {
        focusedField = nil
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .current
        if let date = calendar.date(byAdding: .day, value: offset, to: minimumEffectiveDate) { effectiveDate = date }
    }

    private func invalidatePendingSave() {
        saveState.invalidate()
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
            invalidatePendingSave()
        }
        clockRevision &+= 1
        if !dateIsValid { invalidatePendingSave() }
        refreshSavedGoalContext()
    }

    private func refreshSavedGoalContext() {
        // Display changes reformat context without resetting inputs,
        // the persisted baseline or a matching save retry request.
        if hasLoaded, let today,
           let read = try? GoalHistoryReader.read(container: modelContext.container, day: today, allowLegacyCurrent: true) {
            savedGoalContext = GoalContextPresentation.text(for: read, day: today, display: dateDisplay)
            legacyNeedsConfirmation = read.legacyNeedsConfirmation
            hasFutureVersions = read.versions.contains { $0.effectiveDay > today }
        }
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
            savedGoalContext = GoalContextPresentation.text(for: read, day: today, display: dateDisplay)
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
        guard TimeZone.current.identifier == timeZoneIdentifier else {
            refreshClock()
            saveError = GoalVersionSaveCommandError.timeZoneChanged
            return
        }
        guard canSave, let baseline, let effectiveDay else { return }
        focusedField = nil
        isSaving = true
        do {
            // The Save tap supplies confirmation. Matching the current payload here
            // also protects a tap that arrives before SwiftUI's onChange callback.
            let request = saveState.request(
                draft: draft, effectiveDay: effectiveDay, source: source, sourceNote: sourceNote,
                timeZoneIdentifier: timeZoneIdentifier, expectedBaseline: baseline,
                decimalSeparator: decimalSeparator
            )
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
