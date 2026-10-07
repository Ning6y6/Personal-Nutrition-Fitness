import Foundation
import Testing

@testable import FoodDecisionCore

@Suite("Energy progress")
struct EnergyProgressTests {
    private let policy = EnergyProgressPolicy.v1

    @Test("Progress fills without exceeding one and reports the remaining energy")
    func progressWithinTarget() {
        let summary = policy.evaluate(consumedKcal: 1_200, targetKcal: 2_000)

        #expect(summary.status == .withinTarget)
        #expect(summary.ratio == 0.6)
        #expect(summary.ringProgress == 0.6)
        #expect(summary.remainingKcal == 800)
        #expect(summary.overageKcal == 0)
    }

    @Test("A small overage uses the warning state")
    func smallOverage() {
        let summary = policy.evaluate(consumedKcal: 2_100, targetKcal: 2_000)

        #expect(summary.status == .overTarget)
        #expect(summary.ringProgress == 1)
        #expect(summary.overageKcal == 100)
    }

    @Test("An overage beyond ten percent uses the high warning state")
    func significantOverage() {
        let boundary = policy.evaluate(consumedKcal: 2_200, targetKcal: 2_000)
        let beyondBoundary = policy.evaluate(consumedKcal: 2_201, targetKcal: 2_000)

        #expect(boundary.status == .overTarget)
        #expect(beyondBoundary.status == .significantlyOverTarget)
    }

    @Test("Negative inputs are unavailable, never clamped into a green result")
    func negativeValuesAreRejected() {
        let summary = policy.evaluate(consumedKcal: -100, targetKcal: -1)

        #expect(summary.consumedKcal == nil)
        #expect(summary.targetKcal == nil)
        #expect(summary.ratio == nil)
        #expect(summary.ringProgress == nil)
        #expect(summary.status == .invalidInput)
    }

    @Test("V2 ring has a bounded base lap and at most one overflow lap", arguments: [
        (0.0, 0.0, 0.0), (1_200, 0.6, 0), (2_000, 1, 0),
        (2_500, 1, 0.25), (4_000, 1, 1), (6_400, 1, 1)
    ])
    func twoLapGeometry(consumed: Double, base: Double, overflow: Double) {
        let summary = EnergyProgressPolicy.standard.evaluate(consumedKcal: consumed, targetKcal: 2_000)
        #expect(summary.nutritionProgress.policyVersion == 2)
        #expect(summary.baseLap == base)
        #expect(summary.overflowLap == overflow)
        #expect(summary.multiple == consumed / 2_000)
        #expect(summary.consumedKcal == consumed)
        #expect(summary.overageKcal == max(consumed - 2_000, 0))
    }

    @Test("No target, unknown intake, invalid and zero energy targets do not fabricate laps", arguments: [
        (Optional(0.0), Optional<Double>.none), (Optional<Double>.none, Optional(2_000.0)),
        (Optional(0.0), Optional(0.0)), (Optional(1.0), Optional(0.0)),
        (Optional(-1.0), Optional(2_000.0)), (Optional(Double.infinity), Optional(2_000.0))
    ])
    func unavailableLapGeometry(consumed: Double?, target: Double?) {
        let summary = EnergyProgressPolicy.standard.evaluate(consumedKcal: consumed, targetKcal: target)
        #expect(summary.baseLap == nil)
        #expect(summary.overflowLap == nil)
        #expect(summary.multiple == nil)
        #expect(summary.nutritionProgress.displayTone == .neutral)
    }

    @Test("Extreme finite ratios remain finite and never produce more than two visual laps")
    func saturatedLapGeometry() {
        let summary = EnergyProgressPolicy.standard.evaluate(consumedKcal: .greatestFiniteMagnitude, targetKcal: .leastNonzeroMagnitude)
        #expect(summary.multiple == .greatestFiniteMagnitude)
        #expect(summary.ratioIsSaturated == true)
        #expect(summary.baseLap == 1)
        #expect(summary.overflowLap == 1)
        #expect(summary.nutritionProgress.displayTone == .amber)
    }

    @Test("V1 energy JSON keeps its exact wire format and gains derived laps after decoding")
    func legacyEnergySummaryDecoding() throws {
        let original = EnergyProgressPolicy.v1.evaluate(consumedKcal: 2_500, targetKcal: 2_000)
        let data = try JSONEncoder().encode(original)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["baseLap"] == nil)
        #expect(object["overflowLap"] == nil)
        #expect(object["multiple"] == nil)
        let decoded = try JSONDecoder().decode(EnergyProgressSummary.self, from: data)
        #expect(decoded == original)
        #expect(decoded.nutritionProgress.policyVersion == 1)
        #expect(decoded.baseLap == 1)
        #expect(decoded.overflowLap == 0.25)
        #expect(decoded.multiple == 1.25)
        #expect(decoded.nutritionProgress.displayTone == .critical)
    }
}
