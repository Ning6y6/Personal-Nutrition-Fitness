import FoodDecisionCore
import Foundation
import SwiftData
import Testing
@testable import FoodDecisionAssistant

@MainActor
struct PersonalFoodCompatibilityTests {
    @Test("V2 file reopen, catalog bootstrap and backup 2 preserve card IDs/source/nil versus zero and old meal snapshots")
    func fileCatalogHistoryAndBackupRoundTrip() throws {
        let directory = try temporaryDirectory()
        let url = directory.appendingPathComponent("cards.store")
        let original = try food(energy: 400, name: "old synthetic food", fibre: nil)
        let knownZero = try food(energy: 0, name: "known zero fibre", fibre: 0)
        let unknownID = UUID()
        let unknown = try FoodItem(id: unknownID, name: "unknown preserved food", category: .mixedMeal,
            nutrientsPer100Units: .zero, source: "unmarked legacy source")
        let baseline = try autoreleasepool { () throws -> (UUID, UUID, MealEditSnapshot, FoodItem) in
            let c = try container(url: url)
            for card in [original, knownZero] {
                _ = try PersonalFoodSaveCommand.save(request: PersonalFoodSaveRequest(food: card, intent: .create), container: c)
            }
            c.mainContext.insert(PersistentFoodItem(domain: unknown))
            let oldMeal = try meal(food: original, title: "historical synthetic meal", weight: 30)
            c.mainContext.insert(oldMeal)
            let template = PersistentMealTemplate(domain: try MealTemplate(name: "historical template", components: [
                MealTemplateComponent(foodItemID: original.id, foodName: original.name, defaultWeightGrams: 30),
            ]))
            c.mainContext.insert(template)
            try c.mainContext.save()
            let before = MealEditSnapshot(oldMeal)
            #expect(before.nutrition.energyKcal == 120)

            let target = try food(id: original.id, energy: 450, name: "new synthetic food", fibre: nil)
            _ = try PersonalFoodSaveCommand.save(request: PersonalFoodSaveRequest(food: target, intent: .edit(original: original)), container: c)
            #expect(try snapshot(in: c, id: oldMeal.id) == before)
            let renamed = try MealEditCommand.save(baseline: before,
                changes: MealEditChanges(title: "renamed historical meal"), in: c)
            #expect(renamed.nutrition.energyKcal == 120)
            #expect(renamed.components.first?.foodName == original.name)
            let part = try #require(renamed.originalComponents().first)
            let scaled = try MealComponentEditPolicy.resolve(original: part, id: part.id,
                foodItemID: part.foodItemID, weightGrams: 40, currentFood: target)
            let changed = try MealEditCommand.save(baseline: renamed,
                changes: MealEditChanges(components: [scaled]), in: c)
            #expect(abs(changed.nutrition.energyKcal - 160) < 1e-10)
            #expect(changed.components.first?.id == part.id)
            #expect(changed.components.first?.foodName == original.name)

            let current = try readFood(in: c, id: target.id)
            let newMeal = try meal(food: current, title: "new current-card meal", weight: 30)
            c.mainContext.insert(newMeal)
            try c.mainContext.save()
            #expect(newMeal.energyKcal == 135)
            #expect(newMeal.components.first?.foodName == target.name)
            let templateBefore = try template.domainModel()
            _ = try SeedFoodCatalog.importIfNeeded(into: c.mainContext)
            let imported = try FoodCatalogImportCommand.importIfNeeded(into: c)
            #expect(imported.conflictingIDs.isEmpty)
            #expect(try FoodCatalogImportCommand.importIfNeeded(into: c).insertedCount == 0)
            #expect(try SeedFoodCatalog.importIfNeeded(into: c.mainContext) == 0)
            #expect(try readFood(in: c, id: target.id) == target)
            #expect(try readFood(in: c, id: knownZero.id) == knownZero)
            #expect(try readFood(in: c, id: unknown.id) == unknown)
            #expect(try template.domainModel() == templateBefore)
            #expect(try snapshot(in: c, id: oldMeal.id) == changed)
            return (oldMeal.id, newMeal.id, changed, target)
        }

        let archive = try autoreleasepool { () throws -> Data in
            let reopened = try container(url: url)
            let identity = try PersonalFoodIdentity()
            let card = try readFood(in: reopened, id: original.id)
            #expect(card == baseline.3)
            #expect(card.nutrientsPer100Units.fibreGrams == nil)
            #expect(identity.isEditable(card))
            #expect(identity.verifiedSource(for: card)?.note == "Synthetic label\nCoFID is user text; 100 g\t原文")
            #expect(try readFood(in: reopened, id: knownZero.id).nutrientsPer100Units.fibreGrams == 0)
            #expect(identity.isEditable(try readFood(in: reopened, id: unknown.id)) == false)
            #expect(try snapshot(in: reopened, id: baseline.0) == baseline.2)
            #expect(try snapshot(in: reopened, id: baseline.1).nutrition.energyKcal == 135)
            return try LocalStoreBackupService.export(from: reopened)
        }
        let document = try LocalStoreBackupCodec.decode(archive)
        #expect(document.formatVersion == 2)
        #expect(document.schemaVersion == "2.0.0")
        let restoredURL = try LocalStoreBackupService.stageRestore(data: archive,
            directory: directory.appendingPathComponent("restore"))
        try autoreleasepool {
            let restored = try container(url: restoredURL)
            let identity = try PersonalFoodIdentity()
            #expect(try LocalStoreBackupService.records(from: restored) == document.canonicalRecords)
            #expect(try readFood(in: restored, id: original.id) == baseline.3)
            #expect(identity.isEditable(try readFood(in: restored, id: original.id)))
            #expect(identity.isEditable(try readFood(in: restored, id: knownZero.id)))
            #expect(identity.isEditable(try readFood(in: restored, id: unknown.id)) == false)
            #expect(try snapshot(in: restored, id: baseline.0) == baseline.2)
            #expect(try snapshot(in: restored, id: baseline.1).nutrition.energyKcal == 135)
            let before = try LocalStoreBackupService.records(from: restored)
            #expect(try FoodCatalogImportCommand.importIfNeeded(into: restored).insertedCount == 0)
            #expect(try SeedFoodCatalog.importIfNeeded(into: restored.mainContext) == 0)
            #expect(try LocalStoreBackupService.records(from: restored) == before)
        }
    }

    @Test("A real read-only store rejects card creation/edit without modifying committed records and writable reopen can retry",
          arguments: [false, true])
    func actualReadOnlyFailureAndRetry(edit: Bool) throws {
        let directory = try temporaryDirectory()
        let url = directory.appendingPathComponent("read-only.store")
        let original = try food(energy: 400)
        let before = try autoreleasepool { () throws -> [LocalStoreBackupRecord] in
            let c = try container(url: url)
            if edit {
                _ = try PersonalFoodSaveCommand.save(request: PersonalFoodSaveRequest(food: original, intent: .create), container: c)
            }
            c.mainContext.insert(try meal(food: original, title: "preserved original meal", weight: 30))
            try c.mainContext.save()
            return try LocalStoreBackupService.records(from: c)
        }
        let target = try food(id: original.id, energy: 450)
        let request = PersonalFoodSaveRequest(food: target, intent: edit ? .edit(original: original) : .create)
        try autoreleasepool {
            let readOnly = try container(url: url, allowsSave: false)
            readOnly.mainContext.insert(try meal(food: original, title: "unsaved parent meal", weight: 40))
            #expect(throws: PersonalFoodSaveCommandError.saveFailed) {
                try PersonalFoodSaveCommand.save(request: request, container: readOnly)
            }
            #expect(readOnly.mainContext.hasChanges)
            #expect(try LocalStoreBackupService.records(from: readOnly) == before)
        }
        try autoreleasepool {
            let writable = try container(url: url)
            #expect(try LocalStoreBackupService.records(from: writable) == before)
            #expect(try PersonalFoodSaveCommand.save(request: request, container: writable) == target)
            #expect(try readFood(in: writable, id: original.id) == target)
            #expect(try ModelContext(writable).fetchCount(FetchDescriptor<PersistentMealLog>()) == 1)
        }
    }

    @Test("An edit writes every supported scalar while retaining its ID and creates no intake")
    func allSupportedCardValuesCanChange() throws {
        let c = try container()
        let original = try food(energy: 400)
        _ = try PersonalFoodSaveCommand.save(request: PersonalFoodSaveRequest(food: original, intent: .create), container: c)
        let target = try FoodItem(id: original.id, name: "all values changed", category: .sauce,
            nutrientsPer100Units: NutrientValues(energyKcal: 123.45, fatGrams: 1.25, saturatedFatGrams: 0.75,
                carbohydrateGrams: 12.25, sugarGrams: 2.5, proteinGrams: 8.5, saltGrams: 0.75, fibreGrams: 0),
            source: PersonalFoodSource.encode(foodID: original.id, note: "new\n原文"))
        #expect(try PersonalFoodSaveCommand.save(request: PersonalFoodSaveRequest(food: target,
            intent: .edit(original: original)), container: c) == target)
        #expect(try readFood(in: c, id: original.id) == target)
        #expect(try ModelContext(c).fetchCount(FetchDescriptor<PersistentFoodItem>()) == 1)
        #expect(try ModelContext(c).fetchCount(FetchDescriptor<PersistentMealLog>()) == 0)
    }

    private func container(url: URL? = nil, allowsSave: Bool = true) throws -> ModelContainer {
        let schema = Schema(versionedSchema: VersionedSchemaV2.self)
        let configuration = url.map { ModelConfiguration(schema: schema, url: $0, allowsSave: allowsSave, cloudKitDatabase: .none) }
            ?? ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let c = try ModelContainer(for: schema, migrationPlan: ShiHengMigrationPlan.self, configurations: configuration)
        c.mainContext.autosaveEnabled = false
        return c
    }

    private func temporaryDirectory() throws -> URL {
        // Keep synthetic SQLite artifacts until the QA App's lifecycle reclaims
        // them: SwiftData can close a file asynchronously after its scope ends.
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("personal-food-compatibility-synthetic-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func food(id: UUID = UUID(), energy: Double, name: String = "synthetic card", fibre: Double? = nil) throws -> FoodItem {
        try FoodItem(id: id, name: name, category: .snackDessert,
            nutrientsPer100Units: NutrientValues(energyKcal: energy, fatGrams: 8, saturatedFatGrams: 2,
                carbohydrateGrams: 40, sugarGrams: 3, proteinGrams: 35, saltGrams: 0, fibreGrams: fibre),
            source: PersonalFoodSource.encode(foodID: id, note: "Synthetic label\nCoFID is user text; 100 g\t原文"))
    }

    private func meal(food: FoodItem, title: String, weight: Double) throws -> PersistentMealLog {
        PersistentMealLog(domain: try MealLog(title: title, entryMethod: .weighed, coverageStatus: .complete,
            components: [MealComponent(foodItem: food, consumedWeightGrams: weight)]))
    }

    private func readFood(in c: ModelContainer, id: UUID) throws -> FoodItem {
        let row = try #require(ModelContext(c).fetch(FetchDescriptor<PersistentFoodItem>(predicate: #Predicate { $0.id == id })).first)
        return try row.domainModel
    }

    private func snapshot(in c: ModelContainer, id: UUID) throws -> MealEditSnapshot {
        let row = try #require(ModelContext(c).fetch(FetchDescriptor<PersistentMealLog>(predicate: #Predicate { $0.id == id })).first)
        return MealEditSnapshot(row)
    }
}
