import FoodDecisionCore
import Foundation
import SwiftData
import Testing

@testable import FoodDecisionAssistant

@MainActor
struct FoodCatalogImportCommandTests {
    @Test("Bundled catalog appends once across disk reopen without changing old seeds or snapshots")
    func bundledCatalogPreservesExistingRecordsAcrossReopen() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("catalog.store")
        let catalog = try FoodCatalog.bundled().entries.map(\.food)
        let originalSeeds = try SeedFoodCatalog.loadFoods()
        let originalIDs = Set(originalSeeds.map(\.id))
        let before = try autoreleasepool {
            let store = try container(at: url)
            try populateOriginalRecords(in: store)
            let baseline = try records(in: store)
            let result = try FoodCatalogImportCommand.importIfNeeded(into: store)
            #expect(result.insertedIDs == sorted(catalog.map(\.id).filter { !originalIDs.contains($0) }))
            #expect(result.unchangedIDs == sorted(Array(originalIDs)))
            #expect(result.conflictingIDs.isEmpty)
            #expect(try records(in: store).filter { !result.insertedIDs.contains($0.id) } == baseline)
            return baseline
        }
        try autoreleasepool {
            let reopened = try container(at: url)
            var saveCalled = false
            let repeated = try FoodCatalogImportCommand.importIfNeeded(into: reopened) { _ in saveCalled = true }
            #expect(repeated.insertedCount == 0)
            #expect(repeated.unchangedIDs == sorted(catalog.map(\.id)))
            #expect(repeated.conflictingIDs.isEmpty)
            #expect(saveCalled == false)
            let rows = try ModelContext(reopened).fetch(FetchDescriptor<PersistentFoodItem>())
            #expect(rows.count == catalog.count + 2)
            #expect(Set(rows.map(\.id)).count == rows.count)
            for original in originalSeeds {
                let saved = try #require(rows.first { $0.id == original.id })
                #expect(try saved.domainModel == original)
            }
            #expect(originalSeeds.filter { $0.nutrientsPer100Units.fibreGrams == nil }.count == 6)
            let appendedIDs = Set(catalog.map(\.id)).subtracting(originalIDs)
            #expect(try records(in: reopened).filter { !appendedIDs.contains($0.id) } == before)
        }
    }

    @Test("Every stored food fingerprint field can conflict without being overwritten", arguments: [
        "name", "category", "unit", "source", "energy", "fat", "saturatedFat",
        "carbohydrate", "sugar", "protein", "salt", "fibre",
    ])
    func localConflictRetainsRawContentAndStillAppendsOtherFoods(field: String) throws {
        let store = try container()
        let catalogFood = try food(index: 1)
        let local = PersistentFoodItem(domain: catalogFood)
        switch field {
        case "name": local.name = "local renamed food"
        case "category": local.categoryRawValue = "unrecognized_legacy_category"
        case "unit": local.unit = "local_unit"
        case "source": local.source = "local source"
        case "energy": local.energyKcalPer100Units = -123
        case "fat": local.fatGramsPer100Units += 1
        case "saturatedFat": local.saturatedFatGramsPer100Units += 1
        case "carbohydrate": local.carbohydrateGramsPer100Units += 1
        case "sugar": local.sugarGramsPer100Units += 1
        case "protein": local.proteinGramsPer100Units += 1
        case "salt": local.saltGramsPer100Units += 1
        case "fibre": local.fibreGramsPer100Units = 0 // Catalog nil must stay distinct from zero.
        default: Issue.record("Unexpected fingerprint fixture field")
        }
        store.mainContext.insert(local)
        try store.mainContext.save()
        let before = try records(in: store)
        let addition = try food(index: 2)
        let result = try FoodCatalogImportCommand.importIfNeeded(into: store, foods: [addition, catalogFood])
        #expect(result.insertedIDs == [addition.id])
        #expect(result.unchangedIDs.isEmpty)
        #expect(result.conflictingIDs == [catalogFood.id])
        #expect(try records(in: store).filter { $0.id != addition.id } == before)
        let retry = try FoodCatalogImportCommand.importIfNeeded(into: store, foods: [catalogFood, addition])
        #expect(retry.insertedIDs.isEmpty)
        #expect(retry.unchangedIDs == [addition.id])
        #expect(retry.conflictingIDs == result.conflictingIDs)
    }

    @Test("Identical duplicate inputs insert once; contradictory duplicate IDs reject the whole batch")
    func duplicateInputsCannotTriggerUniqueUpsert() throws {
        let store = try container()
        let first = try food(index: 1)
        var saveCalls = 0
        let result = try FoodCatalogImportCommand.importIfNeeded(into: store, foods: [first, first]) { context in
            saveCalls += 1
            try context.save()
        }
        #expect(result.insertedIDs == [first.id])
        #expect(saveCalls == 1)
        let before = try records(in: store)
        let second = try food(index: 2)
        let contradictory = try FoodItem(id: second.id, name: "different content", category: second.category,
            nutrientsPer100Units: second.nutrientsPer100Units, source: second.source)
        #expect(throws: FoodCatalogImportError.conflictingCatalogID(second.id)) {
            try FoodCatalogImportCommand.importIfNeeded(into: store, foods: [try food(index: 3), second, contradictory])
        }
        #expect(try records(in: store) == before)
    }

    @Test("An empty catalog and a repeated import perform no save")
    func noOpImportDoesNotSave() throws {
        let store = try container()
        var saveCalls = 0
        let empty = try FoodCatalogImportCommand.importIfNeeded(into: store, foods: []) { _ in saveCalls += 1 }
        #expect(empty == FoodCatalogImportResult(insertedIDs: [], unchangedIDs: [], conflictingIDs: []))
        #expect(saveCalls == 0)
        #expect(try records(in: store).isEmpty)
    }

    @Test("Injected failure rolls back the entire private batch and cannot leak through a later shared save")
    func injectedFailureProtectsSharedDraftAndRetry() throws {
        let store = try container()
        try populateOriginalRecords(in: store)
        let before = try records(in: store)
        let draftMeal = try meal(title: "unsaved parent meal")
        store.mainContext.insert(draftMeal)
        let incoming = try [food(index: 1), food(index: 2), food(index: 3)]
        var attempted: ModelContext?
        var saveCalls = 0
        #expect(throws: FoodCatalogImportError.saveFailed) {
            try FoodCatalogImportCommand.importIfNeeded(into: store, foods: incoming) { context in
                attempted = context
                saveCalls += 1
                #expect(context !== store.mainContext)
                #expect(context.autosaveEnabled == false)
                #expect(context.insertedModelsArray.count == incoming.count)
                throw Injected.beforeCommit
            }
        }
        #expect(saveCalls == 1)
        #expect(store.mainContext.hasChanges)
        #expect(attempted?.hasChanges == false)
        #expect(try records(in: store) == before)
        try attempted?.save()
        #expect(try records(in: store) == before)
        try store.mainContext.save()
        #expect(try records(in: store).filter { $0.id != draftMeal.id && $0.entity != .mealComponent } == before.filter { $0.entity != .mealComponent })
        let retry = try FoodCatalogImportCommand.importIfNeeded(into: store, foods: incoming)
        #expect(retry.insertedIDs == sorted(incoming.map(\.id)))
        #expect(retry.conflictingIDs.isEmpty)
    }

    @Test("A successful private append leaves unsaved food, goal, meal and template drafts uncommitted")
    func successfulImportDoesNotCommitSharedDrafts() throws {
        let store = try container()
        try populateOriginalRecords(in: store)
        let before = try records(in: store)
        let shared = store.mainContext
        let draftFood = try food(index: 90)
        shared.insert(PersistentFoodItem(domain: draftFood))
        shared.insert(try meal(title: "unsaved parent meal"))
        shared.insert(PersistentGoalProfile(domain: try GoalProfile(energyKcal: 1777,
            proteinGrams: 100, carbohydrateGrams: 180, fatGrams: 60)))
        let template = try #require(shared.fetch(FetchDescriptor<PersistentMealTemplate>()).first)
        template.name = "unsaved parent template"
        let addition = try food(index: 1)
        var saveCalls = 0
        let result = try FoodCatalogImportCommand.importIfNeeded(into: store, foods: [addition]) { context in
            saveCalls += 1
            #expect(context !== shared)
            #expect(context.autosaveEnabled == false)
            try context.save()
        }
        #expect(result.insertedIDs == [addition.id])
        #expect(saveCalls == 1)
        #expect(shared.hasChanges)
        #expect(template.name == "unsaved parent template")
        #expect(try records(in: store).filter { $0.id != addition.id } == before)
        shared.rollback()
        #expect(try records(in: store).filter { $0.id != addition.id } == before)
    }

    @Test("Pending same-ID local edits are not upserted or resurrected", arguments: ["inserted", "changed", "deleted"])
    func pendingLocalIDRetainsItsUncommittedState(state: String) throws {
        let store = try container()
        let shared = store.mainContext
        shared.autosaveEnabled = false
        let first = try food(index: 1)
        let local = PersistentFoodItem(domain: first)
        shared.insert(local)
        if state != "inserted" { try shared.save() }
        let before = try records(in: store)
        if state == "changed" { local.name = "unsaved local name" }
        if state == "deleted" { shared.delete(local) }
        let addition = try food(index: 2)
        let result = try FoodCatalogImportCommand.importIfNeeded(into: store, foods: [first, addition])
        #expect(result.conflictingIDs == [first.id])
        #expect(result.insertedIDs == [addition.id])
        #expect(shared.hasChanges)
        #expect(try records(in: store).filter { $0.id != addition.id } == before)
        shared.rollback()
        #expect(try records(in: store).filter { $0.id != addition.id } == before)
        let retried = try FoodCatalogImportCommand.importIfNeeded(into: store, foods: [first, addition])
        #expect(retried.conflictingIDs.isEmpty)
    }

    @Test("An actual read-only file-store failure preserves all committed records after reopening and allows retry")
    func realReadOnlyFailureReopenAndRetry() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("readonly.store")
        let incoming = try [food(index: 1), food(index: 2), food(index: 3)]
        let before = try autoreleasepool {
            let writable = try container(at: url)
            try populateOriginalRecords(in: writable)
            return try records(in: writable)
        }
        try autoreleasepool {
            let readOnly = try container(at: url, allowsSave: false)
            readOnly.mainContext.autosaveEnabled = false
            readOnly.mainContext.insert(try meal(title: "unsaved read-only parent meal"))
            #expect(throws: FoodCatalogImportError.saveFailed) {
                try FoodCatalogImportCommand.importIfNeeded(into: readOnly, foods: incoming)
            }
            #expect(readOnly.mainContext.hasChanges)
            #expect(try records(in: readOnly) == before)
        }
        try autoreleasepool {
            let reopened = try container(at: url)
            #expect(try records(in: reopened) == before)
            let retried = try FoodCatalogImportCommand.importIfNeeded(into: reopened, foods: incoming)
            #expect(retried.insertedIDs == sorted(incoming.map(\.id)))
            #expect(try records(in: reopened).filter { !retried.insertedIDs.contains($0.id) } == before)
        }
        let final = try container(at: url)
        #expect(try final.mainContext.fetchCount(FetchDescriptor<PersistentFoodItem>()) == 17)
        #expect(try FoodCatalogImportCommand.importIfNeeded(into: final, foods: incoming).insertedCount == 0)
    }

    @Test("Old V1 and V2 archives can append missing catalog foods without changing restored snapshots", arguments: [1, 2])
    func restoredOldBackupRemainsIntactAndIdempotent(formatVersion: Int) throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = try container()
        try populateOriginalRecords(in: source)
        var document = try LocalStoreBackupCodec.decode(LocalStoreBackupService.export(from: source))
        if formatVersion == 1 {
            document.records.removeAll { $0.entity == .goalVersion }
            document.formatVersion = 1
            document.schemaVersion = "1.0.0"
        }
        try document.validate()
        let restoredURL = try LocalStoreBackupService.stageRestore(data: LocalStoreBackupCodec.encode(document), directory: directory)
        let fullArchive = try autoreleasepool {
            let restored = try container(at: restoredURL)
            #expect(try records(in: restored) == document.canonicalRecords)
            let result = try FoodCatalogImportCommand.importIfNeeded(into: restored)
            #expect(result.conflictingIDs.isEmpty)
            #expect(try records(in: restored).filter { !result.insertedIDs.contains($0.id) } == document.canonicalRecords)
            #expect(try FoodCatalogImportCommand.importIfNeeded(into: restored).insertedCount == 0)
            return try LocalStoreBackupService.export(from: restored)
        }
        let expected = try LocalStoreBackupCodec.decode(fullArchive)
        #expect(expected.formatVersion == 2)
        #expect(expected.schemaVersion == "2.0.0")
        let secondURL = try LocalStoreBackupService.stageRestore(data: fullArchive, directory: directory)
        try autoreleasepool {
            let reopened = try container(at: secondURL)
            #expect(try records(in: reopened) == expected.canonicalRecords)
            #expect(try FoodCatalogImportCommand.importIfNeeded(into: reopened).insertedCount == 0)
            #expect(try records(in: reopened) == expected.canonicalRecords)
        }
    }

    private enum Injected: Error { case beforeCommit }

    private func sorted(_ ids: [UUID]) -> [UUID] { ids.sorted { $0.uuidString < $1.uuidString } }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("food-catalog-test-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        return directory
    }

    private func container(at url: URL? = nil, allowsSave: Bool = true) throws -> ModelContainer {
        let schema = Schema(versionedSchema: VersionedSchemaV2.self)
        let configuration: ModelConfiguration
        if let url {
            configuration = ModelConfiguration(schema: schema, url: url, allowsSave: allowsSave, cloudKitDatabase: .none)
        } else {
            configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        }
        return try ModelContainer(for: schema, migrationPlan: ShiHengMigrationPlan.self, configurations: configuration)
    }

    private func records(in container: ModelContainer) throws -> [LocalStoreBackupRecord] {
        try LocalStoreBackupService.records(from: container)
    }

    private func food(index: Int) throws -> FoodItem {
        let digits = String(index)
        let suffix = String(repeating: "0", count: max(0, 12 - digits.count)) + digits
        let id = try #require(UUID(uuidString: "A0000000-0000-4000-8000-\(suffix)"))
        return try FoodItem(id: id, name: "synthetic food \(index)", category: .mixedMeal,
            nutrientsPer100Units: NutrientValues(energyKcal: Double(50 + index), fatGrams: 1,
                saturatedFatGrams: 0.2, carbohydrateGrams: 8, sugarGrams: 2,
                proteinGrams: 3, saltGrams: 0.1, fibreGrams: nil), source: "synthetic fixture")
    }

    private func meal(title: String) throws -> PersistentMealLog {
        let food = try food(index: 80)
        let first = try MealComponent(foodItemID: food.id, foodName: "first snapshot", consumedWeightGrams: 100,
            unit: "g", nutrients: food.nutrientsPer100Units)
        let second = try MealComponent(foodItemID: food.id, foodName: "second snapshot", consumedWeightGrams: 50,
            unit: "g", nutrients: food.nutrientsPer100Units.scaled(by: 0.5))
        return PersistentMealLog(domain: try MealLog(title: title, entryMethod: .weighed,
            coverageStatus: .complete, components: [first, second]))
    }

    private func populateOriginalRecords(in container: ModelContainer) throws {
        let context = container.mainContext
        context.autosaveEnabled = false
        _ = try SeedFoodCatalog.importIfNeeded(into: context)
        context.insert(PersistentFoodItem(domain: try food(index: 80)))
        let deprecatedID = try #require(UUID(uuidString: "20000000-0000-4000-8000-000000018521"))
        context.insert(PersistentFoodItem(domain: try FoodItem(id: deprecatedID, name: "preserved local deprecated-ID food",
            category: .mixedMeal, nutrientsPer100Units: .zero, source: "synthetic local record")))
        context.insert(PersistentGoalProfile(domain: try GoalProfile(energyKcal: 2000,
            proteinGrams: 140, carbohydrateGrams: 210, fatGrams: 60)))
        let day = try GoalDay(key: 20261018)
        let start = try day.start(in: "Europe/London")
        context.insert(PersistentGoalVersion(domain: try GoalVersion(
            profile: GoalProfile(effectiveFrom: start, energyKcal: 2100, proteinGrams: 140,
                carbohydrateGrams: 200, fatGrams: 60, saturatedFatLimitGrams: 0, fibreGrams: nil),
            effectiveDay: day, source: .selfSelected, confirmedAt: start,
            timeZoneIdentifier: "Europe/London", commitSequence: 1)))
        let savedMeal = try meal(title: "preserved meal snapshot")
        savedMeal.components[0].sortIndex = 8
        savedMeal.components[1].sortIndex = 17
        context.insert(savedMeal)
        let template = try MealTemplate(name: "preserved template", useCount: 7, components: [
            MealTemplateComponent(foodItemID: try food(index: 80).id, foodName: "preserved food name", defaultWeightGrams: 123),
        ])
        context.insert(PersistentMealTemplate(domain: template))
        try context.save()
    }
}
