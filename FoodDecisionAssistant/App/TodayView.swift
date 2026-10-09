import FoodDecisionCore
import SwiftData
import SwiftUI

struct TodayView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    @Query(sort: \PersistentMealLog.eatenAt, order: .reverse)
    private var mealLogs: [PersistentMealLog]

    let isSelected: Bool
    private let mealEntryPlacement: TodayMealEntryButton.Placement

    @State private var isShowingGoalSettings = false
    @State private var isShowingMealStart = false
    @State private var isShowingMealHistory = false
    @State private var selectedMeal: PersistentMealLog?
    @State private var currentGoal: GoalProfile?
    @State private var hasGoalReadError = false
    @State private var dateContext = TodayDateContext()

    init(
        isSelected: Bool = true,
        mealEntryPlacement: TodayMealEntryButton.Placement = .bottom
    ) {
        self.isSelected = isSelected
        self.mealEntryPlacement = mealEntryPlacement
    }

    private var todayMeals: [PersistentMealLog] {
        guard let window = dateContext.dayWindow else { return [] }
        return MealReadValidation.records(in: window, from: mealLogs)
    }

    private var todaySummary: MealReadValidation {
        MealReadValidation(todayMeals)
    }

    private var dateSubtitle: String {
        dateContext.dayWindow?.start.formatted(date: .abbreviated, time: .omitted) ?? "日期暂不可用"
    }

    var body: some View {
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
        .onChange(of: isSelected, initial: true) {
            guard isSelected else { return }
            refreshGoal()
            refreshDate()
        }
        .onChange(of: scenePhase, initial: true) {
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

// Lightweight meal expansion belongs to the separately gated UI-2C slice.
private struct RecentMealsCard: View {
    let meals: [PersistentMealLog]
    let hasHistory: Bool
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
                    if index > 0 {
                        Divider()
                    }
                    Button {
                        selectMeal(meal)
                    } label: {
                        MealSummaryRow(meal: meal)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("查看、编辑或删除这条餐食记录")
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
