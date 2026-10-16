import FoodDecisionCore
import Foundation
import Testing

@testable import FoodDecisionAssistant

@MainActor
struct KcalDisplayTests {
    private let locale = Locale(identifier: "en_GB")

    @Test("kcal uses nearest integer with half values rounded up", arguments: [
        (0.0, "0"), (-0.0, "0"), (1.0, "1"), (1.49, "1"), (1.5, "2"),
        (235.49, "235"), (235.5, "236"), (235.8, "236"), (236.5, "237"),
        (1_999.49, "1,999"), (1_999.5, "2,000"), (2_000.25, "2,000"),
    ])
    func integerAmounts(sample: (Double, String)) {
        #expect(KcalDisplay.value(sample.0, locale: locale) == sample.1)
        #expect(KcalDisplay.amount(sample.0, locale: locale) == "\(sample.1) kcal")
    }

    @Test("Every positive sub-unit quantity remains distinguishable from zero", arguments: [
        Double.leastNonzeroMagnitude, 0.001, 0.1, 0.49, 0.5, 0.99, Double(1).nextDown,
    ])
    func subUnitAmounts(value: Double) {
        #expect(KcalDisplay.value(value, locale: locale) == "不足 1")
        #expect(KcalDisplay.amount(value, locale: locale) == "不足 1 kcal")
    }

    @Test("Invalid energy is unavailable and never invented as zero", arguments: [
        -1.0, -Double.leastNonzeroMagnitude, Double.nan, .infinity, -.infinity,
    ])
    func invalidAmounts(value: Double) {
        #expect(KcalDisplay.value(value, locale: locale) == "不可用")
        #expect(KcalDisplay.amount(value, locale: locale) == "不可用")
    }

    @Test("Half rounding is stable on both neighboring representable values")
    func halfNeighbors() {
        #expect(KcalDisplay.value(236.5.nextDown, locale: locale) == "236")
        #expect(KcalDisplay.value(236.5, locale: locale) == "237")
        #expect(KcalDisplay.value(236.5.nextUp, locale: locale) == "237")
    }

    @Test("Grouping follows the numeric locale without changing precision", arguments: [
        ("en_GB", "2,000"), ("en_US", "2,000"), ("zh_CN", "2,000"), ("de_DE", "2.000"),
    ])
    func numericLocale(sample: (String, String)) {
        #expect(KcalDisplay.value(2_000.25, locale: Locale(identifier: sample.0)) == sample.1)
    }

    @Test("Very large finite kcal does not overflow an integer conversion")
    func largeFiniteAmount() {
        let text = KcalDisplay.value(.greatestFiniteMagnitude, locale: locale)
        #expect(text != "不可用")
        #expect(text != "0")
        #expect(text.lowercased().contains("nan") == false)
        #expect(text.contains("∞") == false)
        #expect(text.contains(".") == false)
    }

    @Test("Rounded current and target do not erase tiny remaining or over-budget states", arguments: [1_999.99, 2_000.01])
    func rawBudgetStatus(consumed: Double) {
        let summary = NutritionDisplayPolicy.v1.evaluate(consumed: consumed, target: 2_000, semantics: .budget)
        let display = NutritionProgressPresentation(summary: summary, unit: "kcal", locale: locale)
        #expect(display.currentText == "2,000")
        #expect(display.targetText == "2,000")
        #expect(display.progress == summary.progress)
        if consumed < 2_000 {
            #expect(summary.status == .withinBudget)
            #expect(display.message == "预算剩余 不足 1 kcal")
            #expect(display.tone == .success)
            #expect(display.symbol == "chart.pie")
        } else {
            #expect(summary.status == .overBudget)
            #expect(display.message == "超出预算 不足 1 kcal")
            #expect(display.tone == .warning)
            #expect(display.symbol == "exclamationmark.circle.fill")
        }
        #expect(display.message.contains("已达到") == false)
    }

    @Test("Missing energy and unset budgets retain their separate meanings")
    func missingValues() {
        let unset = NutritionDisplayPolicy.v1.evaluate(consumed: 235.8, target: nil, semantics: .budget)
        let unsetDisplay = NutritionProgressPresentation(summary: unset, unit: "kcal", locale: locale)
        #expect(unsetDisplay.currentText == "236")
        #expect(unsetDisplay.targetText == "—")
        #expect(unsetDisplay.message == "未设置预算")
        let missing = NutritionDisplayPolicy.v1.evaluate(consumed: nil, target: 2_000.25, semantics: .budget)
        let missingDisplay = NutritionProgressPresentation(summary: missing, unit: "kcal", locale: locale)
        #expect(missingDisplay.currentText == "—")
        #expect(missingDisplay.targetText == "2,000")
        #expect(missingDisplay.progress == nil)
        #expect(missingDisplay.tone == .neutral)
    }

    @Test("Gram quantities keep their existing decimal and tiny-positive display")
    func gramPrecisionUnchanged() {
        let summary = NutritionDisplayPolicy.v1.evaluate(consumed: 14.24, target: 15, semantics: .minimum)
        let display = NutritionProgressPresentation(summary: summary, unit: "g", locale: locale)
        #expect(display.currentText == "14.2")
        #expect(display.message == "距最低目标还差 0.8 g")
        let tiny = NutritionDisplayPolicy.v1.evaluate(consumed: 10.001, target: 10, semantics: .maximum)
        let tinyDisplay = NutritionProgressPresentation(summary: tiny, unit: "g", locale: locale)
        #expect(tinyDisplay.message == "已超出上限 不足 0.1 g")
    }

    @Test("Goal editing round-trips the stored fractional energy rather than its display")
    func goalDraftKeepsPrecision() throws {
        let goal = try GoalProfile(effectiveFrom: .now, energyKcal: 2_000.25, proteinGrams: 140,
                                   carbohydrateGrams: 210, fatGrams: 60)
        #expect(KcalDisplay.amount(goal.energyKcal, locale: locale) == "2,000 kcal")
        var draft = GoalInputDraft(existingGoal: goal)
        #expect(draft.energyKcal == "2000.25")
        draft.isConfirmed = true
        let saved = try draft.validGoal(id: goal.id, effectiveFrom: goal.effectiveFrom)
        #expect(saved == goal)
    }

    @Test("Meal snapshots and totals retain fractions and rendering performs no writes")
    func persistedFractionsAndRawAggregation() throws {
        let fixture = try NativeInlineMealPreviewFixture.make(.confirmed)
        let foods = try SeedFoodCatalog.loadFoods()
        let rice = try #require(foods.first { $0.name == "熟长粒白米饭（无盐）" })
        let rice180 = try MealComponent(foodItem: rice, consumedWeightGrams: 180)
        let rice181 = try MealComponent(foodItem: rice, consumedWeightGrams: 181)
        #expect(abs(rice180.nutrients.energyKcal - 235.8) < 1e-10)
        #expect(abs(rice181.nutrients.energyKcal - 237.11) < 1e-10)
        let component = try MealComponent(foodItem: rice, consumedWeightGrams: 75)
        let meal = try MealLog(eatenAt: .now, title: "[测试] kcal 原始精度", entryMethod: .weighed,
                               coverageStatus: .complete, components: [component, try MealComponent(foodItem: rice, consumedWeightGrams: 75)])
        let stored = PersistentMealLog(domain: meal)
        let context = fixture.container.mainContext
        context.insert(stored)
        try context.save()
        let before = try LocalStoreBackupService.records(from: fixture.container)
        #expect(component.nutrients.energyKcal == 98.25)
        #expect(meal.nutrients.energyKcal == 196.5)
        #expect(KcalDisplay.amount(component.nutrients.energyKcal, locale: locale) == "98 kcal")
        #expect(InlineMealPresentation(meal: stored).energyText == "197 kcal")
        #expect(stored.energyKcal == 196.5)
        #expect(try stored.domainModel() == meal)
        #expect(try LocalStoreBackupService.records(from: fixture.container) == before)
        #expect(context.hasChanges == false)
    }
}
