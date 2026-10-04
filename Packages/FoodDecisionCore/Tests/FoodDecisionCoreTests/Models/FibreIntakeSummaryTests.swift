import Foundation
import Testing
@testable import FoodDecisionCore

struct FibreIntakeSummaryTests {
    @Test("Partial fibre keeps a known subtotal without claiming an exact total", arguments: [1, 2])
    func partialKnownFibre(unknownCount: Int) throws {
        let values = try [snapshot(fibre: 1.5), snapshot(fibre: 2.5)]
            + Array(repeating: snapshot(fibre: nil), count: unknownCount)
        let summary = try FibreIntakeSummary(snapshots: values)

        #expect(summary.knownSubtotalGrams == 4)
        #expect(summary.knownComponentCount == 2)
        #expect(summary.unknownComponentCount == unknownCount)
        #expect(summary.totalComponentCount == 2 + unknownCount)
        #expect(summary.exactGrams == nil)
        #expect(summary.isComplete == false)
        #expect(summary.hasRecords == true)
    }

    @Test("All-unknown records are not zero intake", arguments: [1, 3])
    func allUnknownFibre(count: Int) throws {
        let values = try Array(repeating: snapshot(fibre: nil), count: count)
        let summary = try FibreIntakeSummary(snapshots: values)

        #expect(summary.knownSubtotalGrams == nil)
        #expect(summary.knownComponentCount == 0)
        #expect(summary.unknownComponentCount == count)
        #expect(summary.totalComponentCount == count)
        #expect(summary.exactGrams == nil)
        #expect(summary.isComplete == false)
        #expect(summary.hasRecords == true)
    }

    @Test("An empty collection is no record, not a complete zero")
    func emptyCollection() throws {
        let summary = try FibreIntakeSummary(snapshots: [])

        #expect(summary.knownSubtotalGrams == nil)
        #expect(summary.knownComponentCount == 0)
        #expect(summary.unknownComponentCount == 0)
        #expect(summary.totalComponentCount == 0)
        #expect(summary.exactGrams == nil)
        #expect(summary.isComplete == false)
        #expect(summary.hasRecords == false)
    }

    @Test("Explicit zero in every recorded component is an exact zero")
    func allKnownZero() throws {
        let summary = try FibreIntakeSummary(snapshots: [.zero, .zero])

        #expect(summary.knownSubtotalGrams == 0)
        #expect(summary.knownComponentCount == 2)
        #expect(summary.unknownComponentCount == 0)
        #expect(summary.totalComponentCount == 2)
        #expect(summary.exactGrams == 0)
        #expect(summary.isComplete == true)
        #expect(summary.hasRecords == true)
    }

    @Test("A known zero and unknown data remain a partial zero subtotal")
    func knownZeroAndUnknown() throws {
        let summary = try FibreIntakeSummary(snapshots: [.zero, snapshot(fibre: nil)])

        #expect(summary.knownSubtotalGrams == 0)
        #expect(summary.knownComponentCount == 1)
        #expect(summary.unknownComponentCount == 1)
        #expect(summary.totalComponentCount == 2)
        #expect(summary.exactGrams == nil)
        #expect(summary.isComplete == false)
        #expect(summary.hasRecords == true)
    }

    @Test("Complete known fibre gives an exact finite sum")
    func allKnownNonzero() throws {
        let summary = try FibreIntakeSummary(snapshots: [snapshot(fibre: 1.25), snapshot(fibre: 2.75)])

        #expect(summary.knownSubtotalGrams == 4)
        #expect(summary.exactGrams == 4)
        #expect(summary.knownComponentCount == 2)
        #expect(summary.unknownComponentCount == 0)
        #expect(summary.isComplete == true)
        #expect(summary.hasRecords == true)
    }

    @Test("Unknown components never mask a known-subtotal overflow", arguments: [false, true])
    func overflow(includeUnknown: Bool) throws {
        var snapshots = try [snapshot(fibre: .greatestFiniteMagnitude)]
        if includeUnknown { snapshots.append(try snapshot(fibre: nil)) }
        snapshots.append(try snapshot(fibre: .greatestFiniteMagnitude))
        let original = snapshots

        #expect(throws: DomainValidationError.calculationOverflow(field: "knownSubtotalGrams")) {
            try FibreIntakeSummary(snapshots: snapshots)
        }
        #expect(snapshots == original)
    }

    @Test("Known subtotals do not rewrite historical nil or change NutrientValues.sum")
    func preservesUnknownSnapshotsAndLegacySum() throws {
        let snapshots = try [snapshot(fibre: 3), snapshot(fibre: nil)]
        let original = snapshots
        let before = try NutrientValues.sum(snapshots)

        let summary = try FibreIntakeSummary(snapshots: snapshots)
        let after = try NutrientValues.sum(snapshots)

        #expect(before.fibreGrams == nil)
        #expect(after == before)
        #expect(snapshots == original)
        #expect(snapshots.last?.fibreGrams == nil)
        #expect(summary.knownSubtotalGrams == 3)
        #expect(summary.exactGrams == nil)
        #expect(try NutrientValues.sum([]).fibreGrams == 0)
    }

    @Test("Flattening meal components keeps fibre that an unknown meal total cannot express")
    func flattenComponentsNotMealTotals() throws {
        let first = try MealLog(
            eatenAt: Date(timeIntervalSinceReferenceDate: 0),
            title: "部分纤维数据餐",
            entryMethod: .weighed,
            coverageStatus: .complete,
            components: [component(fibre: 4), component(fibre: nil)]
        )
        let second = try MealLog(
            eatenAt: Date(timeIntervalSinceReferenceDate: 1),
            title: "明确零纤维餐",
            entryMethod: .weighed,
            coverageStatus: .complete,
            components: [component(fibre: 0)]
        )
        try #require(first.nutrients.fibreGrams == nil)
        try #require(second.nutrients.fibreGrams == 0)

        let meals = [first, second]
        let summary = try FibreIntakeSummary(snapshots: meals.flatMap(\.components).map(\.nutrients))
        let fromMealTotals = try FibreIntakeSummary(snapshots: meals.map(\.nutrients))

        #expect(summary.knownSubtotalGrams == 4)
        #expect(summary.knownComponentCount == 2)
        #expect(summary.unknownComponentCount == 1)
        #expect(summary.totalComponentCount == 3)
        #expect(summary.exactGrams == nil)
        #expect(fromMealTotals.knownSubtotalGrams == 0)
        #expect(first.nutrients.fibreGrams == nil)
    }

    @Test("Invalid fibre cannot enter the validated snapshot boundary", arguments: [Double.nan, .infinity, -.infinity, -1.0])
    func invalidSnapshotFibre(value: Double) {
        let expected = value.isFinite
            ? DomainValidationError.invalidValue(field: "fibreGrams")
            : .nonFiniteValue(field: "fibreGrams")

        #expect(throws: expected) { try snapshot(fibre: value) }
    }

    private func snapshot(fibre: Double?) throws -> NutrientValues {
        try NutrientValues(
            energyKcal: 0,
            fatGrams: 0,
            saturatedFatGrams: 0,
            carbohydrateGrams: 0,
            sugarGrams: 0,
            proteinGrams: 0,
            saltGrams: 0,
            fibreGrams: fibre
        )
    }

    private func component(fibre: Double?) throws -> MealComponent {
        try MealComponent(
            foodItemID: UUID(),
            foodName: "食物",
            consumedWeightGrams: 100,
            unit: "g",
            nutrients: snapshot(fibre: fibre)
        )
    }
}
