import FoodDecisionCore
import Foundation
import Testing

@testable import FoodDecisionAssistant

/// These tests exercise the value adapter used by both SwiftUI indicators. They deliberately
/// do not instantiate views or claim to validate device layout, animation, or VoiceOver focus.
@MainActor
struct NutritionProgressPresentationTests {
    @Test("Protein and fibre above their minimum are successful, not over-limit warnings", arguments: [NutritionGoalMetric.protein, .fibre])
    func minimumDoesNotBecomeAnUpperLimit(metric: NutritionGoalMetric) {
        let consumed = metric == .protein ? 145.0 : 32.0
        let target = metric == .protein ? 140.0 : 30.0
        let summary = NutritionDisplayPolicy.v1.evaluate(consumed: consumed, target: target, semantics: metric.semantics)
        let display = NutritionProgressPresentation(summary: summary, unit: "g")

        #expect(summary.policyVersion == 1)
        #expect(summary.status == .minimumMet)
        #expect(summary.overage == nil)
        #expect(display.tone == .success)
        #expect(display.symbol == "checkmark.circle.fill")
        #expect(display.message.contains("已达最低目标"))
        #expect(display.message.contains("超出") == false)
        #expect(display.progress == 1)
    }

    @Test("Below a minimum the gap is displayed without a success checkmark")
    func belowMinimumHasAnActualGap() {
        let summary = NutritionDisplayPolicy.v1.evaluate(consumed: 120, target: 140, semantics: .minimum)
        let display = NutritionProgressPresentation(summary: summary, unit: "g")

        #expect(summary.status == .belowMinimum)
        #expect(summary.remaining == 20)
        #expect(display.tone == .neutral)
        #expect(display.symbol == "circle.dotted")
        #expect(display.message.contains("最低目标"))
        #expect(display.message.contains("还差"))
        #expect(display.message.contains("20"))
    }

    @Test("Exactly meeting a minimum is reached, not a zero-gram shortfall")
    func exactMinimumIsReached() {
        let summary = NutritionDisplayPolicy.v1.evaluate(consumed: 140, target: 140, semantics: .minimum)
        let display = NutritionProgressPresentation(summary: summary, unit: "g")

        #expect(summary.status == .minimumMet)
        #expect(display.tone == .success)
        #expect(display.message.contains("已达"))
        #expect(display.message.contains("还差") == false)
        #expect(display.message.contains("超出") == false)
    }

    @Test("Energy budget text, symbol and tone agree at each boundary", arguments: [0.0, 1_200, 2_000, 2_100, 2_200, 2_201])
    func budgetBoundaries(consumed: Double) {
        let summary = NutritionDisplayPolicy.v1.evaluate(consumed: consumed, target: 2_000, semantics: NutritionGoalMetric.energy.semantics)
        let display = NutritionProgressPresentation(summary: summary, unit: "kcal")

        #expect(display.message.contains("预算"))
        #expect(display.message.contains("还差") == false)
        #expect(display.progress == summary.progress)
        if consumed < 2_000 {
            #expect(summary.status == .withinBudget)
            #expect(display.message.contains("剩余"))
            #expect(display.tone == .success)
            #expect(display.symbol == "circle.dotted")
        } else if consumed == 2_000 {
            #expect(summary.status == .atBudget)
            #expect(display.message.contains("已达到"))
            #expect(display.tone == .success)
            #expect(display.symbol == "checkmark.circle.fill")
        } else if consumed <= 2_200 {
            #expect(summary.status == .overBudget)
            #expect(display.message.contains("超出"))
            #expect(display.message.contains("明显") == false)
            #expect(display.tone == .warning)
            #expect(display.symbol == "exclamationmark.circle.fill")
        } else {
            #expect(summary.status == .significantlyOverBudget)
            #expect(display.message.contains("明显超出"))
            #expect(display.tone == .danger)
            #expect(display.symbol == "exclamationmark.triangle.fill")
        }
    }

    @Test("Saturated fat signals approaching, at, and above its upper limit consistently", arguments: [7.99, 8.0, 10.0, 10.001])
    func upperLimitBoundaries(consumed: Double) {
        let summary = NutritionDisplayPolicy.v1.evaluate(consumed: consumed, target: 10, semantics: NutritionGoalMetric.saturatedFat.semantics)
        let display = NutritionProgressPresentation(summary: summary, unit: "g")

        #expect(display.message.contains("上限"))
        if consumed < 8 {
            #expect(summary.status == .belowMaximum)
            #expect(display.message.contains("剩余"))
            #expect(display.tone == .success)
            #expect(display.symbol == "circle.dotted")
        } else if consumed < 10 {
            #expect(summary.status == .approachingMaximum)
            #expect(display.message.contains("接近"))
            #expect(display.tone == .warning)
            #expect(display.symbol == "exclamationmark.circle.fill")
        } else if consumed == 10 {
            #expect(summary.status == .atMaximum)
            #expect(display.message.contains("尚未超出"))
            #expect(display.tone == .warning)
            #expect(display.symbol == "exclamationmark.circle.fill")
        } else {
            #expect(summary.status == .overMaximum)
            #expect(display.message.contains("已超出"))
            #expect(display.tone == .danger)
            #expect(display.symbol == "exclamationmark.triangle.fill")
        }
    }

    @Test("An explicitly configured zero is not presented as an unset target", arguments: [NutritionGoalSemantics.minimum, .budget, .maximum])
    func explicitZeroRemainsAConfiguredTarget(semantics: NutritionGoalSemantics) throws {
        let summary = NutritionDisplayPolicy.v1.evaluate(consumed: 0, target: 0, semantics: semantics)
        let display = NutritionProgressPresentation(summary: summary, unit: "g")
        let progress = try #require(display.progress)

        #expect(progress.isFinite)
        #expect((0...1).contains(progress))
        #expect(display.targetText == "0")
        #expect(display.message.contains("未设置") == false)
        switch semantics {
        case .minimum:
            #expect(summary.status == .minimumMet)
            #expect(display.tone == .success)
            #expect(display.message.contains("最低目标"))
        case .budget:
            #expect(summary.status == .atBudget)
            #expect(display.tone == .success)
            #expect(display.message.contains("预算"))
        case .maximum:
            #expect(summary.status == .atMaximum)
            #expect(display.tone == .warning)
            #expect(display.message.contains("上限"))
        }
    }

    @Test("Positive intake above a zero target respects its minimum or upper-bound meaning", arguments: [NutritionGoalSemantics.minimum, .budget, .maximum])
    func positiveIntakeWithZeroTarget(semantics: NutritionGoalSemantics) throws {
        let summary = NutritionDisplayPolicy.v1.evaluate(consumed: 1, target: 0, semantics: semantics)
        let display = NutritionProgressPresentation(summary: summary, unit: "g")
        let progress = try #require(display.progress)

        #expect(progress.isFinite)
        #expect((0...1).contains(progress))
        if semantics == .minimum {
            #expect(display.tone == .success)
            #expect(display.symbol == "checkmark.circle.fill")
            #expect(display.message.contains("超出") == false)
        } else {
            #expect(display.tone == .warning || display.tone == .danger)
            #expect(display.message.contains("超出"))
            #expect(display.symbol.contains("exclamationmark"))
        }
    }

    @Test("Missing targets remain unset and never become a zero target", arguments: [NutritionGoalSemantics.minimum, .budget, .maximum])
    func unsetTargetHasNeutralPresentation(semantics: NutritionGoalSemantics) {
        let summary = NutritionDisplayPolicy.v1.evaluate(consumed: 123, target: nil, semantics: semantics)
        let display = NutritionProgressPresentation(summary: summary, unit: "g")

        #expect(summary.status == .unset)
        #expect(display.tone == .neutral)
        #expect(display.symbol == "target")
        #expect(display.message.contains("未设置"))
        #expect(display.progress == nil)
        #expect(display.currentText.contains("123"))
        #expect(display.targetText == "—")
    }

    @Test("Missing intake is unavailable, not zero or a success", arguments: [NutritionGoalSemantics.minimum, .budget, .maximum])
    func unavailableIntakeIsNotInvented(semantics: NutritionGoalSemantics) {
        let summary = NutritionDisplayPolicy.v1.evaluate(consumed: nil, target: 10, semantics: semantics)
        let display = NutritionProgressPresentation(summary: summary, unit: "g")

        #expect(summary.status == .unavailable)
        #expect(display.tone == .neutral)
        #expect(display.symbol == "questionmark.circle")
        #expect(display.message.contains("未提供"))
        #expect(display.message.contains("无法计算"))
        #expect(display.progress == nil)
        #expect(display.currentText == "—")
    }

    @Test("Invalid numerical inputs are neutral and never rendered as safe progress", arguments: [(-1.0, 10.0), (Double.nan, 10.0), (Double.infinity, 10.0), (10.0, -1.0), (10.0, Double.nan), (10.0, Double.infinity)], [NutritionGoalSemantics.minimum, .budget, .maximum])
    func invalidInputHasNoHealthyGreenState(values: (Double, Double), semantics: NutritionGoalSemantics) {
        let summary = NutritionDisplayPolicy.v1.evaluate(consumed: values.0, target: values.1, semantics: semantics)
        let display = NutritionProgressPresentation(summary: summary, unit: "g")

        #expect(summary.status == .invalidInput)
        #expect(display.tone == .neutral)
        #expect(display.symbol == "exclamationmark.triangle")
        #expect(display.message.contains("无效"))
        #expect(display.progress == nil)
        #expect(display.valueLabel.lowercased().contains("nan") == false)
        #expect(display.valueLabel.contains("∞") == false)
    }

    @Test("A positive overage smaller than display precision never says exceeded zero", arguments: [NutritionGoalSemantics.budget, .maximum])
    func tinyPositiveOverageDoesNotRoundToZero(semantics: NutritionGoalSemantics) {
        let summary = NutritionDisplayPolicy.v1.evaluate(consumed: 10.001, target: 10, semantics: semantics)
        let display = NutritionProgressPresentation(summary: summary, unit: "g")

        #expect((summary.overage ?? 0) > 0)
        #expect(display.message.contains("超出"))
        #expect(display.message.contains("不足"))
        #expect(display.message.range(of: #"超出(?:预算|上限)?\s+0(?:[.,]0+)?\s+g"#, options: .regularExpression) == nil)
        #expect(display.message.contains("g"))
        #expect(display.tone == .warning || display.tone == .danger)
    }

    @Test("Finite extreme inputs produce a finite saturated indicator, not infinity", arguments: [NutritionGoalSemantics.minimum, .budget, .maximum])
    func finiteOverflowingRatioStaysRenderable(semantics: NutritionGoalSemantics) throws {
        let summary = NutritionDisplayPolicy.v1.evaluate(consumed: .greatestFiniteMagnitude, target: .leastNonzeroMagnitude, semantics: semantics)
        let display = NutritionProgressPresentation(summary: summary, unit: "g")
        let progress = try #require(display.progress)

        #expect(progress.isFinite)
        #expect(progress == 1)
        #expect(display.message.contains("∞") == false)
        #expect(display.message.lowercased().contains("nan") == false)
        #expect(display.tone == (semantics == .minimum ? .success : .danger))
    }

    @Test("The energy ring and generic budget use the same policy-derived presentation", arguments: [0.0, 1_200, 2_000, 2_100, 2_200, 2_201])
    func energyRingSharesBudgetPresentation(consumed: Double) {
        let energy = EnergyProgressPolicy.standard.evaluate(consumedKcal: consumed, targetKcal: 2_000)
        let common = NutritionDisplayPolicy.v1.evaluate(consumed: consumed, target: 2_000, semantics: .budget)
        let ring = NutritionProgressPresentation(summary: energy.nutritionProgress, unit: "kcal")
        let row = NutritionProgressPresentation(summary: common, unit: "kcal")

        #expect(ring == row)
        #expect(energy.nutritionProgress.policyVersion == 1)
    }
}
