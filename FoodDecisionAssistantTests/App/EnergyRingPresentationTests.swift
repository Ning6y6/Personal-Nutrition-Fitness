import FoodDecisionCore
import Foundation
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
        #expect(display.symbol == "arrow.up.circle")
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

    @Test("Ordinary remaining states use distinct static symbols, not a loading or warning mark", arguments: NutritionGoalSemantics.allCases)
    func remainingSymbolsAreSemantic(semantics: NutritionGoalSemantics) {
        let summary = NutritionDisplayPolicy.standard.evaluate(consumed: 2, target: 10, semantics: semantics)
        let display = NutritionProgressPresentation(summary: summary, unit: "g")
        let expected = switch semantics {
        case .minimum: "arrow.up.circle"
        case .budget: "chart.pie"
        case .maximum: "arrow.left.and.right.circle"
        }
        #expect(display.symbol == expected)
        #expect(display.symbol.contains("dotted") == false)
        #expect(display.symbol.contains("exclamationmark") == false)
        #expect(display.tone == .success)
        #expect(display.message.contains("还差") || display.message.contains("剩余"))
    }

    @Test("Endpoint geometry follows the same clockwise lap, beginning at twelve o'clock", arguments: [0.0, 0.25, 0.5, 0.75, 1.0])
    func endpointTracksLap(progress: Double) {
        let rect = CGRect(x: 10, y: 20, width: 240, height: 240)
        let bounds = EnergyRingEndpoint.bounds(in: rect, progress: progress, diameter: DesignTokens.ringEndpointDiameter)
        let expectedCenter: CGPoint
        switch progress {
        case 0, 1: expectedCenter = CGPoint(x: 130, y: 20)
        case 0.25: expectedCenter = CGPoint(x: 250, y: 140)
        case 0.5: expectedCenter = CGPoint(x: 130, y: 260)
        default: expectedCenter = CGPoint(x: 10, y: 140)
        }
        #expect(abs(bounds.midX - expectedCenter.x) < 0.0001)
        #expect(abs(bounds.midY - expectedCenter.y) < 0.0001)
        #expect(bounds.width == DesignTokens.ringEndpointDiameter)
        #expect(bounds.height == DesignTokens.ringEndpointDiameter)
    }

    @Test("The overlap cap is wider than the lap stroke and has a visible outline")
    func endpointIsDistinctFromStroke() {
        #expect(DesignTokens.ringEndpointDiameter > DesignTokens.ringLineWidth)
        #expect(DesignTokens.ringEndpointOutlineWidth >= 2)
        #expect(DesignTokens.ringEndpointShadowRadius > 0)
    }

    @Test("A non-square endpoint viewport uses the centered ring radius")
    func endpointSupportsNonSquareBounds() {
        let bounds = EnergyRingEndpoint.bounds(in: CGRect(x: 0, y: 0, width: 300, height: 200), progress: 0.25, diameter: 20)
        #expect(abs(bounds.midX - 250) < 0.0001)
        #expect(abs(bounds.midY - 100) < 0.0001)
    }
}
