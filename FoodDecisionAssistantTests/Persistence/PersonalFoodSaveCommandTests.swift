import FoodDecisionCore
import Foundation
import SwiftData
import Testing
@testable import FoodDecisionAssistant

@MainActor
struct PersonalFoodSaveCommandTests {
    @Test("Only this version's complete g cards are editable; the entire bundled and seed ID sets stay protected")
    func identityDoesNotClaimOfficialOrUnknownFoods() throws {
        let identity = try PersonalFoodIdentity()
        let card = try food()
        #expect(identity.isEditable(card))
        #expect(identity.verifiedSource(for: card)?.note == "synthetic label")
        let retired = try #require(UUID(uuidString: "20000000-0000-4000-8000-000000018521"))
        let protected = try FoodCatalog.bundled().entries.map(\.food) + SeedFoodCatalog.loadFoods()
        for official in protected {
            let forged = try food(id: official.id)
            #expect(identity.isReserved(official.id))
            #expect(identity.isEditable(official) == false)
            #expect(identity.isEditable(forged) == false)
        }
        #expect(identity.isEditable(try food(id: retired)) == false)
        for source in ["unknown old local record", "CoFID 2021", "evenfare.personal-food:",
                       "evenfare.personal-food:damaged", try PersonalFoodSource.encode(foodID: UUID(), note: "wrong ID")] {
            #expect(identity.isEditable(try replacing(card, source: source)) == false)
        }
        #expect(identity.isEditable(try replacing(card, unit: "ml")) == false)
        #expect(identity.isEditable(try replacing(card, name: "  noncanonical external name  ")) == false)
    }

    @Test("A catalog read failure blocks identity loading instead of removing reserved-ID protection")
    func catalogLoadFailureIsFailClosed() throws {
        #expect(throws: PersonalFoodIdentityError.catalogUnavailable) {
            try PersonalFoodIdentity(catalogLoader: { throw Injected.readFailure })
        }
    }

    @Test("Create and edit retries commit once and conflicting operations never upsert an existing card")
    func duplicateOperationsAreIdempotentAndConflictsProtectData() throws {
        let c = try container()
        let original = try food()
        var saveCalls = 0
        let create = PersonalFoodSaveRequest(food: original, intent: .create)
        #expect(try PersonalFoodSaveCommand.save(request: create, container: c) { context in
            saveCalls += 1; try context.save()
        } == original)
        #expect(try PersonalFoodSaveCommand.save(request: create, container: c) { _ in saveCalls += 1 } == original)
        #expect(saveCalls == 1)
        #expect(try readFood(in: c, id: original.id) == original)
        #expect(try ModelContext(c).fetchCount(FetchDescriptor<PersistentMealLog>()) == 0)
        let updated = try food(id: original.id, energy: 450, name: "changed synthetic card", fibre: 0)
        #expect(throws: PersonalFoodSaveCommandError.idConflict) {
            try PersonalFoodSaveCommand.save(request: PersonalFoodSaveRequest(food: updated, intent: .create), container: c)
        }
        let edit = PersonalFoodSaveRequest(food: updated, intent: .edit(original: original))
        #expect(try PersonalFoodSaveCommand.save(request: edit, container: c) { context in
            saveCalls += 1; try context.save()
        } == updated)
        #expect(try PersonalFoodSaveCommand.save(request: edit, container: c) { _ in saveCalls += 1 } == updated)
        #expect(saveCalls == 2)
        let stale = PersonalFoodSaveRequest(food: try food(id: original.id, energy: 500), intent: .edit(original: original))
        #expect(throws: PersonalFoodSaveCommandError.baselineChanged) {
            try PersonalFoodSaveCommand.save(request: stale, container: c)
        }
        #expect(try readFood(in: c, id: original.id) == updated)
        #expect(try ModelContext(c).fetchCount(FetchDescriptor<PersistentFoodItem>()) == 1)
    }

    @Test("Official IDs, unknown local rows and changing an edit's identity cannot be overwritten")
    func nonpersonalRowsAreReadOnly() throws {
        let c = try container()
        let official = try #require(SeedFoodCatalog.loadFoods().first)
        let unknown = try replacing(food(), source: "unmarked old food")
        for row in [official, unknown] { c.mainContext.insert(PersistentFoodItem(domain: row)) }
        try c.mainContext.save()
        let before = try LocalStoreBackupService.records(from: c)
        #expect(throws: PersonalFoodSaveCommandError.reservedFoodID) {
            try PersonalFoodSaveCommand.save(request: PersonalFoodSaveRequest(food: food(id: official.id), intent: .create), container: c)
        }
        #expect(throws: PersonalFoodSaveCommandError.invalidPersonalFood) {
            try PersonalFoodSaveCommand.save(request: PersonalFoodSaveRequest(food: food(id: unknown.id), intent: .create), container: c)
        }
        #expect(throws: PersonalFoodSaveCommandError.invalidPersonalFood) {
            try PersonalFoodSaveCommand.save(request: PersonalFoodSaveRequest(food: food(id: unknown.id), intent: .edit(original: unknown)), container: c)
        }
        let real = try food()
        _ = try PersonalFoodSaveCommand.save(request: PersonalFoodSaveRequest(food: real, intent: .create), container: c)
        #expect(throws: PersonalFoodSaveCommandError.idConflict) {
            try PersonalFoodSaveCommand.save(request: PersonalFoodSaveRequest(food: food(), intent: .edit(original: real)), container: c)
        }
        #expect(try LocalStoreBackupService.records(from: c).filter { $0.id != real.id } == before)
    }

    @Test("A successful card save neither commits nor rolls back unsaved meal, template, goal or unrelated food drafts")
    func parentDraftsSurviveSuccessfulSave() throws {
        let c = try container()
        let original = try food()
        let shared = c.mainContext
        let draftFood = try food()
        shared.insert(PersistentFoodItem(domain: draftFood))
        shared.insert(try meal(food: original))
        shared.insert(PersistentMealTemplate(domain: try MealTemplate(name: "unsaved template", components: [
            MealTemplateComponent(foodItemID: original.id, foodName: original.name, defaultWeightGrams: 30),
        ])))
        shared.insert(PersistentGoalProfile(domain: try GoalProfile(energyKcal: 2000,
            proteinGrams: 100, carbohydrateGrams: 200, fatGrams: 50)))
        _ = try PersonalFoodSaveCommand.save(request: PersonalFoodSaveRequest(food: original, intent: .create), container: c)
        #expect(shared.hasChanges)
        let records = try LocalStoreBackupService.records(from: c)
        #expect(records.count == 1)
        #expect(records.first?.entity == .foodItem)
        #expect(records.first?.id == original.id)
        shared.rollback()
        #expect(try LocalStoreBackupService.records(from: c) == records)
        #expect(try readFood(in: c, id: original.id) == original)
    }

    @Test("Save failure rolls back only the private context and retry uses the supplied current values")
    func failedSavePreservesDraftAndCannotLeakIntoLaterSaves() throws {
        let c = try container()
        let original = try food()
        _ = try PersonalFoodSaveCommand.save(request: PersonalFoodSaveRequest(food: original, intent: .create), container: c)
        let before = try LocalStoreBackupService.records(from: c)
        c.mainContext.insert(try meal(food: original))
        let failedTarget = try food(id: original.id, energy: 450)
        var attempted: ModelContext?
        #expect(throws: PersonalFoodSaveCommandError.saveFailed) {
            try PersonalFoodSaveCommand.save(request: PersonalFoodSaveRequest(food: failedTarget, intent: .edit(original: original)), container: c) { context in
                attempted = context
                #expect(context !== c.mainContext)
                #expect(context.autosaveEnabled == false)
                throw Injected.beforeCommit
            }
        }
        #expect(c.mainContext.hasChanges)
        #expect(attempted?.hasChanges == false)
        #expect(try LocalStoreBackupService.records(from: c) == before)
        try attempted?.save()
        #expect(try LocalStoreBackupService.records(from: c) == before)
        let corrected = try food(id: original.id, energy: 500, name: "current retry value")
        _ = try PersonalFoodSaveCommand.save(request: PersonalFoodSaveRequest(food: corrected, intent: .edit(original: original)), container: c)
        #expect(try readFood(in: c, id: original.id) == corrected)
        #expect(c.mainContext.hasChanges)
        #expect(try ModelContext(c).fetchCount(FetchDescriptor<PersistentMealLog>()) == 0)
        try c.mainContext.save()
        #expect(try readFood(in: c, id: original.id) == corrected)
        #expect(try ModelContext(c).fetchCount(FetchDescriptor<PersistentMealLog>()) == 1)
    }

    @Test("A pending same-ID insertion, edit or deletion is rejected without saving or discarding it", arguments: ["insert", "edit", "delete"])
    func pendingSameFoodIsProtected(state: String) throws {
        let c = try container()
        let original = try food()
        let row = PersistentFoodItem(domain: original)
        c.mainContext.insert(row)
        if state != "insert" { try c.mainContext.save() }
        let before = try LocalStoreBackupService.records(from: c)
        if state == "edit" { row.name = "unsaved raw name" }
        if state == "delete" { c.mainContext.delete(row) }
        #expect(throws: PersonalFoodSaveCommandError.sharedFoodHasUnsavedChanges) {
            try PersonalFoodSaveCommand.save(request: PersonalFoodSaveRequest(food: original, intent: .create), container: c)
        }
        #expect(c.mainContext.hasChanges)
        #expect(try LocalStoreBackupService.records(from: c) == before)
        if state == "edit" { #expect(row.name == "unsaved raw name") }
        c.mainContext.rollback()
        #expect(try LocalStoreBackupService.records(from: c) == before)
    }

    @Test("An already-read main-context card reflects a private edit while an unrelated parent draft stays unsaved", arguments: [false, true])
    func heldMainContextFoodReflectsCommittedEdit(disk: Bool) throws {
        let url = try disk ? temporaryDirectory().appendingPathComponent("visibility.store") : nil
        let c = try container(url: url)
        let original = try food()
        _ = try PersonalFoodSaveCommand.save(request: PersonalFoodSaveRequest(food: original, intent: .create), container: c)
        let id = original.id
        let held = try #require(c.mainContext.fetch(FetchDescriptor<PersistentFoodItem>(predicate: #Predicate { $0.id == id })).first)
        try #require(held.energyKcalPer100Units == 400)
        let draftMeal = try meal(food: original)
        c.mainContext.insert(draftMeal)
        let target = try food(id: id, energy: 450, name: "updated held card", fibre: 0)
        _ = try PersonalFoodSaveCommand.save(request: PersonalFoodSaveRequest(food: target, intent: .edit(original: original)), container: c)
        // Access the object fetched before the private save before any further
        // fetch/relationship access could conceal a stale main-context cache.
        #expect(held.energyKcalPer100Units == 450)
        #expect(held.name == target.name)
        #expect(try held.domainModel == target)
        #expect(try MealComponent(foodItem: held.domainModel, consumedWeightGrams: 30).nutrients.energyKcal == 135)
        #expect(c.mainContext.hasChanges)
        #expect(try ModelContext(c).fetchCount(FetchDescriptor<PersistentMealLog>()) == 0)
        c.mainContext.rollback()
        #expect(try readFood(in: c, id: id) == target)
    }

    private enum Injected: Error { case beforeCommit, readFailure }

    private func container(url: URL? = nil) throws -> ModelContainer {
        let schema = Schema(versionedSchema: VersionedSchemaV2.self)
        let configuration = url.map { ModelConfiguration(schema: schema, url: $0, cloudKitDatabase: .none) }
            ?? ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let c = try ModelContainer(for: schema, migrationPlan: ShiHengMigrationPlan.self, configurations: configuration)
        c.mainContext.autosaveEnabled = false
        return c
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("personal-food-synthetic-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func food(id: UUID = UUID(), energy: Double = 400, name: String = "synthetic personal food", fibre: Double? = nil) throws -> FoodItem {
        try FoodItem(id: id, name: name, category: .snackDessert,
            nutrientsPer100Units: NutrientValues(energyKcal: energy, fatGrams: 8, saturatedFatGrams: 2,
                carbohydrateGrams: 40, sugarGrams: 3, proteinGrams: 35, saltGrams: 0, fibreGrams: fibre),
            source: PersonalFoodSource.encode(foodID: id, note: "synthetic label"))
    }

    private func replacing(_ food: FoodItem, name: String? = nil, unit: String? = nil, source: String? = nil) throws -> FoodItem {
        try FoodItem(id: food.id, name: name ?? food.name, category: food.category,
            nutrientsPer100Units: food.nutrientsPer100Units, unit: unit ?? food.unit, source: source ?? food.source)
    }

    private func readFood(in c: ModelContainer, id: UUID) throws -> FoodItem {
        let row = try #require(ModelContext(c).fetch(FetchDescriptor<PersistentFoodItem>(predicate: #Predicate { $0.id == id })).first)
        return try row.domainModel
    }

    private func meal(food: FoodItem) throws -> PersistentMealLog {
        PersistentMealLog(domain: try MealLog(title: "synthetic parent meal", entryMethod: .weighed,
            coverageStatus: .complete, components: [MealComponent(foodItem: food, consumedWeightGrams: 30)]))
    }
}
