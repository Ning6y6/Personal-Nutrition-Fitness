import FoodDecisionCore
import Foundation
import SwiftData
import Testing

@testable import FoodDecisionAssistant

/// Saved component snapshots, not the current food catalogue or an optional meal total,
/// are the input to fibre completeness. All relationship fixtures are inserted and saved.
@MainActor
struct FibreSummaryIntegrationTests {
    private let syntheticDay = Date(timeIntervalSince1970: 1_700_000_000)

    @Test("Unknown fibre stays nil in food, meal and component snapshots after a file-store reopen")
    func persistedUnknownIsNeverFilledWithZero() throws {
        let directory = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("fibre-fixture-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("fibre.store")
        let food = try FoodItem(
            name: "synthetic unknown fibre food", category: .mixedMeal,
            nutrientsPer100Units: nutrients(fibre: nil), source: "synthetic test fixture"
        )
        let component = try MealComponent(foodItem: food, consumedWeightGrams: 100)
        let meal = try MealLog(
            eatenAt: syntheticDay, title: "synthetic unknown fibre meal",
            entryMethod: .weighed, coverageStatus: .complete, components: [component]
        )
        try autoreleasepool {
            let container = try makeContainer(at: url)
            let writer = ModelContext(container)
            writer.autosaveEnabled = false
            writer.insert(PersistentFoodItem(domain: food))
            writer.insert(PersistentMealLog(domain: meal))
            try writer.save()
        }

        let reopened = try makeContainer(at: url)
        let reader = ModelContext(reopened)
        reader.autosaveEnabled = false
        let savedFood = try #require(try reader.fetch(FetchDescriptor<PersistentFoodItem>()).first)
        let savedMeal = try #require(try reader.fetch(FetchDescriptor<PersistentMealLog>()).first)
        let savedComponent = try #require(savedMeal.components.first)
        #expect(savedFood.fibreGramsPer100Units == nil)
        #expect(try savedFood.domainModel.nutrientsPer100Units.fibreGrams == nil)
        #expect(savedMeal.fibreGrams == nil)
        #expect(savedComponent.fibreGrams == nil)
        #expect(try savedComponent.domainModel().nutrients.fibreGrams == nil)
        #expect(try savedMeal.domainModel().nutrients.fibreGrams == nil)
        #expect(savedComponent.foodItemID == savedFood.id)
        let fibre = try #require(try daySummary(in: reopened).fibreSummary)
        #expect(fibre.knownSubtotalGrams == nil)
        #expect(fibre.unknownComponentCount == 1)
        #expect(try StoreSchemaCompatibility.modelHashes(at: url) == StoreSchemaCompatibility.frozenModelHashes)
    }

    @Test("Flattening saved components retains known fibre hidden by a mixed meal's nil total")
    func mixedDayDoesNotDropKnownPartsOfMixedMeals() throws {
        let container = try makeContainer()
        let mixed = try meal(fibres: [2, nil])
        let known = try meal(fibres: [3])
        try persist([mixed, known], in: container)

        let result = try daySummary(in: container)
        let fibre = try #require(result.fibreSummary)
        let mixedSnapshot = try #require(result.meals.first { $0.id == mixed.id })
        #expect(mixedSnapshot.nutrients.fibreGrams == nil)
        #expect(result.nutrients?.fibreGrams == nil)
        #expect(result.nutrients?.energyKcal == 300)
        #expect(fibre.knownSubtotalGrams == 5)
        #expect(fibre.knownComponentCount == 2)
        #expect(fibre.unknownComponentCount == 1)
        #expect(fibre.totalComponentCount == 3)
        #expect(fibre.exactGrams == nil)
        #expect(fibre.isComplete == false)
        let display = FibreSummaryPresentation(summary: fibre)
        #expect(display.amountText.contains("至少"))
        #expect(display.amountText.contains("5"))
        #expect(display.detailText?.contains("1个分项") == true)
        #expect(display.detailText?.contains("缺口未确定") == true)
        #expect(display.exactGrams == nil)
    }

    @Test("A day with only unknown component fibre cannot display confirmed zero", arguments: [1, 2])
    func allUnknownIsNotZero(unknownCount: Int) throws {
        let container = try makeContainer()
        try persist([try meal(fibres: Array(repeating: nil, count: unknownCount))], in: container)

        let result = try daySummary(in: container)
        let fibre = try #require(result.fibreSummary)
        #expect(fibre.hasRecords)
        #expect(fibre.knownComponentCount == 0)
        #expect(fibre.unknownComponentCount == unknownCount)
        #expect(fibre.knownSubtotalGrams == nil)
        #expect(fibre.exactGrams == nil)
        #expect(fibre.isComplete == false)
        let display = FibreSummaryPresentation(summary: fibre)
        #expect(display.amountText == "未知")
        #expect(display.detailText?.contains("全部\(unknownCount)个分项") == true)
        #expect(display.detailText?.contains("未显示为0") == true)
        #expect(display.exactGrams == nil)
    }

    @Test("Known zero plus unknown is a lower bound; only complete known zero is exact", arguments: [false, true])
    func knownZeroDoesNotEraseUnknownComponents(includeUnknown: Bool) throws {
        let container = try makeContainer()
        try persist([try meal(fibres: includeUnknown ? [0, nil] : [0])], in: container)
        let result = try daySummary(in: container)
        let fibre = try #require(result.fibreSummary)

        #expect(fibre.knownSubtotalGrams == 0)
        #expect(fibre.knownComponentCount == 1)
        #expect(fibre.unknownComponentCount == (includeUnknown ? 1 : 0))
        #expect(fibre.exactGrams == (includeUnknown ? nil : 0))
        #expect(fibre.isComplete == (includeUnknown == false))
        let display = FibreSummaryPresentation(summary: fibre)
        #expect(display.exactGrams == (includeUnknown ? nil : 0))
        if includeUnknown {
            #expect(display.amountText.contains("至少 0"))
            #expect(display.detailText?.contains("未知") == true)
            #expect(result.nutrients?.fibreGrams == nil)
        } else {
            #expect(display.amountText == "0 g")
            #expect(display.detailText == nil)
            #expect(result.nutrients?.fibreGrams == 0)
        }
    }

    @Test("A complete known fibre day keeps an exact sum eligible for target progress")
    func completeKnownDayIsExact() throws {
        let container = try makeContainer()
        try persist([try meal(fibres: [2]), try meal(fibres: [3])], in: container)
        let result = try daySummary(in: container)
        let fibre = try #require(result.fibreSummary)

        #expect(fibre.hasRecords)
        #expect(fibre.isComplete)
        #expect(fibre.knownComponentCount == 2)
        #expect(fibre.unknownComponentCount == 0)
        #expect(fibre.exactGrams == 5)
        #expect(result.nutrients?.fibreGrams == 5)
        let display = FibreSummaryPresentation(summary: fibre)
        #expect(display.exactGrams == 5)
        #expect(display.amountText.contains("5"))
        #expect(display.amountText.contains("至少") == false)
        #expect(display.detailText == nil)
    }

    @Test("Meal edits and deletions recompute fibre subtotal, completeness and component counts")
    func editsAndDeletesRecomputeSavedDay() throws {
        let container = try makeContainer()
        let original = try meal(fibres: [2, nil])
        let other = try meal(fibres: [3])
        try persist([original, other], in: container)
        let before = try #require(try daySummary(in: container).fibreSummary)
        #expect(before.knownSubtotalGrams == 5)
        #expect(before.knownComponentCount == 2)
        #expect(before.unknownComponentCount == 1)
        #expect(before.exactGrams == nil)

        let writer = ModelContext(container)
        writer.autosaveEnabled = false
        let rows = try writer.fetch(FetchDescriptor<PersistentMealLog>())
        let editedRow = try #require(rows.first { $0.id == original.id })
        let otherRow = try #require(rows.first { $0.id == other.id })
        // Replacing unknown with known changes the daily result without mutating source foods.
        try editedRow.update(from: meal(id: original.id, fibres: [2, 4]), in: writer)
        try writer.save()
        let afterEdit = try #require(try daySummary(in: container).fibreSummary)
        #expect(afterEdit.knownSubtotalGrams == 9)
        #expect(afterEdit.knownComponentCount == 3)
        #expect(afterEdit.unknownComponentCount == 0)
        #expect(afterEdit.exactGrams == 9)

        // Removing a component changes both the sum and denominator used for completeness.
        try editedRow.update(from: meal(id: original.id, fibres: [2]), in: writer)
        try writer.save()
        let afterComponentRemoval = try #require(try daySummary(in: container).fibreSummary)
        #expect(afterComponentRemoval.knownSubtotalGrams == 5)
        #expect(afterComponentRemoval.totalComponentCount == 2)
        #expect(afterComponentRemoval.exactGrams == 5)
        #expect(try writer.fetchCount(FetchDescriptor<PersistentMealComponent>()) == 2)

        writer.delete(editedRow)
        try writer.save()
        let afterMealDeletion = try #require(try daySummary(in: container).fibreSummary)
        #expect(afterMealDeletion.knownSubtotalGrams == 3)
        #expect(afterMealDeletion.totalComponentCount == 1)
        #expect(afterMealDeletion.exactGrams == 3)
        #expect(try writer.fetchCount(FetchDescriptor<PersistentMealComponent>()) == 1)

        writer.delete(otherRow)
        try writer.save()
        let empty = try #require(try daySummary(in: container).fibreSummary)
        #expect(empty.hasRecords == false)
        #expect(empty.totalComponentCount == 0)
        #expect(empty.knownSubtotalGrams == nil)
        #expect(empty.exactGrams == nil)
        #expect(FibreSummaryPresentation(summary: empty).amountText.contains("尚无"))
        #expect(try writer.fetchCount(FetchDescriptor<PersistentMealComponent>()) == 0)
    }

    @Test("Draft D and a damaged historical meal are excluded whole while warning identities remain")
    func invalidAndDraftMealsCannotContributePartialFibre() throws {
        let container = try makeContainer()
        let formal = try meal(fibres: [2, nil])
        let draftDomain = try meal(fibres: [50])
        let invalidDomain = try meal(fibres: [100, 7])
        try persist([formal, draftDomain, invalidDomain], in: container)
        let writer = ModelContext(container)
        writer.autosaveEnabled = false
        let rows = try writer.fetch(FetchDescriptor<PersistentMealLog>())
        let draft = try #require(rows.first { $0.id == draftDomain.id })
        let invalid = try #require(rows.first { $0.id == invalidDomain.id })
        let formalRow = try #require(rows.first { $0.id == formal.id })
        draft.estimateEvidenceGradeRawValue = EstimateEvidenceGrade.d.rawValue
        // Simulate finite, malformed legacy data through raw persistence fields, not a
        // permissive domain constructor. Do not compactMap the surviving valid component.
        let damagedComponent = try #require(invalid.components.first { $0.sortIndex == 0 })
        damagedComponent.fibreGrams = -1
        try writer.save()

        let result = try daySummary(in: container)
        #expect(result.meals.map(\.id) == [formal.id])
        #expect(result.draftRecordIDs == [draftDomain.id])
        #expect(result.invalidRecordIDs == [invalidDomain.id])
        let fibre = try #require(result.fibreSummary)
        #expect(fibre.knownSubtotalGrams == 2)
        #expect(fibre.knownComponentCount == 1)
        #expect(fibre.unknownComponentCount == 1)
        #expect(fibre.totalComponentCount == 2)
        #expect(draft.estimateEvidenceGradeRawValue == "d")
        #expect(damagedComponent.fibreGrams == -1)
        #expect(invalid.components.count == 2)

        writer.delete(formalRow)
        try writer.save()
        let excludedOnly = try daySummary(in: container)
        let emptyFibre = try #require(excludedOnly.fibreSummary)
        #expect(excludedOnly.meals.isEmpty)
        #expect(excludedOnly.draftRecordIDs == [draftDomain.id])
        #expect(excludedOnly.invalidRecordIDs == [invalidDomain.id])
        #expect(emptyFibre.hasRecords == false)
        #expect(emptyFibre.knownSubtotalGrams == nil)
        #expect(emptyFibre.exactGrams == nil)
    }

    @Test("No saved formal components is a no-record state rather than confirmed zero")
    func emptyDayIsNotConfirmedZero() throws {
        let container = try makeContainer()
        let result = try daySummary(in: container)
        let fibre = try #require(result.fibreSummary)

        #expect(fibre.hasRecords == false)
        #expect(fibre.isComplete == false)
        #expect(fibre.totalComponentCount == 0)
        #expect(fibre.knownSubtotalGrams == nil)
        #expect(fibre.exactGrams == nil)
        let display = FibreSummaryPresentation(summary: fibre)
        #expect(display.amountText.contains("尚无"))
        #expect(display.exactGrams == nil)
        #expect(display.detailText == nil)
    }

    @Test("Overflow of valid saved fibre values has an explicit unavailable presentation")
    func dayFibreOverflowCannotBecomeZero() throws {
        let container = try makeContainer()
        try persist([
            try meal(fibres: [.greatestFiniteMagnitude]),
            try meal(fibres: [.greatestFiniteMagnitude]),
        ], in: container)
        let result = try daySummary(in: container)

        #expect(result.meals.count == 2)
        #expect(result.invalidRecordIDs.isEmpty)
        #expect(result.fibreSummary == nil)
        #expect(result.nutrients == nil)
        let display = FibreSummaryPresentation(summary: result.fibreSummary)
        #expect(display.amountText.contains("无法安全计算"))
        #expect(display.detailText?.contains("未显示为0") == true)
        #expect(display.exactGrams == nil)
    }

    @Test("A displayed known lower bound never rounds upwards or says at least less than", arguments: [0.001, 4.99])
    func partialLowerBoundDoesNotOverstateKnownFibre(known: Double) throws {
        let container = try makeContainer()
        try persist([try meal(fibres: [known, nil])], in: container)
        let fibre = try #require(try daySummary(in: container).fibreSummary)
        let display = FibreSummaryPresentation(summary: fibre)
        let token = display.amountText.replacingOccurrences(of: "至少 ", with: "")
            .replacingOccurrences(of: " g", with: "")
        let formatter = NumberFormatter()
        formatter.locale = .current
        formatter.numberStyle = .decimal
        let displayedNumber = try #require(formatter.number(from: token)?.doubleValue)

        #expect(display.amountText.contains("至少"))
        #expect(display.amountText.contains("不足") == false)
        #expect(display.exactGrams == nil)
        #expect(displayedNumber > 0)
        #expect(displayedNumber <= known)
        if known == 4.99 {
            #expect(abs(displayedNumber - 4.9) < 0.000_001)
            #expect(displayedNumber < 5)
        } else {
            #expect(abs(displayedNumber - 0.001) < 0.000_000_001)
        }
    }

    private func nutrients(fibre: Double?) throws -> NutrientValues {
        try NutrientValues(
            energyKcal: 100, fatGrams: 1, saturatedFatGrams: 0,
            carbohydrateGrams: 10, sugarGrams: 0, proteinGrams: 5, saltGrams: 0,
            fibreGrams: fibre
        )
    }

    private func meal(id: UUID = UUID(), fibres: [Double?]) throws -> MealLog {
        let components = try fibres.enumerated().map { index, fibre in
            try MealComponent(
                foodItemID: UUID(), foodName: "synthetic component \(index)",
                consumedWeightGrams: 100, unit: "g", nutrients: nutrients(fibre: fibre)
            )
        }
        return try MealLog(
            id: id, eatenAt: syntheticDay, title: "synthetic fibre meal",
            entryMethod: .weighed, coverageStatus: .complete, components: components
        )
    }

    private func persist(_ meals: [MealLog], in container: ModelContainer) throws {
        let writer = ModelContext(container)
        writer.autosaveEnabled = false
        for meal in meals { writer.insert(PersistentMealLog(domain: meal)) }
        try writer.save()
    }

    private func daySummary(in container: ModelContainer) throws -> MealReadValidation {
        let reader = ModelContext(container)
        reader.autosaveEnabled = false
        let records = try reader.fetch(FetchDescriptor<PersistentMealLog>())
            .filter { Calendar.current.isDate($0.eatenAt, inSameDayAs: syntheticDay) }
        return MealReadValidation(records)
    }

    private func makeContainer(at url: URL? = nil) throws -> ModelContainer {
        let schema = Schema(versionedSchema: VersionedSchemaV1.self)
        let configuration: ModelConfiguration
        if let url { configuration = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none) }
        else { configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none) }
        return try ModelContainer(for: schema, migrationPlan: ShiHengMigrationPlan.self, configurations: configuration)
    }
}
