import Testing

@testable import FoodDecisionCore

@Suite("Energy progress")
struct EnergyProgressTests {
    private let policy = EnergyProgressPolicy.standard

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
}
