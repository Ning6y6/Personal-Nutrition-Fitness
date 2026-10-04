import FoodDecisionCore
import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \PersistentGoalProfile.effectiveFrom, order: .reverse)
    private var goalProfiles: [PersistentGoalProfile]

    @Query(sort: \PersistentMealLog.eatenAt, order: .reverse)
    private var mealLogs: [PersistentMealLog]

    @State private var isShowingGoalSettings = false
    @State private var isShowingMealEntry = false
    @State private var seedImportError: Error?

    private var currentGoal: GoalProfile? {
        goalProfiles.first?.domainModel
    }

    private var todayMeals: [PersistentMealLog] {
        mealLogs.filter { Calendar.current.isDateInToday($0.eatenAt) }
    }

    private var todayNutrients: NutrientValues {
        NutrientValues.sum(todayMeals.map(\.nutrientSnapshot))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    TodayStatusCard(
                        goal: currentGoal,
                        nutrients: todayNutrients,
                        mealCount: todayMeals.count
                    )
                    Button {
                        isShowingMealEntry = true
                    } label: {
                        HomeActionCard(
                            title: "记录一餐",
                            subtitle: "称重录入家常菜，或使用标准份量估算",
                            systemImage: "fork.knife",
                            isAvailable: true
                        )
                    }
                    .buttonStyle(.plain)
                    RecentMealsCard(meals: Array(todayMeals.prefix(3)))
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
                ToolbarItem(placement: .topBarTrailing) {
                    Button("目标") {
                        isShowingGoalSettings = true
                    }
                }
            }
            .sheet(isPresented: $isShowingGoalSettings) {
                GoalSettingsView()
            }
            .sheet(isPresented: $isShowingMealEntry) {
                MealEntryView()
            }
            .task {
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
}

private struct RecentMealsCard: View {
    let meals: [PersistentMealLog]

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
                    RecentMealRow(meal: meal)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 18))
    }
}

private struct RecentMealRow: View {
    let meal: PersistentMealLog

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "fork.knife.circle.fill")
                .font(.title2)
                .foregroundStyle(.green)

            VStack(alignment: .leading, spacing: 3) {
                Text(meal.title)
                    .font(.subheadline.weight(.semibold))
                Text(meal.eatenAt, format: .dateTime.hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text("\(meal.energyKcal.formatted(.number.precision(.fractionLength(0)))) kcal")
                    .font(.subheadline)
                Text("\(evidenceLabel) · \(coverageLabel)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var evidenceLabel: String {
        switch EstimateEvidenceGrade(rawValue: meal.estimateEvidenceGradeRawValue) {
        case .a: "A"
        case .b: "B"
        case .c: "C"
        case .d, .none: "D"
        }
    }

    private var coverageLabel: String {
        switch MealCoverageStatus(rawValue: meal.coverageStatusRawValue) {
        case .complete: "完整"
        case .partial: "部分"
        case .incomplete, .none: "临时"
        }
    }
}

private extension PersistentMealLog {
    var nutrientSnapshot: NutrientValues {
        NutrientValues(
            energyKcal: energyKcal,
            fatGrams: fatGrams,
            saturatedFatGrams: saturatedFatGrams,
            carbohydrateGrams: carbohydrateGrams,
            sugarGrams: sugarGrams,
            proteinGrams: proteinGrams,
            saltGrams: saltGrams,
            fibreGrams: fibreGrams
        )
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

private struct GoalSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \PersistentGoalProfile.effectiveFrom, order: .reverse)
    private var goalProfiles: [PersistentGoalProfile]

    @State private var energyKcal = 2_000.0
    @State private var proteinGrams = 140.0
    @State private var carbohydrateGrams = 210.0
    @State private var fatGrams = 60.0
    @State private var saturatedFatLimitGrams = 15.0
    @State private var fibreGrams = 30.0
    @State private var saveError: Error?

    var body: some View {
        NavigationStack {
            Form {
                GoalEnergySection(energyKcal: $energyKcal)
                GoalMacrosSection(
                    proteinGrams: $proteinGrams,
                    carbohydrateGrams: $carbohydrateGrams,
                    fatGrams: $fatGrams
                )
                GoalLimitsSection(
                    saturatedFatLimitGrams: $saturatedFatLimitGrams,
                    fibreGrams: $fibreGrams
                )
            }
            .navigationTitle("每日目标")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        saveGoal()
                    }
                }
            }
            .task(id: goalProfiles.first?.id) {
                loadGoal()
            }
            .alert(
                "无法保存目标",
                isPresented: Binding(
                    get: { saveError != nil },
                    set: { if !$0 { saveError = nil } }
                )
            ) {
                Button("好", role: .cancel) {}
            } message: {
                Text(saveError?.localizedDescription ?? "")
            }
        }
    }

    private func loadGoal() {
        guard let goal = goalProfiles.first?.domainModel else {
            return
        }

        energyKcal = goal.energyKcal
        proteinGrams = goal.proteinGrams
        carbohydrateGrams = goal.carbohydrateGrams
        fatGrams = goal.fatGrams
        saturatedFatLimitGrams = goal.saturatedFatLimitGrams ?? 0
        fibreGrams = goal.fibreGrams ?? 0
    }

    private func saveGoal() {
        let domain = GoalProfile(
            id: goalProfiles.first?.id ?? UUID(),
            effectiveFrom: goalProfiles.first?.effectiveFrom ?? .now,
            energyKcal: energyKcal,
            proteinGrams: proteinGrams,
            carbohydrateGrams: carbohydrateGrams,
            fatGrams: fatGrams,
            saturatedFatLimitGrams: saturatedFatLimitGrams,
            fibreGrams: fibreGrams
        )

        if let persistentGoal = goalProfiles.first {
            persistentGoal.update(from: domain)
        } else {
            modelContext.insert(PersistentGoalProfile(domain: domain))
        }

        do {
            try modelContext.save()
            dismiss()
        } catch {
            saveError = error
        }
    }
}

private struct GoalEnergySection: View {
    @Binding var energyKcal: Double

    var body: some View {
        Section("能量") {
            TextField("每日热量 (kcal)", value: $energyKcal, format: .number)
                .keyboardType(.decimalPad)
        }
    }
}

private struct GoalMacrosSection: View {
    @Binding var proteinGrams: Double
    @Binding var carbohydrateGrams: Double
    @Binding var fatGrams: Double

    var body: some View {
        Section("宏量营养素 (g)") {
            TextField("蛋白质", value: $proteinGrams, format: .number)
                .keyboardType(.decimalPad)
            TextField("碳水化合物", value: $carbohydrateGrams, format: .number)
                .keyboardType(.decimalPad)
            TextField("脂肪", value: $fatGrams, format: .number)
                .keyboardType(.decimalPad)
        }
    }
}

private struct GoalLimitsSection: View {
    @Binding var saturatedFatLimitGrams: Double
    @Binding var fibreGrams: Double

    var body: some View {
        Section("限制与目标 (g)") {
            TextField("饱和脂肪上限", value: $saturatedFatLimitGrams, format: .number)
                .keyboardType(.decimalPad)
            TextField("纤维目标", value: $fibreGrams, format: .number)
                .keyboardType(.decimalPad)
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: VersionedSchemaV1.models, inMemory: true)
}
