import FoodDecisionCore
import Foundation
import SwiftData
import Testing

@testable import FoodDecisionAssistant

/// Availability is derived from saved records, not from the mathematical value of an empty sum.
/// Every relationship fixture is inserted and saved before a fresh context reads it.
@MainActor
struct MealIntakeAvailabilityTests {
    @Test("No saved meal is unavailable for progress even though the mathematical sum is zero")
    func noRecordsIsNotConfirmedZero() throws {
        let container = try makeContainer()
        let result = try readSummary(in: container)

        #expect(result.availability == .noRecords)
        #expect(result.availability.canShowNutritionProgress == false)
        #expect(result.meals.isEmpty)
        #expect(result.nutrients == .zero)
        #expect(try NutrientValues.sum([]) == .zero)
        #expect(result.invalidRecordIDs.isEmpty)
        #expect(result.draftRecordIDs.isEmpty)
        let fibre = try #require(result.fibreSummary)
        #expect(fibre.hasRecords == false)
        #expect(fibre.exactGrams == nil)
        #expect(result.availability.title.contains("尚未记录"))
        #expect(result.availability.explanation.contains("不代表"))
    }

    @Test("Only valid confirmed records can unlock intake progress", arguments: [
        MealIntakeAvailability.noRecords, .noConfirmedRecords, .available, .unavailable,
    ])
    func progressGate(availability: MealIntakeAvailability) {
        #expect(availability.canShowNutritionProgress == (availability == .available))
        if availability != .available {
            #expect(availability.explanation.isEmpty == false)
            #expect(availability.title.contains("已达") == false)
            #expect(availability.explanation.contains("预算剩余") == false)
        }
    }

    @Test("Saved drafts and invalid rows remain distinguishable from no records", arguments: ["draft", "invalid", "both"])
    func excludedRowsDoNotCreateEmptyDaySuccess(scenario: String) throws {
        let container = try makeContainer()
        let expected = try saveScenario(scenario, in: container)
        let result = try readSummary(in: container)

        #expect(result.availability == .noConfirmedRecords)
        #expect(result.availability.canShowNutritionProgress == false)
        #expect(result.meals.isEmpty)
        #expect(result.nutrients == .zero)
        #expect(Set(result.draftRecordIDs) == expected.draftIDs)
        #expect(Set(result.invalidRecordIDs) == expected.invalidIDs)
        #expect(result.availability.explanation.contains("草稿"))
        #expect(result.availability.explanation.contains("旧记录"))
        let reader = ModelContext(container)
        reader.autosaveEnabled = false
        let raw = try reader.fetch(FetchDescriptor<PersistentMealLog>())
        #expect(raw.count == expected.recordCount)
        #expect(raw.filter { $0.estimateEvidenceGradeRawValue == "d" }.count == expected.draftIDs.count)
        #expect(raw.filter { $0.coverageStatusRawValue == "synthetic_invalid_coverage" }.count == expected.invalidIDs.count)
    }

    @Test("A saved real zero-nutrient meal remains available for normal progress", arguments: [EstimateEvidenceGrade.a, .b, .c])
    func confirmedZeroIsNotMissing(grade: EstimateEvidenceGrade) throws {
        let container = try makeContainer()
        let row = try makeMeal(energy: 0, grade: grade, fibre: 0)
        let writer = ModelContext(container)
        writer.autosaveEnabled = false
        writer.insert(row)
        try writer.save()

        let result = try readSummary(in: container)
        #expect(result.availability == .available)
        #expect(result.availability.canShowNutritionProgress)
        #expect(result.meals.map(\.id) == [row.id])
        #expect(result.nutrients == .zero)
        #expect(result.invalidRecordIDs.isEmpty)
        #expect(result.draftRecordIDs.isEmpty)
        let fibre = try #require(result.fibreSummary)
        #expect(fibre.hasRecords)
        #expect(fibre.exactGrams == 0)
        let progress = NutritionDisplayPolicy.v1.evaluate(consumed: result.nutrients?.energyKcal, target: 2_000, semantics: .budget)
        #expect(progress.progress == 0)
        #expect(progress.status == .withinBudget)
    }

    @Test("A valid record is summarized without recovering excluded rows or claiming the full day")
    func mixedRecordsKeepKnownRecordedIntake() throws {
        let container = try makeContainer()
        let expected = try saveScenario("mixed", in: container)
        let result = try readSummary(in: container)

        #expect(result.availability == .available)
        #expect(result.availability.canShowNutritionProgress)
        #expect(result.meals.count == 1)
        #expect(result.nutrients?.energyKcal == 100)
        #expect(Set(result.draftRecordIDs) == expected.draftIDs)
        #expect(Set(result.invalidRecordIDs) == expected.invalidIDs)
        #expect(result.availability.title == "今日已记录摄入")
        #expect(result.fibreSummary?.unknownComponentCount == 1)
        #expect(result.fibreSummary?.exactGrams == nil)
    }

    @Test("Finite records whose aggregate overflows stay unavailable instead of returning zero")
    func overflowNeverUnlocksProgress() throws {
        let container = try makeContainer()
        _ = try saveScenario("overflow", in: container)
        let result = try readSummary(in: container)

        #expect(result.availability == .unavailable)
        #expect(result.availability.canShowNutritionProgress == false)
        #expect(result.meals.count == 2)
        #expect(result.nutrients == nil)
        #expect(result.invalidRecordIDs.isEmpty)
        #expect(result.draftRecordIDs.isEmpty)
        #expect(result.availability.explanation.contains("未按 0"))
    }

    @Test("Removing the last formal meal reclassifies remaining drafts and then a truly empty store")
    func removalRecomputesAvailabilityWithoutDiscardingDrafts() throws {
        let container = try makeContainer()
        _ = try saveScenario("mixed", in: container)
        let writer = ModelContext(container)
        writer.autosaveEnabled = false
        let saved = try writer.fetch(FetchDescriptor<PersistentMealLog>())
        let confirmed = try #require(saved.first { $0.energyKcal == 100 })
        writer.delete(confirmed)
        try writer.save()
        let excluded = try readSummary(in: container)
        #expect(excluded.availability == .noConfirmedRecords)
        #expect(excluded.draftRecordIDs.count == 1)
        #expect(excluded.invalidRecordIDs.count == 1)
        #expect(excluded.availability.canShowNutritionProgress == false)

        for row in try writer.fetch(FetchDescriptor<PersistentMealLog>()) { writer.delete(row) }
        try writer.save()
        let empty = try readSummary(in: container)
        #expect(empty.availability == .noRecords)
        #expect(empty.invalidRecordIDs.isEmpty)
        #expect(empty.draftRecordIDs.isEmpty)
        #expect(empty.availability.canShowNutritionProgress == false)
    }

    @Test("Availability and excluded raw records survive a file-backed save and reopen", arguments: ["empty", "draft", "invalid", "both", "zero", "mixed", "overflow"])
    func fileStoreReopen(scenario: String) throws {
        let directory = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("intake-availability-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("synthetic-intake.store")
        let expected = try autoreleasepool {
            let container = try makeContainer(at: url)
            return try saveScenario(scenario, in: container)
        }

        let reopened = try makeContainer(at: url)
        let result = try readSummary(in: reopened)
        #expect(result.availability == expected.availability)
        #expect(result.availability.canShowNutritionProgress == (expected.availability == .available))
        #expect(Set(result.draftRecordIDs) == expected.draftIDs)
        #expect(Set(result.invalidRecordIDs) == expected.invalidIDs)
        #expect(result.nutrients?.energyKcal == expected.energy)
        let reader = ModelContext(reopened)
        reader.autosaveEnabled = false
        #expect(try reader.fetchCount(FetchDescriptor<PersistentMealLog>()) == expected.recordCount)
        #expect(try StoreSchemaCompatibility.modelHashes(at: url) == StoreSchemaCompatibility.frozenModelHashes)
    }

    private func saveScenario(_ scenario: String, in container: ModelContainer) throws -> ScenarioExpectation {
        let writer = ModelContext(container)
        writer.autosaveEnabled = false
        var rows: [PersistentMealLog] = []
        if ["draft", "both", "mixed"].contains(scenario) { rows.append(try makeMeal(energy: 200)) }
        if ["invalid", "both", "mixed"].contains(scenario) { rows.append(try makeMeal(energy: 300)) }
        if scenario == "zero" { rows.append(try makeMeal(energy: 0, fibre: 0)) }
        if scenario == "mixed" { rows.append(try makeMeal(energy: 100)) }
        if scenario == "overflow" {
            rows.append(try makeMeal(energy: .greatestFiniteMagnitude))
            rows.append(try makeMeal(energy: .greatestFiniteMagnitude))
        }
        for row in rows { writer.insert(row) }
        try writer.save()
        var draftIDs: Set<UUID> = []
        var invalidIDs: Set<UUID> = []
        if ["draft", "both", "mixed"].contains(scenario), let draft = rows.first {
            draft.estimateEvidenceGradeRawValue = "d"
            draftIDs.insert(draft.id)
        }
        if ["invalid", "both", "mixed"].contains(scenario) {
            let index = scenario == "invalid" ? 0 : 1
            rows[index].coverageStatusRawValue = "synthetic_invalid_coverage"
            invalidIDs.insert(rows[index].id)
        }
        try writer.save()
        let availability: MealIntakeAvailability
        let energy: Double?
        switch scenario {
        case "empty": availability = .noRecords; energy = 0
        case "zero": availability = .available; energy = 0
        case "mixed": availability = .available; energy = 100
        case "overflow": availability = .unavailable; energy = nil
        default: availability = .noConfirmedRecords; energy = 0
        }
        return ScenarioExpectation(availability: availability, energy: energy, recordCount: rows.count, draftIDs: draftIDs, invalidIDs: invalidIDs)
    }

    private func makeMeal(energy: Double, grade: EstimateEvidenceGrade = .a, fibre: Double? = nil) throws -> PersistentMealLog {
        let nutrients = try NutrientValues(
            energyKcal: energy, fatGrams: 0, saturatedFatGrams: 0, carbohydrateGrams: 0,
            sugarGrams: 0, proteinGrams: 0, saltGrams: 0, fibreGrams: fibre
        )
        let component = try MealComponent(foodItemID: UUID(), foodName: "synthetic fixture", consumedWeightGrams: 1, unit: "g", nutrients: nutrients)
        return PersistentMealLog(domain: try MealLog(
            eatenAt: Date(timeIntervalSince1970: 1_700_000_000), title: "synthetic meal",
            consumedWeightGrams: 1, nutrients: nutrients, coverageStatus: .complete,
            estimateEvidenceGrade: grade, components: [component]
        ))
    }

    private func readSummary(in container: ModelContainer) throws -> MealReadValidation {
        let reader = ModelContext(container)
        reader.autosaveEnabled = false
        return MealReadValidation(try reader.fetch(FetchDescriptor<PersistentMealLog>()))
    }

    private func makeContainer(at url: URL? = nil) throws -> ModelContainer {
        let schema = Schema(versionedSchema: VersionedSchemaV1.self)
        let configuration: ModelConfiguration
        if let url {
            configuration = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        } else {
            configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        }
        return try ModelContainer(for: schema, migrationPlan: ShiHengMigrationPlan.self, configurations: [configuration])
    }

    private struct ScenarioExpectation {
        let availability: MealIntakeAvailability
        let energy: Double?
        let recordCount: Int
        let draftIDs: Set<UUID>
        let invalidIDs: Set<UUID>
    }
}
