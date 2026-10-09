import FoodDecisionCore
import Foundation
import SwiftData
import SwiftUI

/// Preview-only fixtures own isolated memory stores. The title and deliberately changed
/// catalog values are fictitious; no production store or personal record is read here.
@MainActor
struct NativeInlineMealPreviewFixture {
    enum Scenario: String, CaseIterable, Sendable {
        case confirmed, longMixed, draft, invalid
    }

    let container: ModelContainer
    let meal: PersistentMealLog
    let originalMeal: MealLog
    let changedSourceFood: PersistentFoodItem

    static func make(_ scenario: Scenario) throws -> Self {
        let schema = Schema(versionedSchema: VersionedSchemaV1.self)
        let configuration = ModelConfiguration(
            schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none
        )
        let container = try ModelContainer(for: schema, configurations: configuration)
        let context = container.mainContext
        context.autosaveEnabled = false
        try SeedFoodCatalog.importIfNeeded(into: context)
        let foods = try SeedFoodCatalog.loadFoods()
        guard let rice = foods.first(where: { $0.name == "熟长粒白米饭（无盐）" }),
              let pepper = foods.first(where: { $0.name == "青椒（生）" }) else {
            throw NativeInlineMealPreviewError.missingSeed
        }

        let components: [MealComponent]
        if scenario == .longMixed {
            // Eight actual saved snapshots, including known zero and unknown fibre.
            // Long names are clearly marked synthetic rather than advertised catalog entries.
            let selected = [rice, pepper] + Array(foods.filter { $0.id != rice.id && $0.id != pepper.id }.prefix(6))
            components = try selected.enumerated().map { index, food in
                try MealComponent(
                    foodItemID: food.id,
                    foodName: index == 0
                        ? "[预览] 自己准备并分装的一大碗熟长粒白米饭（不加盐，记录保存时的名称）"
                        : food.name,
                    consumedWeightGrams: index == 0 ? 150 : 25 + Double(index) * 10,
                    unit: "g",
                    nutrients: food.nutrientsPer100Units.scaled(by: index == 0 ? 1.5 : (25 + Double(index) * 10) / 100)
                )
            }
        } else {
            components = [try MealComponent(foodItem: rice, consumedWeightGrams: 200)]
        }
        let originalMeal = try MealLog(
            eatenAt: .now,
            title: scenario == .longMixed
                ? "[预览] 和朋友一起备餐之后称重分装的午餐，包含多种食物与尚未公布的纤维数据"
                : "[预览] 熟米饭午餐",
            entryMethod: .weighed,
            coverageStatus: .complete,
            components: components
        )
        let meal = PersistentMealLog(domain: originalMeal)
        if scenario == .draft {
            // D is retained raw history, not an allowed formal MealLog initializer.
            meal.estimateEvidenceGradeRawValue = EstimateEvidenceGrade.d.rawValue
        } else if scenario == .invalid {
            meal.coverageStatusRawValue = "preview_unknown_coverage"
            meal.energyKcal = -10
        }
        context.insert(meal)
        context.insert(PersistentGoalProfile(domain: try GoalProfile(
            effectiveFrom: Date(timeIntervalSince1970: 1_704_067_200),
            energyKcal: 2_000, proteinGrams: 140, carbohydrateGrams: 210, fatGrams: 60,
            saturatedFatLimitGrams: 15, fibreGrams: 30
        )))
        try context.save()

        guard let source = try context.fetch(FetchDescriptor<PersistentFoodItem>()).first(where: { $0.id == rice.id }) else {
            throw NativeInlineMealPreviewError.missingSeed
        }
        // Preparation is saved BEFORE any no-write baseline. Reading history must not
        // recompute the earlier component/meal from this changed current catalog value.
        source.energyKcalPer100Units += 500
        source.name = "[预览] 当前食物库已修改的米饭名称"
        try context.save()
        return Self(container: container, meal: meal, originalMeal: originalMeal, changedSourceFood: source)
    }
}

private enum NativeInlineMealPreviewError: Error {
    case missingSeed
}

/// Uses the production shared row. Only transient expansion state is preview-owned.
struct NativeInlineMealPreviewRow: View {
    let fixture: NativeInlineMealPreviewFixture
    @State private var expansion: InlineMealExpansionState

    init(fixture: NativeInlineMealPreviewFixture) {
        self.fixture = fixture
        _expansion = State(initialValue: InlineMealExpansionState(expandedMealID: fixture.meal.id))
    }

    var body: some View {
        MealExpandableRow(
            meal: fixture.meal,
            isExpanded: expansion.expandedMealID == fixture.meal.id,
            showsDate: true,
            onToggle: { expansion.toggle(fixture.meal.id) },
            onEdit: {},
            onReuse: { _ in },
            onDetails: {}
        )
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DesignTokens.background)
        .tint(DesignTokens.accent)
    }
}

#Preview("C 正式餐食快照 · 浅色") {
    if let fixture = try? NativeInlineMealPreviewFixture.make(.confirmed) {
        NativeInlineMealPreviewRow(fixture: fixture)
            .modelContainer(fixture.container)
            .preferredColorScheme(.light)
    } else {
        ContentUnavailableView("预览不可用", systemImage: "exclamationmark.triangle")
    }
}

#Preview("C 正式餐食快照 · 深色") {
    if let fixture = try? NativeInlineMealPreviewFixture.make(.confirmed) {
        NativeInlineMealPreviewRow(fixture: fixture)
            .modelContainer(fixture.container)
            .preferredColorScheme(.dark)
    } else {
        ContentUnavailableView("预览不可用", systemImage: "exclamationmark.triangle")
    }
}

#Preview("C 长中文、多分项与未知纤维 · 最大辅助字体") {
    if let fixture = try? NativeInlineMealPreviewFixture.make(.longMixed) {
        NativeInlineMealPreviewRow(fixture: fixture)
            .modelContainer(fixture.container)
            .environment(\.dynamicTypeSize, .accessibility5)
    } else {
        ContentUnavailableView("预览不可用", systemImage: "exclamationmark.triangle")
    }
}

#Preview("C 未确认 D 草稿 · 深色最大辅助字体") {
    if let fixture = try? NativeInlineMealPreviewFixture.make(.draft) {
        NativeInlineMealPreviewRow(fixture: fixture)
            .modelContainer(fixture.container)
            .preferredColorScheme(.dark)
            .environment(\.dynamicTypeSize, .accessibility5)
    } else {
        ContentUnavailableView("预览不可用", systemImage: "exclamationmark.triangle")
    }
}

#Preview("C 异常原始快照 · 浅色") {
    if let fixture = try? NativeInlineMealPreviewFixture.make(.invalid) {
        NativeInlineMealPreviewRow(fixture: fixture)
            .modelContainer(fixture.container)
            .preferredColorScheme(.light)
    } else {
        ContentUnavailableView("预览不可用", systemImage: "exclamationmark.triangle")
    }
}

#Preview("C 今日页 · 同一容器内展开") {
    if let fixture = try? NativeInlineMealPreviewFixture.make(.confirmed) {
        NavigationStack {
            TodayView(initialExpandedMealID: fixture.meal.id)
        }
        .modelContainer(fixture.container)
    } else {
        ContentUnavailableView("预览不可用", systemImage: "exclamationmark.triangle")
    }
}

#Preview("C 历史列表 · 深色") {
    if let fixture = try? NativeInlineMealPreviewFixture.make(.longMixed) {
        MealHistoryView(initialExpandedMealID: fixture.meal.id)
            .modelContainer(fixture.container)
            .preferredColorScheme(.dark)
    } else {
        ContentUnavailableView("预览不可用", systemImage: "exclamationmark.triangle")
    }
}
