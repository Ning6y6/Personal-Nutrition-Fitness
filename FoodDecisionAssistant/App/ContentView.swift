import FoodDecisionCore
import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \PersistentMealLog.eatenAt, order: .reverse)
    private var mealLogs: [PersistentMealLog]

    @State private var isShowingGoalSettings = false
    @State private var isShowingMealStart = false
    @State private var isShowingMealHistory = false
    @State private var isShowingBackup = false
    @State private var selectedMeal: PersistentMealLog?
    @State private var seedImportError: Error?
    @State private var currentGoal: GoalProfile?
    @State private var hasGoalReadError = false

    private var todayMeals: [PersistentMealLog] {
        mealLogs.filter { Calendar.current.isDateInToday($0.eatenAt) }
    }

    private var todaySummary: MealReadValidation {
        MealReadValidation(todayMeals)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    let summary = todaySummary
                    TodayStatusCard(
                        goal: currentGoal,
                        nutrients: summary.nutrients,
                        mealCount: summary.meals.count,
                        fibreSummary: summary.fibreSummary,
                        hasGoalReadError: hasGoalReadError
                    )
                    if !summary.invalidRecordIDs.isEmpty || !summary.draftRecordIDs.isEmpty {
                        Label(
                            "今日有\(summary.invalidRecordIDs.count)条旧记录需修复、\(summary.draftRecordIDs.count)条未确认草稿，未计入正式汇总。原记录仍在历史中。",
                            systemImage: "exclamationmark.triangle"
                        )
                        .font(.subheadline)
                        .foregroundStyle(.orange)
                    }
                    Button {
                        isShowingMealStart = true
                    } label: {
                        HomeActionCard(
                            title: "记录一餐",
                            subtitle: "称重录入家常菜，或使用标准份量估算",
                            systemImage: "fork.knife",
                            isAvailable: true
                        )
                    }
                    .buttonStyle(.plain)
                    RecentMealsCard(
                        meals: Array(todayMeals.prefix(3)),
                        hasHistory: !mealLogs.isEmpty,
                        selectMeal: { selectedMeal = $0 },
                        showHistory: { isShowingMealHistory = true }
                    )
                    HomeActionCard(
                        title: "扫描食品标签",
                        subtitle: "先检查硬约束，再计算营养分",
                        systemImage: "viewfinder",
                        isAvailable: false
                    )
                    HomeActionCard(
                        title: "待核对",
                        subtitle: "补齐未识别字段后再给正式结论",
                        systemImage: "checklist",
                        isAvailable: false
                    )
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("今日")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("本地备份", systemImage: "externaldrive") {
                        isShowingBackup = true
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("目标") {
                        isShowingGoalSettings = true
                    }
                }
            }
            .sheet(isPresented: $isShowingGoalSettings) {
                GoalSettingsView(onSaved: refreshGoal)
            }
            .sheet(isPresented: $isShowingBackup) {
                BackupManagementView()
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
            .task {
                refreshGoal()
                do {
                    try SeedFoodCatalog.importIfNeeded(into: modelContext)
                } catch {
                    seedImportError = error
                }
            }
            .alert(
                "无法准备食物库",
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

private struct HomeActionCard: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    let systemImage: String
    let isAvailable: Bool

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.title2)
                .frame(width: 42, height: 42)
                .background(
                    Color.green.opacity(0.15),
                    in: RoundedRectangle(cornerRadius: 12)
                )
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isAvailable {
                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
            } else {
                Text("开发中")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 18))
    }
}

#Preview {
    ContentView()
        .modelContainer(for: VersionedSchemaV1.models, inMemory: true)
}
