import FoodDecisionCore
import SwiftData
import SwiftUI

struct TodayView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Query(sort: \PersistentMealLog.eatenAt, order: .reverse)
    private var mealLogs: [PersistentMealLog]

    let isSelected: Bool
    private let mealEntryPlacement: TodayMealEntryButton.Placement

    @State private var isShowingGoalSettings = false
    @State private var isShowingMealStart = false
    @State private var isShowingMealHistory = false
    @State private var selectedMeal: PersistentMealLog?
    @State private var editingMeal: PersistentMealLog?
    @State private var reuseDraft: MealEntryDraft?
    @State private var expansion: InlineMealExpansionState
    @State private var expansionScroll = InlineMealScrollState()
    @State private var currentGoal: GoalProfile?
    @State private var hasGoalReadError = false
    @State private var dateContext = TodayDateContext()

    init(
        isSelected: Bool = true,
        mealEntryPlacement: TodayMealEntryButton.Placement = .bottom,
        initialExpandedMealID: UUID? = nil
    ) {
        self.isSelected = isSelected
        self.mealEntryPlacement = mealEntryPlacement
        _expansion = State(initialValue: InlineMealExpansionState(expandedMealID: initialExpandedMealID))
    }

    private var todayMeals: [PersistentMealLog] {
        guard let window = dateContext.dayWindow else { return [] }
        return MealReadValidation.records(in: window, from: mealLogs)
    }

    private var todaySummary: MealReadValidation {
        MealReadValidation(todayMeals)
    }

    private var visibleMealIDs: [UUID] { todayMeals.prefix(3).map(\.id) }

    private var hasPresentedSheet: Bool {
        isShowingGoalSettings || isShowingMealStart || isShowingMealHistory
            || selectedMeal != nil || editingMeal != nil || reuseDraft != nil
    }

    private var dateSubtitle: String {
        dateContext.dayWindow?.start.formatted(date: .abbreviated, time: .omitted) ?? "日期暂不可用"
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 16) {
                    let summary = todaySummary
                    if dateContext.dayWindow != nil {
                        TodayStatusCard(
                            goal: currentGoal,
                            nutrients: summary.nutrients,
                            mealCount: summary.meals.count,
                            fibreSummary: summary.fibreSummary,
                            availability: summary.availability,
                            hasGoalReadError: hasGoalReadError
                        )
                    } else {
                        Label("今日日期暂不可用", systemImage: "exclamationmark.triangle")
                        Text("暂不显示今日摄入与缺口，历史记录仍保留。")
                            .foregroundStyle(.secondary)
                    }
                    if !summary.invalidRecordIDs.isEmpty || !summary.draftRecordIDs.isEmpty {
                        Label(
                            "今日有\(summary.invalidRecordIDs.count)条旧记录需修复、\(summary.draftRecordIDs.count)条未确认草稿，未计入正式汇总。原记录仍在历史中。",
                            systemImage: "exclamationmark.triangle"
                        )
                        .font(.subheadline)
                        .foregroundStyle(.orange)
                    }
                    if dateContext.dayWindow != nil {
                        RecentMealsCard(
                            meals: Array(todayMeals.prefix(3)),
                            hasHistory: !mealLogs.isEmpty,
                            expandedMealID: expansion.expandedMealID,
                            scrollRequest: expansionScroll.request,
                            toggleMeal: toggleMeal,
                            didLayoutExpansion: { request in
                                expansionScroll.recordLayout(for: request)
                                scrollToExpansionIfReady(in: proxy)
                            },
                            editMeal: { editingMeal = $0 },
                            reuseMeal: { reuseDraft = MealEntryDraft(reusing: $0) },
                            selectMeal: { selectedMeal = $0 },
                            showHistory: { isShowingMealHistory = true }
                        )
                    } else {
                        Button("查看全部历史", systemImage: "clock.arrow.circlepath") {
                            isShowingMealHistory = true
                        }
                    }
                }
                .padding()
            }
            .accessibilityIdentifier("today.content")
            .onScrollPhaseChange { _, phase in
                // A user's own drag takes priority over a pending automatic scroll.
                if phase == .interacting { expansionScroll.invalidate() }
            }
        }
        .background(DesignTokens.background)
        .safeAreaInset(edge: .bottom) {
            if isSelected, mealEntryPlacement == .bottom {
                TodayMealEntryButton(action: showMealStart)
                    .padding()
            }
        }
        .navigationTitle(AppTab.today.title)
        .navigationSubtitle(Text(dateSubtitle))
        .toolbar {
            if isSelected, mealEntryPlacement == .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("记录一餐", systemImage: "plus", action: showMealStart)
                        .labelStyle(.iconOnly)
                        .accessibilityIdentifier("today.recordMeal")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("预算与目标") {
                    isShowingGoalSettings = true
                }
            }
        }
        .sheet(isPresented: $isShowingGoalSettings) {
            GoalSettingsView(onSaved: refreshGoal)
        }
        .sheet(isPresented: $isShowingMealStart) {
            MealStartView()
        }
        .sheet(isPresented: $isShowingMealHistory) {
            MealHistoryView()
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
        .onChange(of: visibleMealIDs) {
            expansion.prune(visibleIDs: visibleMealIDs)
            if let request = expansionScroll.request, !visibleMealIDs.contains(request.mealID) {
                expansionScroll.invalidate()
            }
        }
        .onChange(of: dateContext.dayWindow) {
            expansion.collapse()
            expansionScroll.invalidate()
        }
        .onChange(of: hasPresentedSheet) {
            if hasPresentedSheet { expansionScroll.invalidate() }
        }
        .onChange(of: isSelected, initial: true) {
            guard isSelected else {
                expansionScroll.invalidate()
                return
            }
            refreshGoal()
            refreshDate()
        }
        .onChange(of: scenePhase, initial: true) {
            if scenePhase != .active { expansionScroll.invalidate() }
            if scenePhase == .active, isSelected { refreshDate() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged).receive(on: RunLoop.main)) { _ in
            refreshDate()
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSSystemClockDidChange).receive(on: RunLoop.main)) { _ in
            refreshDate()
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange).receive(on: RunLoop.main)) { _ in
            refreshDate()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSLocale.currentLocaleDidChangeNotification).receive(on: RunLoop.main)) { _ in
            refreshDate()
        }
        .task(id: isSelected && scenePhase == .active ? dateContext.refreshRevision : nil) {
            await monitorDateBoundary()
        }
    }

    private func showMealStart() {
        guard !isShowingMealStart else { return }
        isShowingMealStart = true
    }

    private func toggleMeal(_ meal: PersistentMealLog) {
        let mealID = meal.id
        let target = expansion.expandedMealID == mealID ? nil : mealID
        expansionScroll.begin(expandedMealID: target)
        // The first expanded layout starts scrolling; do not wait for the
        // spring's completion and serialize two visible movements.
        withAnimation(inlineExpansionAnimation) {
            expansion.toggle(mealID)
        }
    }

    private var inlineExpansionAnimation: Animation? {
        reduceMotion ? nil : .snappy(duration: 0.3, extraBounce: 0)
    }

    private func scrollToExpansionIfReady(in proxy: ScrollViewProxy) {
        // A layout pass is necessary to obtain the expanded scroll bounds,
        // not a delay: scroll during expansion, consuming the request once.
        guard let target = expansionScroll.takeReadyTarget(
            expandedMealID: expansion.expandedMealID,
            visibleIDs: visibleMealIDs,
            isActive: isSelected && scenePhase == .active && !hasPresentedSheet
        ) else { return }
        withAnimation(inlineExpansionAnimation) {
            // A long meal or large text cannot fit in one viewport: show its
            // beginning rather than jumping straight past the food to actions.
            proxy.scrollTo(target, anchor: .top)
        }
    }

    private func refreshDate() {
        dateContext.refresh()
    }

    private func monitorDateBoundary() async {
        guard isSelected, scenePhase == .active else { return }
        dateContext.refreshIfNeeded()
        do {
            try await dateContext.waitForNextDay()
        } catch is CancellationError {
            // Backgrounding and tab changes are normal lifecycle events, not errors.
        } catch {
            dateContext.markUnavailable()
        }
    }

    private func refreshGoal() {
        do {
            let reader = ModelContext(modelContext.container)
            reader.autosaveEnabled = false
            let descriptor = FetchDescriptor<PersistentGoalProfile>(sortBy: [SortDescriptor(\.effectiveFrom, order: .reverse)])
            currentGoal = try reader.fetch(descriptor).first?.domainModel
            hasGoalReadError = false
        } catch {
            currentGoal = nil
            hasGoalReadError = true
        }
    }
}

private struct RecentMealsCard: View {
    let meals: [PersistentMealLog]
    let hasHistory: Bool
    let expandedMealID: UUID?
    let scrollRequest: InlineMealScrollState.Request?
    let toggleMeal: (PersistentMealLog) -> Void
    let didLayoutExpansion: (InlineMealScrollState.Request) -> Void
    let editMeal: (PersistentMealLog) -> Void
    let reuseMeal: (MealLog) -> Void
    let selectMeal: (PersistentMealLog) -> Void
    let showHistory: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("今日记录")
                .font(.headline)

            if meals.isEmpty {
                Text("今天还没有记录餐食。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(meals.enumerated()), id: \.element.id) { index, meal in
                    let laidOutRequest = expandedMealID == meal.id && scrollRequest?.mealID == meal.id
                        ? scrollRequest : nil
                    if index > 0 {
                        Divider()
                    }
                    MealExpandableRow(
                        meal: meal, isExpanded: expandedMealID == meal.id,
                        onToggle: { toggleMeal(meal) }, onEdit: { editMeal(meal) },
                        onReuse: reuseMeal, onDetails: { selectMeal(meal) }
                    )
                    .id(meal.id)
                    .onGeometryChange(for: InlineMealScrollState.Request?.self) { geometry in
                        // The Sendable transform captures only a UI request,
                        // not the main-actor-bound persistence model.
                        geometry.size.height > 0 ? laidOutRequest : nil
                    } action: { request in
                        if let request { didLayoutExpansion(request) }
                    }
                }
            }

            if hasHistory {
                Divider()
                Button("查看全部历史", systemImage: "clock.arrow.circlepath") {
                    showHistory()
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 18))
    }
}
