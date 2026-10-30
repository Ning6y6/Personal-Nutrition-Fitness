import FoodDecisionCore
import Foundation
import SwiftData
import Testing
@testable import FoodDecisionAssistant

@MainActor
struct PersonalFoodDeleteCommandTests {
    @Test("Deleting one card preserves the entire catalog, all other records and exact historical snapshots",
          arguments: [false, true])
    func onlyTheSelectedPersonalCardIsRemoved(disk: Bool) throws {
        let url = try disk ? temporaryDirectory().appendingPathComponent("preservation.store") : nil
        let c = try container(url: url)
        _ = try FoodCatalogImportCommand.importIfNeeded(into: c)
        _ = try SeedFoodCatalog.importIfNeeded(into: c.mainContext)
        let target = try food()
        let other = try food(fibre: 0)
        let unknown = try FoodItem(name: "unmarked synthetic food", category: .mixedMeal,
            nutrientsPer100Units: .zero, source: "legacy unmarked source")
        for value in [target, other, unknown] { c.mainContext.insert(PersistentFoodItem(domain: value)) }
        let oldMeal = try meal(food: target)
        c.mainContext.insert(oldMeal)
        let oldTemplate = try template(food: target)
        c.mainContext.insert(oldTemplate)
        let day = try GoalDay(key: 20261030)
        let profile = try GoalProfile(effectiveFrom: day.start(in: "Europe/London"), energyKcal: 2000,
            proteinGrams: 100, carbohydrateGrams: 200, fatGrams: 60, fibreGrams: nil)
        c.mainContext.insert(PersistentGoalProfile(domain: profile))
        c.mainContext.insert(PersistentGoalVersion(domain: try GoalVersion(profile: profile,
            effectiveDay: day, source: .selfSelected, confirmedAt: day.start(in: "Europe/London"),
            timeZoneIdentifier: "Europe/London", commitSequence: 1)))
        try c.mainContext.save()
        let snapshot = MealEditSnapshot(oldMeal)
        let templateBefore = try oldTemplate.domainModel()
        let before = try LocalStoreBackupService.records(from: c)
        let officialIDs = Set(try FoodCatalog.bundled().entries.map { $0.food.id })
        #expect(officialIDs.count == 357)
        var saveCalls = 0
        let request = PersonalFoodDeleteRequest(originalFood: target)
        try PersonalFoodDeleteCommand.delete(request: request, container: c, saveContext: { context in
            saveCalls += 1
            #expect(context !== c.mainContext)
            #expect(context.autosaveEnabled == false)
            try context.save()
        })
        try PersonalFoodDeleteCommand.delete(request: request, container: c, saveContext: { _ in saveCalls += 1 })
        #expect(saveCalls == 1)
        #expect(try LocalStoreBackupService.records(from: c) == withoutFood(target.id, in: before))
        #expect(try snapshotIn(c, id: oldMeal.id) == snapshot)
        #expect(try oldTemplate.domainModel() == templateBefore)
        let remaining = try ModelContext(c).fetch(FetchDescriptor<PersistentFoodItem>()).map { $0.id }
        #expect(officialIDs.isSubset(of: Set(remaining)))
        #expect(remaining.contains(target.id) == false)
        #expect(c.mainContext.hasChanges == false)
    }

    @Test("All current, legacy and retired built-in IDs remain protected even with forged personal markers")
    func reservedIDsCannotBeDeleted() throws {
        let c = try container()
        let catalog = try FoodCatalog.bundled().entries.map(\.food)
        let seeds = try SeedFoodCatalog.loadFoods()
        let retired = try #require(UUID(uuidString: "20000000-0000-4000-8000-000000018521"))
        var byID: [UUID: FoodItem] = [:]
        for value in catalog + seeds { byID[value.id] = value }
        byID[retired] = try food(id: retired)
        for value in byID.values { c.mainContext.insert(PersistentFoodItem(domain: value)) }
        try c.mainContext.save()
        let before = try LocalStoreBackupService.records(from: c)
        let identity = try PersonalFoodIdentity()
        for id in byID.keys {
            #expect(throws: PersonalFoodDeleteCommandError.reservedFoodID) {
                try PersonalFoodDeleteCommand.delete(request: PersonalFoodDeleteRequest(originalFood: food(id: id)),
                    container: c, identity: identity)
            }
        }
        #expect(try LocalStoreBackupService.records(from: c) == before)
    }

    @Test("Unmarked, mismatched, unsupported or corrupt cards fail closed before deleting anything",
          arguments: ["requestUnmarked", "requestWrongID", "requestML", "rowUnmarked", "rowWrongID", "rowInvalid"])
    func invalidPersonalIdentityIsProtected(kind: String) throws {
        let c = try container()
        let target = try food()
        let row = PersistentFoodItem(domain: target)
        var original = target
        switch kind {
        case "requestUnmarked": original = try replacing(target, source: "old unknown source")
        case "requestWrongID": original = try replacing(target, source: PersonalFoodSource.encode(foodID: UUID(), note: "wrong"))
        case "requestML": original = try replacing(target, unit: "ml")
        case "rowUnmarked": row.source = "old unknown source"
        case "rowWrongID": row.source = try PersonalFoodSource.encode(foodID: UUID(), note: "wrong")
        case "rowInvalid": row.energyKcalPer100Units = -1
        default: Issue.record("Unexpected fixture")
        }
        c.mainContext.insert(row)
        try c.mainContext.save()
        let before = try LocalStoreBackupService.records(from: c)
        #expect(throws: PersonalFoodDeleteCommandError.invalidPersonalFood) {
            try PersonalFoodDeleteCommand.delete(request: PersonalFoodDeleteRequest(originalFood: original), container: c)
        }
        #expect(try LocalStoreBackupService.records(from: c) == before)
    }

    @Test("A changed saved baseline is never deleted, including missing-versus-zero fibre and source changes",
          arguments: ["name", "category", "nutrition", "fibre", "source", "salt"])
    func staleBaselineIsProtected(field: String) throws {
        let c = try container()
        let original = try food()
        let row = PersistentFoodItem(domain: original)
        switch field {
        case "name": row.name = "changed saved name"
        case "category": row.categoryRawValue = FoodCategory.sauce.rawValue
        case "nutrition": row.proteinGramsPer100Units = 36
        case "fibre": row.fibreGramsPer100Units = 0
        case "source": row.source = try PersonalFoodSource.encode(foodID: original.id, note: "changed source")
        case "salt": row.saltGramsPer100Units = 0.75
        default: Issue.record("Unexpected fixture")
        }
        c.mainContext.insert(row)
        try c.mainContext.save()
        let before = try LocalStoreBackupService.records(from: c)
        #expect(throws: PersonalFoodDeleteCommandError.baselineChanged) {
            try PersonalFoodDeleteCommand.delete(request: PersonalFoodDeleteRequest(originalFood: original), container: c)
        }
        #expect(try LocalStoreBackupService.records(from: c) == before)
    }

    @Test("Pending same-ID insertion, editing or deletion is neither committed nor discarded",
          arguments: ["insert", "edit", "delete"])
    func relatedMainContextDraftIsProtected(state: String) throws {
        let c = try container()
        let original = try food()
        let row = PersistentFoodItem(domain: original)
        c.mainContext.insert(row)
        if state != "insert" { try c.mainContext.save() }
        let before = try LocalStoreBackupService.records(from: c)
        if state == "edit" { row.name = "unsaved card name" }
        if state == "delete" { c.mainContext.delete(row) }
        #expect(throws: PersonalFoodDeleteCommandError.sharedFoodHasUnsavedChanges) {
            try PersonalFoodDeleteCommand.delete(request: PersonalFoodDeleteRequest(originalFood: original), container: c)
        }
        #expect(c.mainContext.hasChanges)
        #expect(try LocalStoreBackupService.records(from: c) == before)
        if state == "edit" { #expect(row.name == "unsaved card name") }
        c.mainContext.rollback()
        #expect(try LocalStoreBackupService.records(from: c) == before)
    }

    @Test("Successful or failed deletion preserves unrelated insertions, edits, deletions and parent drafts",
          arguments: [false, true])
    func unrelatedMainContextWorkIsPreserved(fail: Bool) throws {
        let c = try container()
        let target = try food()
        let changed = PersistentFoodItem(domain: try food())
        let removed = PersistentFoodItem(domain: try food())
        for row in [PersistentFoodItem(domain: target), changed, removed] { c.mainContext.insert(row) }
        try c.mainContext.save()
        let before = try LocalStoreBackupService.records(from: c)
        changed.name = "unsaved unrelated change"
        c.mainContext.delete(removed)
        let inserted = PersistentFoodItem(domain: try food())
        c.mainContext.insert(inserted)
        c.mainContext.insert(try meal(food: target))
        c.mainContext.insert(try template(food: target))
        c.mainContext.insert(PersistentGoalProfile(domain: try GoalProfile(energyKcal: 2100,
            proteinGrams: 100, carbohydrateGrams: 200, fatGrams: 60)))
        var attempted: ModelContext?
        let request = PersonalFoodDeleteRequest(originalFood: target)
        if fail {
            #expect(throws: PersonalFoodDeleteCommandError.saveFailed) {
                try PersonalFoodDeleteCommand.delete(request: request, container: c, saveContext: { context in
                    attempted = context
                    throw Injected.beforeCommit
                })
            }
            #expect(attempted?.hasChanges == false)
            try attempted?.save()
        } else {
            try PersonalFoodDeleteCommand.delete(request: request, container: c)
        }
        #expect(c.mainContext.hasChanges)
        #expect(changed.name == "unsaved unrelated change")
        #expect(c.mainContext.insertedModelsArray.contains { ($0 as? PersistentFoodItem)?.id == inserted.id })
        #expect(c.mainContext.deletedModelsArray.contains { ($0 as? PersistentFoodItem)?.id == removed.id })
        let expected = fail ? before : withoutFood(target.id, in: before)
        #expect(try LocalStoreBackupService.records(from: c) == expected)
        c.mainContext.rollback()
        #expect(try LocalStoreBackupService.records(from: c) == expected)
        if fail {
            try PersonalFoodDeleteCommand.delete(request: request, container: c)
            #expect(try LocalStoreBackupService.records(from: c) == withoutFood(target.id, in: before))
        }
    }

    @Test("A save callback that commits then throws is safely retried without another write",
          arguments: [false, true])
    func ambiguousCommitIsIdempotent(disk: Bool) throws {
        let url = try disk ? temporaryDirectory().appendingPathComponent("ambiguous.store") : nil
        let c = try container(url: url)
        let target = try food()
        c.mainContext.insert(PersistentFoodItem(domain: target))
        try c.mainContext.save()
        let request = PersonalFoodDeleteRequest(originalFood: target)
        var writes = 0
        #expect(throws: PersonalFoodDeleteCommandError.saveFailed) {
            try PersonalFoodDeleteCommand.delete(request: request, container: c, saveContext: { context in
                writes += 1
                try context.save()
                throw Injected.afterCommit
            })
        }
        #expect(try foods(in: c).isEmpty)
        try PersonalFoodDeleteCommand.delete(request: request, container: c, saveContext: { _ in writes += 1 })
        #expect(writes == 1)
        #expect(try foods(in: c).isEmpty)
        #expect(c.mainContext.hasChanges == false)
    }

    @Test("Committed refresh failure preserves drafts and verification never deletes a restored same-ID card",
          arguments: [false, true])
    func committedDeletionCanOnlyBeVerifiedAfterRefreshFailure(disk: Bool) throws {
        let url = try disk ? temporaryDirectory().appendingPathComponent("refresh.store") : nil
        let c = try container(url: url)
        let target = try food()
        c.mainContext.insert(PersistentFoodItem(domain: target))
        try c.mainContext.save()
        c.mainContext.insert(try meal(food: target))
        let request = PersonalFoodDeleteRequest(originalFood: target)
        #expect(throws: PersonalFoodDeleteCommandError.deletedButRefreshFailed) {
            try PersonalFoodDeleteCommand.delete(request: request, container: c, refreshContext: { _, _ in
                throw Injected.refresh
            })
        }
        #expect(try foods(in: c).isEmpty)
        #expect(c.mainContext.hasChanges)
        var writes = 0
        try PersonalFoodDeleteCommand.delete(request: request, container: c, verifyOnly: true,
            saveContext: { _ in writes += 1 })
        #expect(writes == 0)
        let restored = ModelContext(c)
        restored.autosaveEnabled = false
        restored.insert(PersistentFoodItem(domain: target))
        try restored.save()
        #expect(throws: PersonalFoodDeleteCommandError.baselineChanged) {
            try PersonalFoodDeleteCommand.delete(request: request, container: c, verifyOnly: true)
        }
        #expect(try foods(in: c) == [target])
        #expect(c.mainContext.hasChanges)
        c.mainContext.rollback()
        #expect(try foods(in: c) == [target])
    }

    @Test("A held main-context card disappears from selectors without committing an unrelated meal draft",
          arguments: [false, true])
    func mainContextQueriesObserveDeletion(disk: Bool) throws {
        let url = try disk ? temporaryDirectory().appendingPathComponent("visibility.store") : nil
        let c = try container(url: url)
        let target = try food()
        c.mainContext.insert(PersistentFoodItem(domain: target))
        try c.mainContext.save()
        let held = try #require(c.mainContext.fetch(FetchDescriptor<PersistentFoodItem>()).first)
        let heldID = held.id
        c.mainContext.insert(try meal(food: target))
        try PersonalFoodDeleteCommand.delete(request: PersonalFoodDeleteRequest(originalFood: target), container: c)
        // The row was registered before the private deletion. Reusing the shared
        // selector query must not return that cached card as a current food.
        #expect(heldID == target.id)
        #expect(try c.mainContext.fetch(FetchDescriptor<PersistentFoodItem>()).isEmpty)
        #expect(c.mainContext.hasChanges)
        #expect(try ModelContext(c).fetchCount(FetchDescriptor<PersistentMealLog>()) == 0)
        c.mainContext.rollback()
        #expect(try c.mainContext.fetch(FetchDescriptor<PersistentFoodItem>()).isEmpty)
    }

    @Test("V2 reopen and backup 2 restore preserve absent food references; old meals still scale from their snapshots")
    func deletedCardHistoryAndBackupRoundTrip() throws {
        let directory = try temporaryDirectory()
        let url = directory.appendingPathComponent("history.store")
        let target = try food()
        let baseline = try autoreleasepool { () throws -> (UUID, UUID, MealEditSnapshot, MealTemplate) in
            let c = try container(url: url)
            c.mainContext.insert(PersistentFoodItem(domain: target))
            let savedMeal = try meal(food: target)
            let savedTemplate = try template(food: target)
            c.mainContext.insert(savedMeal)
            c.mainContext.insert(savedTemplate)
            try c.mainContext.save()
            let snapshot = MealEditSnapshot(savedMeal)
            let template = try savedTemplate.domainModel()
            try PersonalFoodDeleteCommand.delete(request: PersonalFoodDeleteRequest(originalFood: target), container: c)
            #expect(try snapshotIn(c, id: savedMeal.id) == snapshot)
            return (savedMeal.id, savedTemplate.id, snapshot, template)
        }
        let archive = try autoreleasepool { () throws -> Data in
            let reopened = try container(url: url)
            #expect(try foods(in: reopened).isEmpty)
            #expect(try snapshotIn(reopened, id: baseline.0) == baseline.2)
            let old = try #require(baseline.2.originalComponents().first)
            let scaled = try MealComponentEditPolicy.resolve(original: old, id: old.id,
                foodItemID: old.foodItemID, weightGrams: 40, currentFood: nil)
            #expect(abs(scaled.nutrients.energyKcal - 160) < 1e-10)
            #expect(scaled.nutrients.fibreGrams == nil)
            let renamed = try MealEditCommand.save(baseline: baseline.2,
                changes: MealEditChanges(title: "renamed after source deletion"), in: reopened)
            #expect(renamed.nutrition == baseline.2.nutrition)
            let updated = try MealEditCommand.save(baseline: renamed,
                changes: MealEditChanges(components: [scaled]), in: reopened)
            #expect(abs(updated.nutrition.energyKcal - 160) < 1e-10)
            #expect(updated.components.first?.foodItemID == target.id)
            let template = try #require(ModelContext(reopened).fetch(FetchDescriptor<PersistentMealTemplate>()).first)
            #expect(try template.domainModel() == baseline.3)
            let recentMeal = try #require(ModelContext(reopened).fetch(FetchDescriptor<PersistentMealLog>()).first)
            let recent = try #require(RecentMealSelector.select(from: [recentMeal.domainModel()]).first)
            for draft in [MealEntryDraft(reusing: recent), MealEntryDraft(template: baseline.3)] {
                #expect(draft.components.count == 1)
                #expect(draft.components.first?.foodItemID == target.id)
                #expect(draft.components.first?.foodName == target.name)
                #expect(throws: MealDraftValidationError.unavailableFood) {
                    try MealDraftValidation.components(from: draft.components, foods: [])
                }
            }
            return try LocalStoreBackupService.export(from: reopened)
        }
        let document = try LocalStoreBackupCodec.decode(archive)
        #expect(document.formatVersion == 2)
        #expect(document.schemaVersion == "2.0.0")
        let restoredURL = try LocalStoreBackupService.stageRestore(data: archive,
            directory: directory.appendingPathComponent("restore"))
        try autoreleasepool {
            let restored = try container(url: restoredURL)
            #expect(try LocalStoreBackupService.records(from: restored) == document.canonicalRecords)
            #expect(try foods(in: restored).isEmpty)
            #expect(abs(try snapshotIn(restored, id: baseline.0).nutrition.energyKcal - 160) < 1e-10)
            let template = try #require(ModelContext(restored).fetch(FetchDescriptor<PersistentMealTemplate>()).first)
            #expect(try template.domainModel() == baseline.3)
        }
    }

    @Test("A real read-only file store rejects deletion, preserves records and permits a later writable retry")
    func actualReadOnlyStoreFailureAndRetry() throws {
        let directory = try temporaryDirectory()
        let url = directory.appendingPathComponent("read-only.store")
        let target = try food()
        let before = try autoreleasepool { () throws -> [LocalStoreBackupRecord] in
            let c = try container(url: url)
            c.mainContext.insert(PersistentFoodItem(domain: target))
            c.mainContext.insert(try meal(food: target))
            c.mainContext.insert(try template(food: target))
            try c.mainContext.save()
            return try LocalStoreBackupService.records(from: c)
        }
        let request = PersonalFoodDeleteRequest(originalFood: target)
        try autoreleasepool {
            let readOnly = try container(url: url, allowsSave: false)
            readOnly.mainContext.insert(try meal(food: target))
            #expect(throws: PersonalFoodDeleteCommandError.saveFailed) {
                try PersonalFoodDeleteCommand.delete(request: request, container: readOnly)
            }
            #expect(readOnly.mainContext.hasChanges)
            #expect(try LocalStoreBackupService.records(from: readOnly) == before)
        }
        try autoreleasepool {
            let writable = try container(url: url)
            #expect(try LocalStoreBackupService.records(from: writable) == before)
            try PersonalFoodDeleteCommand.delete(request: request, container: writable)
            #expect(try LocalStoreBackupService.records(from: writable) == withoutFood(target.id, in: before))
        }
        try autoreleasepool {
            let reopened = try container(url: url)
            #expect(try LocalStoreBackupService.records(from: reopened) == withoutFood(target.id, in: before))
        }
    }

    private enum Injected: Error { case beforeCommit, afterCommit, refresh }

    private func container(url: URL? = nil, allowsSave: Bool = true) throws -> ModelContainer {
        let schema = Schema(versionedSchema: VersionedSchemaV2.self)
        let configuration = url.map { ModelConfiguration(schema: schema, url: $0,
            allowsSave: allowsSave, cloudKitDatabase: .none) }
            ?? ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let c = try ModelContainer(for: schema, migrationPlan: ShiHengMigrationPlan.self, configurations: configuration)
        c.mainContext.autosaveEnabled = false
        return c
    }

    private func temporaryDirectory() throws -> URL {
        // Synthetic SQLite artifacts remain in the test sandbox until its App
        // lifecycle reclaims them; SwiftData may close stores asynchronously.
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("personal-food-delete-synthetic-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func food(id: UUID = UUID(), fibre: Double? = nil) throws -> FoodItem {
        try FoodItem(id: id, name: "synthetic personal food", category: .snackDessert,
            nutrientsPer100Units: NutrientValues(energyKcal: 400, fatGrams: 8, saturatedFatGrams: 2,
                carbohydrateGrams: 40, sugarGrams: 3, proteinGrams: 35, saltGrams: 0, fibreGrams: fibre),
            source: PersonalFoodSource.encode(foodID: id, note: "synthetic label"))
    }

    private func replacing(_ value: FoodItem, unit: String? = nil, source: String? = nil) throws -> FoodItem {
        try FoodItem(id: value.id, name: value.name, category: value.category,
            nutrientsPer100Units: value.nutrientsPer100Units, unit: unit ?? value.unit, source: source ?? value.source)
    }

    private func foods(in c: ModelContainer) throws -> [FoodItem] {
        try ModelContext(c).fetch(FetchDescriptor<PersistentFoodItem>()).map { try $0.domainModel }
    }

    private func withoutFood(_ id: UUID, in records: [LocalStoreBackupRecord]) -> [LocalStoreBackupRecord] {
        records.filter { $0.entity != .foodItem || $0.id != id }
    }

    private func meal(food: FoodItem) throws -> PersistentMealLog {
        PersistentMealLog(domain: try MealLog(title: "synthetic historical meal", entryMethod: .weighed,
            coverageStatus: .complete, components: [MealComponent(foodItem: food, consumedWeightGrams: 30)]))
    }

    private func template(food: FoodItem) throws -> PersistentMealTemplate {
        PersistentMealTemplate(domain: try MealTemplate(name: "synthetic retained template", useCount: 3,
            components: [MealTemplateComponent(foodItemID: food.id, foodName: food.name, defaultWeightGrams: 30)]))
    }

    private func snapshotIn(_ c: ModelContainer, id: UUID) throws -> MealEditSnapshot {
        let row = try #require(ModelContext(c).fetch(FetchDescriptor<PersistentMealLog>(predicate: #Predicate { $0.id == id })).first)
        return MealEditSnapshot(row)
    }
}
