import Foundation
import Testing
@testable import FoodDecisionCore

struct NutritionDisplayPolicyTests {
    @Test("Nutrients have centrally defined minimum, budget, and maximum semantics", arguments: NutritionGoalMetric.allCases)
    func nutrientSemantics(metric: NutritionGoalMetric) {
        switch metric {
        case .protein, .fibre: #expect(metric.semantics == .minimum)
        case .energy, .carbohydrate, .fat: #expect(metric.semantics == .budget)
        case .saturatedFat: #expect(metric.semantics == .maximum)
        }
    }

    @Test("Protein or fibre above a minimum is achieved, not an overage", arguments: [140.0, 145, 200])
    func minimumMet(consumed: Double) {
        let result = NutritionDisplayPolicy.v1.evaluate(consumed: consumed, target: 140, semantics: .minimum)
        #expect(result.status == .minimumMet)
        #expect(result.remaining == 0)
        #expect(result.overage == nil)
        #expect(result.progress == 1)
        #expect(result.policyVersion == 1)
    }

    @Test("Upper warnings start at eighty percent, and only a true excess is over the maximum", arguments: [(79.9, NutritionProgressStatus.belowMaximum), (80.0, .approachingMaximum), (100.0, .atMaximum), (100.1, .overMaximum)])
    func maximumBoundaries(consumed: Double, expected: NutritionProgressStatus) {
        let result = NutritionDisplayPolicy.v1.evaluate(consumed: consumed, target: 100, semantics: .maximum)
        #expect(result.status == expected)
        #expect(result.progress == min(consumed / 100, 1))
        #expect(result.remaining == max(100 - consumed, 0))
        #expect(result.overage == max(consumed - 100, 0))
    }

    @Test("Budget threshold equality is not a significant overage", arguments: [(79.9, NutritionProgressStatus.withinBudget), (80.0, .withinBudget), (100.0, .atBudget), (110.0, .overBudget), (110.1, .significantlyOverBudget)])
    func budgetBoundaries(consumed: Double, expected: NutritionProgressStatus) {
        let result = NutritionDisplayPolicy.v1.evaluate(consumed: consumed, target: 100, semantics: .budget)
        #expect(result.status == expected)
    }

    @Test("Unset and explicit zero are distinct for every goal type", arguments: NutritionGoalSemantics.allCases)
    func zeroVersusUnset(semantics: NutritionGoalSemantics) {
        let unset = NutritionDisplayPolicy.v1.evaluate(consumed: 0, target: nil, semantics: semantics)
        #expect(unset.status == .unset)
        #expect(unset.progress == nil)
        #expect(unset.remaining == nil)
        let zero = NutritionDisplayPolicy.v1.evaluate(consumed: 0, target: 0, semantics: semantics)
        switch semantics {
        case .minimum: #expect(zero.status == .minimumMet)
        case .budget: #expect(zero.status == .atBudget)
        case .maximum: #expect(zero.status == .atMaximum)
        }
        #expect(zero.target == 0)
        #expect(zero.progress == 1)
        let positive = NutritionDisplayPolicy.v1.evaluate(consumed: 1, target: 0, semantics: semantics)
        switch semantics {
        case .minimum: #expect(positive.status == .minimumMet)
        case .budget: #expect(positive.status == .significantlyOverBudget)
        case .maximum: #expect(positive.status == .overMaximum)
        }
    }

    @Test("Invalid consumed data is not clamped into a valid green result", arguments: [-1.0, Double.nan, .infinity, -.infinity])
    func invalidConsumed(value: Double) {
        let result = NutritionDisplayPolicy.v1.evaluate(consumed: value, target: 100, semantics: .budget)
        #expect(result.status == .invalidInput)
        #expect(result.consumed == nil)
        #expect(result.progress == nil)
        #expect(result.remaining == nil)
        #expect(result.overage == nil)
    }

    @Test("Invalid target data is not confused with an unset target", arguments: [-1.0, Double.nan, .infinity, -.infinity])
    func invalidTarget(value: Double) {
        let result = NutritionDisplayPolicy.v1.evaluate(consumed: 1, target: value, semantics: .maximum)
        #expect(result.status == .invalidInput)
        #expect(result.target == nil)
        #expect(result.progress == nil)
    }

    @Test("Unknown consumed data is unavailable rather than confirmed zero")
    func unknownConsumed() {
        let result = NutritionDisplayPolicy.v1.evaluate(consumed: nil, target: 25, semantics: .minimum)
        #expect(result.status == .unavailable)
        #expect(result.issue == .unknownConsumed)
        #expect(result.remaining == nil)
        #expect(result.progress == nil)
    }

    @Test("Extreme finite inputs have bounded progress and finite compatibility ratio")
    func finiteExtremes() throws {
        let result = NutritionDisplayPolicy.v1.evaluate(consumed: .greatestFiniteMagnitude, target: .leastNonzeroMagnitude, semantics: .budget)
        #expect(result.status == .significantlyOverBudget)
        #expect(result.progress == 1)
        #expect(result.overage?.isFinite == true)
        let energy = EnergyProgressPolicy.standard.evaluate(consumedKcal: .greatestFiniteMagnitude, targetKcal: .leastNonzeroMagnitude)
        #expect(energy.ratio?.isFinite == true)
        #expect(energy.ratioIsSaturated == true)
        #expect(energy.nutritionProgress == result)
    }

    @Test("Policy construction and decoding share strict finite and range validation", arguments: [0.0, 1, -1, Double.nan, .infinity, -.infinity])
    func policyWarningValidation(value: Double) throws {
        let expected = value.isFinite ? DomainValidationError.invalidValue(field: "upperWarningRatio") : .nonFiniteValue(field: "upperWarningRatio")
        #expect(throws: expected) {
            try NutritionDisplayPolicy(upperWarningRatio: value, budgetSignificantOverageRatio: 1.1)
        }
        let data = try changedPolicy(field: "upperWarningRatio", value: value)
        #expect(throws: expected) { try decoder().decode(NutritionDisplayPolicy.self, from: data) }
    }

    @Test("Significant overage policy must be finite and above one", arguments: [0.0, 1, -1, Double.nan, .infinity, -.infinity])
    func policyBudgetValidation(value: Double) throws {
        let expected = value.isFinite ? DomainValidationError.invalidValue(field: "budgetSignificantOverageRatio") : .nonFiniteValue(field: "budgetSignificantOverageRatio")
        #expect(throws: expected) {
            try NutritionDisplayPolicy(upperWarningRatio: 0.8, budgetSignificantOverageRatio: value)
        }
        let data = try changedPolicy(field: "budgetSignificantOverageRatio", value: value)
        #expect(throws: expected) { try decoder().decode(NutritionDisplayPolicy.self, from: data) }
    }

    @Test("Unknown policy versions cannot silently use v1 interpretation", arguments: [0, -1, 2])
    func policyVersionValidation(version: Int) throws {
        #expect(throws: NutritionDisplayPolicyError.unsupportedVersion(version)) {
            try NutritionDisplayPolicy(version: version, upperWarningRatio: 0.8, budgetSignificantOverageRatio: 1.1)
        }
        var object = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(NutritionDisplayPolicy.v1)) as? [String: Any])
        object["version"] = version
        let data = try JSONSerialization.data(withJSONObject: object)
        #expect(throws: NutritionDisplayPolicyError.unsupportedVersion(version)) {
            try JSONDecoder().decode(NutritionDisplayPolicy.self, from: data)
        }
    }

    @Test("Energy wrapper and nutrition evaluator use the same configured policy")
    func energySharesPolicy() throws {
        let policy = try NutritionDisplayPolicy(upperWarningRatio: 0.75, budgetSignificantOverageRatio: 1.2)
        let energy = EnergyProgressPolicy(displayPolicy: policy)
        #expect(energy.significantOverageRatio == policy.budgetSignificantOverageRatio)
        #expect(energy.evaluate(consumedKcal: 115, targetKcal: 100).status == .overTarget)
        #expect(energy.evaluate(consumedKcal: 121, targetKcal: 100).status == .significantlyOverTarget)
        #expect(energy.evaluate(consumedKcal: 0, targetKcal: 0).status == .invalidInput)
        #expect(energy.evaluate(consumedKcal: nil, targetKcal: 0).nutritionProgress.issue == .nonPositiveEnergyTarget)
        #expect(energy.evaluate(consumedKcal: 0, targetKcal: nil).status == .unset)
        #expect(energy.evaluate(consumedKcal: nil, targetKcal: 100).status == .unavailable)
        #expect(try JSONDecoder().decode(EnergyProgressPolicy.self, from: JSONEncoder().encode(energy)) == energy)
    }

    @Test("Below-minimum progress reports a lower-bound deficit only")
    func minimumDeficit() {
        let result = NutritionDisplayPolicy.v1.evaluate(consumed: 100, target: 140, semantics: .minimum)
        #expect(result.status == .belowMinimum)
        #expect(result.remaining == 40)
        #expect(result.overage == nil)
        #expect(result.progress == 100.0 / 140)
    }

    @Test("Every derived state can be encoded without non-finite output and round-trip unchanged", arguments: NutritionGoalSemantics.allCases)
    func summaryRoundTrips(semantics: NutritionGoalSemantics) throws {
        let cases: [(Double?, Double?)] = [(nil, nil), (nil, 100), (0, nil), (0, 0), (1, 0), (79.9, 100), (80, 100), (100, 100), (110, 100), (111, 100), (-1, 100), (.nan, 100), (1, -.infinity), (.greatestFiniteMagnitude, .leastNonzeroMagnitude)]
        for (consumed, target) in cases {
            let summary = NutritionDisplayPolicy.v1.evaluate(consumed: consumed, target: target, semantics: semantics)
            #expect(try JSONDecoder().decode(NutritionProgressSummary.self, from: JSONEncoder().encode(summary)) == summary)
        }
    }

    @Test("Editing a serialized derived status or number cannot bypass recalculation", arguments: ["status", "progress", "remaining", "overage", "policyVersion"])
    func corruptedSummary(field: String) throws {
        let summary = NutritionDisplayPolicy.v1.evaluate(consumed: 110, target: 100, semantics: .maximum)
        var object = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(summary)) as? [String: Any])
        switch field {
        case "status": object[field] = "belowMaximum"
        case "progress": object[field] = 0.5
        case "policyVersion": object[field] = 2
        default: object[field] = 500
        }
        let data = try JSONSerialization.data(withJSONObject: object)
        #expect(throws: NutritionDisplayPolicyError.invalidSummary) {
            try JSONDecoder().decode(NutritionProgressSummary.self, from: data)
        }
    }

    @Test("Malformed derived progress remains subject to finite-value validation", arguments: ["NaN", "Infinity", "-Infinity"])
    func nonFiniteSummary(text: String) throws {
        let summary = NutritionDisplayPolicy.v1.evaluate(consumed: 1, target: 100, semantics: .minimum)
        var object = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(summary)) as? [String: Any])
        object["progress"] = text
        let data = try JSONSerialization.data(withJSONObject: object)
        #expect(throws: DomainValidationError.nonFiniteValue(field: "progress")) {
            try decoder().decode(NutritionProgressSummary.self, from: data)
        }
    }

    @Test("The old energy policy JSON path also validates instead of using a precondition", arguments: [0.0, 1, -1, Double.nan, .infinity, -.infinity])
    func legacyEnergyPolicyValidation(value: Double) throws {
        let expected = value.isFinite ? DomainValidationError.invalidValue(field: "budgetSignificantOverageRatio") : .nonFiniteValue(field: "budgetSignificantOverageRatio")
        #expect(throws: expected) { try EnergyProgressPolicy(significantOverageRatio: value) }
        let jsonValue: Any = value.isFinite ? value : value.isNaN ? "NaN" : value > 0 ? "Infinity" : "-Infinity"
        let data = try JSONSerialization.data(withJSONObject: ["significantOverageRatio": jsonValue])
        #expect(throws: expected) { try decoder().decode(EnergyProgressPolicy.self, from: data) }
    }

    @Test("Energy summaries round-trip safely, including invalid and saturated results")
    func energySummaryRoundTrips() throws {
        let cases: [(Double?, Double?)] = [(nil, nil), (nil, 100), (nil, 0), (0, nil), (0, 0), (1, 0), (100, 100), (111, 100), (-1, 100), (.infinity, 100), (1, .nan), (.greatestFiniteMagnitude, .leastNonzeroMagnitude)]
        for (consumed, target) in cases {
            let summary = EnergyProgressPolicy.standard.evaluate(consumedKcal: consumed, targetKcal: target)
            #expect(try JSONDecoder().decode(EnergyProgressSummary.self, from: JSONEncoder().encode(summary)) == summary)
        }
    }

    @Test("Energy compatibility output cannot forge a normal status or conceal ratio saturation", arguments: ["ratioIsSaturated", "ratio", "status", "ringProgress"])
    func corruptedEnergySummary(field: String) throws {
        let summary = EnergyProgressPolicy.standard.evaluate(consumedKcal: .greatestFiniteMagnitude, targetKcal: .leastNonzeroMagnitude)
        var object = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(summary)) as? [String: Any])
        switch field {
        case "ratioIsSaturated": object[field] = false
        case "status": object[field] = "within_target"
        default: object[field] = 0
        }
        let data = try JSONSerialization.data(withJSONObject: object)
        #expect(throws: NutritionDisplayPolicyError.invalidSummary) {
            try JSONDecoder().decode(EnergyProgressSummary.self, from: data)
        }
    }

    private func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.nonConformingFloatDecodingStrategy = .convertFromString(positiveInfinity: "Infinity", negativeInfinity: "-Infinity", nan: "NaN")
        return decoder
    }

    private func changedPolicy(field: String, value: Double) throws -> Data {
        var object = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(NutritionDisplayPolicy.v1)) as? [String: Any])
        object[field] = value.isFinite ? value : value.isNaN ? "NaN" : value > 0 ? "Infinity" : "-Infinity"
        return try JSONSerialization.data(withJSONObject: object)
    }
}
