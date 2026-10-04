import FoodDecisionCore
import Foundation
import SwiftData
import Testing

@testable import FoodDecisionAssistant

@MainActor
struct DomainBoundaryPersistenceTests {
    @Test("Unknown stored enums never become a valid fallback", arguments: [
        "foodCategory", "mealEntry", "mealCoverage", "mealEvidence", "reviewStatus", "healthObject", "photoStatus", "cookingMethod",
    ])
    func unknownEnumsAreLocated(field: String) throws {
        switch field {
        case "foodCategory":
            let record = PersistentFoodItem(domain: try makeFood())
            record.categoryRawValue = "legacy_unknown_category"
            #expect(throws: PersistentDomainConversionError.unknownEnum(entity: .foodItem, id: record.id, field: "categoryRawValue")) { _ = try record.domainModel }
        case "mealEntry", "mealCoverage", "mealEvidence":
            try withPersisted(PersistentMealLog(domain: makeMeal())) { record, context in
                let rawField: String
                if field == "mealEntry" { record.entryMethodRawValue = "legacy_unknown_entry"; rawField = "entryMethodRawValue" }
                else if field == "mealCoverage" { record.coverageStatusRawValue = "legacy_unknown_coverage"; rawField = "coverageStatusRawValue" }
                else { record.estimateEvidenceGradeRawValue = "legacy_unknown_evidence"; rawField = "estimateEvidenceGradeRawValue" }
                try context.save()
                #expect(throws: PersistentDomainConversionError.unknownEnum(entity: .mealLog, id: record.id, field: rawField)) { _ = try record.domainModel() }
            }
        case "reviewStatus":
            let record = PersistentReviewQueueItem(domain: ReviewQueueItem(missingFields: []))
            record.statusRawValue = "legacy_unknown_status"
            #expect(throws: PersistentDomainConversionError.unknownEnum(entity: .reviewQueueItem, id: record.id, field: "statusRawValue")) { _ = try record.domainModel }
        case "healthObject":
            let record = PersistentHealthKitSyncRecord(domain: HealthKitSyncRecord(mealID: UUID(), objectType: .energy, syncIdentifier: "fixture", syncVersion: 1))
            record.objectTypeRawValue = "legacy_unknown_health_object"
            #expect(throws: PersistentDomainConversionError.unknownEnum(entity: .healthKitSyncRecord, id: record.id, field: "objectTypeRawValue")) { _ = try record.domainModel }
        case "photoStatus":
            try withPersisted(PersistentMealPhotoEstimate(domain: makePhoto())) { record, context in
                record.confirmationStatusRawValue = "legacy_unknown_confirmation"
                try context.save()
                #expect(throws: PersistentDomainConversionError.unknownEnum(entity: .mealPhotoEstimate, id: record.id, field: "confirmationStatusRawValue")) { _ = try record.domainModel() }
            }
        default:
            let record = PersistentMealPhotoComponent(domain: try makePhotoComponent())
            record.cookingMethodRawValue = "legacy_unknown_cooking"
            #expect(throws: PersistentDomainConversionError.unknownEnum(entity: .mealPhotoComponent, id: record.id, field: "cookingMethodRawValue")) { _ = try record.domainModel() }
        }
    }

    @Test("Invalid goal values are located without modifying the raw record", arguments: [-1.0, .infinity, .nan])
    func invalidGoalRemainsRaw(value: Double) throws {
        let row = PersistentGoalProfile(domain: try GoalProfile(energyKcal: 2000, proteinGrams: 140, carbohydrateGrams: 200, fatGrams: 60))
        row.energyKcal = value
        #expect(throws: PersistentDomainConversionError.invalidRecord(entity: .goalProfile, id: row.id, field: "energyKcal")) { _ = try row.domainModel }
        if value.isNaN { #expect(row.energyKcal.isNaN) }
        else { #expect(row.energyKcal == value) }
    }

    @Test("Negative food nutrients and container tare weights are rejected rather than clamped")
    func invalidFoodAndContainerAreLocated() throws {
        let food = PersistentFoodItem(domain: try makeFood())
        food.proteinGramsPer100Units = -1
        #expect(throws: PersistentDomainConversionError.invalidRecord(entity: .foodItem, id: food.id, field: "proteinGrams")) { _ = try food.domainModel }
        #expect(food.proteinGramsPer100Units == -1)
        let container = PersistentContainerProfile(domain: try ContainerProfile(name: "fixture bowl", tareWeightGrams: 10))
        container.tareWeightGrams = -2
        #expect(throws: PersistentDomainConversionError.invalidRecord(entity: .containerProfile, id: container.id, field: "tareWeightGrams")) { _ = try container.domainModel }
        #expect(container.tareWeightGrams == -2)
    }

    @Test("Invalid child weight errors name the child UUID, not just its parent")
    func invalidChildIsLocated() throws {
        try withPersisted(PersistentMealLog(domain: makeMeal())) { parent, _ in
            let child = try #require(parent.components.first)
            // Keep non-finite corruption in memory: SQLite cannot safely round-trip this scalar.
            child.consumedWeightGrams = .infinity
            #expect(throws: PersistentDomainConversionError.invalidRecord(entity: .mealComponent, id: child.id, field: "consumedWeightGrams")) { _ = try parent.domainModel() }
            #expect(child.consumedWeightGrams.isInfinite)
        }
    }

    @Test("Persisted aggregate snapshots must agree with their validated components")
    func inconsistentMealTotalsAreRejected() throws {
        try withPersisted(PersistentMealLog(domain: makeMeal())) { row, context in
            row.energyKcal += 1
            try context.save()
            #expect(throws: PersistentDomainConversionError.invalidRecord(entity: .mealLog, id: row.id, field: "nutrientSnapshot")) { _ = try row.domainModel() }
        }
    }

    @Test("A complete raw D draft cannot become a formal meal or contribute to validated totals")
    func completeDraftCannotEnterFormalStatistics() throws {
        let container = try makeContainer()
        let confirmed = PersistentMealLog(domain: try makeMeal())
        let draft = PersistentMealLog(domain: try makeMeal())
        draft.estimateEvidenceGradeRawValue = EstimateEvidenceGrade.d.rawValue
        draft.coverageStatusRawValue = MealCoverageStatus.complete.rawValue
        container.mainContext.insert(confirmed)
        container.mainContext.insert(draft)
        try container.mainContext.save()
        #expect(throws: PersistentDomainConversionError.invalidRecord(entity: .mealLog, id: draft.id, field: "estimateEvidenceGrade")) { _ = try draft.domainModel() }
        let validation = MealReadValidation(try container.mainContext.fetch(FetchDescriptor<PersistentMealLog>()))
        #expect(validation.meals.map(\.id) == [confirmed.id])
        #expect(validation.draftRecordIDs == [draft.id])
        #expect(validation.nutrients?.energyKcal == 100)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<PersistentMealLog>()) == 2)
    }

    @Test("A user-confirmed C estimate with complete coverage remains a formal complete meal")
    func confirmedEstimateRemainsComplete() throws {
        let original = try makeMeal()
        let confirmed = try MealLog(id: original.id, eatenAt: original.eatenAt, title: original.title, consumedWeightGrams: original.consumedWeightGrams, nutrients: original.nutrients, entryMethod: .standardPortionEstimate, coverageStatus: .complete, estimateEvidenceGrade: .c, components: original.components)
        try withPersisted(PersistentMealLog(domain: confirmed)) { row, _ in
            let result = try row.domainModel()
            #expect(result.estimateEvidenceGrade == .c)
            #expect(result.isCompleteForDailyCoverage)
            #expect(result == confirmed)
        }
    }

    @Test("Invalid history including D, negative values and empty components survives raw disk restoration")
    func invalidHistoryStillBacksUpAndRestores() throws {
        let directory = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("domain-boundary-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let sourceURL = directory.appendingPathComponent("source.store")
        let rawID = UUID()
        let archive = try autoreleasepool {
            let source = try makeContainer(at: sourceURL)
            let row = PersistentMealLog(domain: try makeMeal())
            for child in row.components { child.meal = nil }
            row.components = []
            row.id = rawID
            row.title = ""
            row.consumedWeightGrams = -2
            row.energyKcal = -5
            row.estimateEvidenceGradeRawValue = EstimateEvidenceGrade.d.rawValue
            row.entryMethodRawValue = "unrecognized historical method"
            row.healthKitSyncVersion = 0
            row.fibreGrams = nil
            source.mainContext.insert(row)
            try source.mainContext.save()
            return try LocalStoreBackupService.export(from: source)
        }
        let candidate = try LocalStoreBackupService.stageRestore(data: archive, directory: directory)
        let reopened = try makeContainer(at: candidate)
        let expected = try LocalStoreBackupCodec.decode(archive).canonicalRecords
        #expect(try LocalStoreBackupService.records(from: reopened) == expected)
        let row = try #require(reopened.mainContext.fetch(FetchDescriptor<PersistentMealLog>()).first)
        #expect(row.id == rawID)
        #expect(row.components.isEmpty)
        #expect(row.energyKcal == -5)
        #expect(row.fibreGrams == nil)
        #expect(row.estimateEvidenceGradeRawValue == "d")
        #expect(row.entryMethodRawValue == "unrecognized historical method")
        #expect(throws: PersistentDomainConversionError.invalidRecord(entity: .mealLog, id: rawID, field: "energyKcal")) { _ = try row.domainModel() }
        #expect(try StoreSchemaCompatibility.modelHashes(at: sourceURL) == StoreSchemaCompatibility.frozenModelHashes)
        #expect(try StoreSchemaCompatibility.modelHashes(at: candidate) == StoreSchemaCompatibility.frozenModelHashes)
    }

    @Test("Seed validation retains unknown fibre as nil instead of manufacturing zero")
    func seedsRetainMissingNutrients() throws {
        let seeds = try SeedFoodCatalog.loadFoods()
        #expect(seeds.count == 12)
        let pepper = try #require(seeds.first { $0.name == "青椒（生）" })
        #expect(pepper.nutrientsPer100Units.fibreGrams == nil)
        #expect(pepper.source.contains("CoFID 2021"))
        let persisted = PersistentFoodItem(domain: pepper)
        #expect(try persisted.domainModel.nutrientsPer100Units.fibreGrams == nil)
    }

    @Test("Wrong meal/template identities fail before mutating any stored field")
    func identityMismatchCannotWrite() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let original = try makeMeal()
        let row = PersistentMealLog(domain: original)
        context.insert(row)
        try context.save()
        #expect(throws: PersistentDomainConversionError.mismatchedIdentity(entity: .mealLog, id: row.id)) { try row.update(from: makeMeal(), in: context) }
        #expect(try row.domainModel() == original)
        let template = try MealTemplate(meal: original)
        let persisted = PersistentMealTemplate(domain: template)
        context.insert(persisted)
        try context.save()
        #expect(throws: PersistentDomainConversionError.mismatchedIdentity(entity: .mealTemplate, id: persisted.id)) { try persisted.update(from: MealTemplate(meal: original), in: context) }
        #expect(try persisted.domainModel() == template)
    }

    @Test("Usage overflow does not partially update a template's timestamp or counter")
    func templateUsageOverflowIsAtomic() throws {
        let template = try MealTemplate(name: "fixture", useCount: Int.max, components: [MealTemplateComponent(foodItemID: UUID(), foodName: "fixture", defaultWeightGrams: 1)])
        try withPersisted(PersistentMealTemplate(domain: template)) { row, _ in
            #expect(throws: MealTemplateError.useCountOverflow) { try row.markUsed() }
            #expect(row.useCount == Int.max)
            #expect(row.lastUsedAt == nil)
        }
    }

    private func makeFood() throws -> FoodItem {
        try FoodItem(name: "fixture food", category: .mixedMeal, nutrientsPer100Units: NutrientValues(energyKcal: 100, fatGrams: 1, saturatedFatGrams: 0, carbohydrateGrams: 10, sugarGrams: 0, proteinGrams: 10, saltGrams: 0, fibreGrams: nil), source: "fixture")
    }

    private func makeMeal() throws -> MealLog {
        try MealLog(title: "fixture meal", entryMethod: .weighed, coverageStatus: .complete, components: [MealComponent(foodItem: makeFood(), consumedWeightGrams: 100)])
    }

    private func makePhotoComponent() throws -> MealPhotoComponent {
        try MealPhotoComponent(freeTextName: "fixture component", cookingMethod: .boiled, portionRange: PortionEstimateRange(lowGrams: 50, midpointGrams: 100, highGrams: 150), confidence: 0.8)
    }

    private func makePhoto() throws -> MealPhotoEstimate {
        try MealPhotoEstimate(mealTitle: "fixture photo", imageReference: "sha256:fixture", providerName: "fixture", modelVersion: "1", outputSchemaVersion: "1", confirmationStatus: .confirmed, consumedShareRatio: 1, components: [makePhotoComponent()])
    }

    private func makeContainer(at url: URL? = nil) throws -> ModelContainer {
        let schema = Schema(versionedSchema: VersionedSchemaV1.self)
        let configuration: ModelConfiguration
        if let url { configuration = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none) }
        else { configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none) }
        return try ModelContainer(for: schema, migrationPlan: ShiHengMigrationPlan.self, configurations: configuration)
    }

    /// An uninserted @Model's inverse relationships are not a persisted-record fixture. Keep its
    /// container alive and save the relationship graph before exercising strict domain conversion.
    private func withPersisted<Row: PersistentModel>(
        _ row: Row, assertion: (Row, ModelContext) throws -> Void
    ) throws {
        let container = try makeContainer()
        let context = container.mainContext
        context.autosaveEnabled = false
        context.insert(row)
        try context.save()
        try assertion(row, context)
    }
}
