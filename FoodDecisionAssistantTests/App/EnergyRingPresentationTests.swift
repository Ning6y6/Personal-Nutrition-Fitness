import FoodDecisionCore
import Testing

@testable import FoodDecisionAssistant

@MainActor
struct EnergyRingPresentationTests {
    @Test("v2 uses theme below minimum and amber for every nutrition overage", arguments: NutritionGoalSemantics.allCases)
    func v2NutritionNeverUsesCritical(semantics: NutritionGoalSemantics) {
        let summary = NutritionDisplayPolicy.standard.evaluate(consumed: 32, target: 10, semantics: semantics)
        let display = NutritionProgressPresentation(summary: summary, unit: "g")
        #expect(display.tone == (semantics == .minimum ? .success : .warning))
        #expect(display.tone != .danger)
        #expect(display.message.contains("明显") == false)
    }

    @Test("Lower-bound progress stays themed before the target is met")
    func minimumIsThemedBelowTarget() {
        let summary = NutritionDisplayPolicy.standard.evaluate(consumed: 20, target: 30, semantics: .minimum)
        let display = NutritionProgressPresentation(summary: summary, unit: "g")
        #expect(display.tone == .success)
        #expect(display.symbol == "circle.dotted")
        #expect(display.message.contains("还差"))
    }

    @Test("Budget reached is explicitly not an overage")
    func exactlyAtBudget() {
        let summary = EnergyProgressPolicy.standard.evaluate(consumedKcal: 2_000, targetKcal: 2_000)
        let display = EnergyRingPresentation(summary: summary)
        #expect(display.message.contains("尚未超出"))
        #expect(display.nutrition.tone == .success)
        #expect(summary.baseLap == 1)
        #expect(summary.overflowLap == 0)
    }

    @Test("Two or more laps display the actual multiple without changing nutrition", arguments: [2.0, 3.2, 10.0])
    func multipleIsShown(ratio: Double) {
        let summary = EnergyProgressPolicy.standard.evaluate(consumedKcal: 2_000 * ratio, targetKcal: 2_000)
        let display = EnergyRingPresentation(summary: summary)
        #expect(summary.overflowLap == 1)
        #expect(display.message.contains("倍"))
        #expect(display.message.contains("超出预算"))
        #expect(display.nutrition.tone == .warning)
        #expect(summary.consumedKcal == 2_000 * ratio)
    }

    @Test("Missing, invalid and zero budgets never create a ratio", arguments: [Optional<Double>.none, 0, -1, .infinity])
    func invalidBudgetDoesNotCreateALap(target: Double?) {
        let summary = EnergyProgressPolicy.standard.evaluate(consumedKcal: 1_000, targetKcal: target)
        let display = EnergyRingPresentation(summary: summary)
        #expect(summary.baseLap == nil)
        #expect(summary.overflowLap == nil)
        #expect(display.message.contains("倍") == false)
        #expect(display.nutrition.tone == .neutral)
    }

    @Test("A saturated multiple is not rounded into an unproven numerical lower bound")
    func saturatedMultipleDoesNotInventPrecision() {
        let summary = EnergyProgressPolicy.standard.evaluate(consumedKcal: .greatestFiniteMagnitude, targetKcal: .leastNonzeroMagnitude)
        let display = EnergyRingPresentation(summary: summary)
        #expect(summary.ratioIsSaturated)
        #expect(display.message.contains("倍数超出可显示精度"))
        #expect(display.message.contains("至少") == false)
        #expect(display.message.contains("约为预算") == false)
    }
}
