import FoodDecisionCore
import Foundation
import SwiftData
import Testing
@testable import FoodDecisionAssistant

@MainActor
struct MealEditCommandTests {
    @Test("Metadata edits preserve archived totals, grades, IDs, order and missing source foods on disk")
    func metadataPreservesRawSnapshotsAndRestore() throws {
        let directory = try temporaryDirectory()
        // SwiftData may retain SQLite handles after a container leaves scope. This
        // synthetic App-tmp directory is reclaimed with the QA App lifecycle.
        let url = directory.appendingPathComponent("test.store")
        let saved = try autoreleasepool {
            let c = try container(url: url)
            let row = try seed(c)
            row.consumedWeightGrams = 987
            row.energyKcal = 654
            row.estimateEvidenceGradeRawValue = "c"
            row.healthKitSyncVersion = 7
            row.components[0].sortIndex = -4
            row.components[1].sortIndex = 19
            try c.mainContext.save()
            let before = MealEditSnapshot(row)
            let date = row.eatenAt.addingTimeInterval(600)
            let result = try MealEditCommand.save(baseline: before,
                changes: MealEditChanges(title: "  synthetic changed  ", eatenAt: date), in: c)
            var expected = before; expected.title = "synthetic changed"; expected.eatenAt = date
            #expect(result == expected)
            #expect(try snapshot(in: c, id: row.id) == expected)
            #expect(try ModelContext(c).fetchCount(FetchDescriptor<PersistentFoodItem>()) == 0)
            return result
        }
        try autoreleasepool {
            let reopened = try container(url: url)
            #expect(try snapshot(in: reopened, id: saved.id) == saved)
            let archive = try LocalStoreBackupService.export(from: reopened)
            let restoredURL = try LocalStoreBackupService.stageRestore(data: archive,
                directory: directory.appendingPathComponent("restore"))
            let restored = try LocalStoreBackupRestoration.container(at: restoredURL)
            #expect(try snapshot(in: restored, id: saved.id) == saved)
            #expect(try LocalStoreBackupService.records(from: restored)
                == LocalStoreBackupCodec.decode(archive).canonicalRecords)
        }
    }

    @Test("Unknown and invalid raw fields remain unchanged during title or time edits", arguments: [false, true])
    func legacyMetadataDoesNotRepair(emptyComponents: Bool) throws {
        let c = try container(); let row = try seed(c)
        row.title = " "
        row.entryMethodRawValue = "future_method"
        row.coverageStatusRawValue = "future_coverage"
        row.estimateEvidenceGradeRawValue = "future_grade"
        row.healthKitSyncVersion = 0
        row.consumedWeightGrams = -7
        row.saltGrams = -2
        row.components[0].unit = "ml"
        if emptyComponents {
            for child in row.components { c.mainContext.delete(child) }
            row.components = []
        }
        try c.mainContext.save()
        let before = MealEditSnapshot(row)
        let date = row.eatenAt.addingTimeInterval(60)
        let saved = try MealEditCommand.save(baseline: before, changes: MealEditChanges(eatenAt: date), in: c)
        var expected = before; expected.eatenAt = date
        #expect(saved == expected)
        #expect(try snapshot(in: c, id: row.id) == expected)
        #expect(throws: MealEditCommandError.invalidChanges) {
            try MealEditCommand.save(baseline: saved, changes: MealEditChanges(title: " \n "), in: c)
        }
        #expect(try snapshot(in: c, id: row.id) == expected)
    }

    @Test("Raw snapshot equality distinguishes NaN payloads, signed zero and optional unknown values")
    func rawEqualityUsesBitPatterns() throws {
        let c = try container(); let row = try seed(c)
        try #require(row.components.count == 2)
        try #require(Set(row.components.map(\.id)).count == 2)
        row.energyKcal = Double(bitPattern: 0x7ff8_0000_0000_0001)
        let invalidChild = try #require(row.components.first)
        let invalidChildID = invalidChild.id
        invalidChild.consumedWeightGrams = Double(bitPattern: 0x7ff8_0000_0000_0002)
        row.fibreGrams = nil
        let a = MealEditSnapshot(row)
        #expect(a == a)
        row.energyKcal = Double(bitPattern: 0x7ff8_0000_0000_0003)
        #expect(MealEditSnapshot(row) != a)
        row.energyKcal = -0.0
        let negativeZero = MealEditSnapshot(row)
        row.energyKcal = 0.0
        #expect(MealEditSnapshot(row) != negativeZero)
        let absentFibre = MealEditSnapshot(row)
        row.fibreGrams = 0
        #expect(MealEditSnapshot(row) != absentFibre)
        #expect(throws: MealLoggingError.nonFiniteWeight) { _ = try a.originalComponent(id: invalidChildID) }
        #expect(try a.originalComponent(id: UUID()) == nil)
    }

    @Test("Snapshot-only weight edits keep C evidence and unchanged child rows without reading a food")
    func quantityEditKeepsIdentityAndUntouchedRows() throws {
        let c = try container(); let row = try seed(c)
        row.estimateEvidenceGradeRawValue = "c"; row.healthKitSyncVersion = 8
        try c.mainContext.save()
        let baseline = MealEditSnapshot(row)
        let originals = try baseline.originalComponents()
        let first = try MealComponentEditPolicy.resolve(original: originals[0], id: originals[0].id,
            foodItemID: originals[0].foodItemID, weightGrams: 150, currentFood: nil)
        let unchangedID = originals[1].id
        let saved = try MealEditCommand.save(baseline: baseline,
            changes: MealEditChanges(components: [first, originals[1]]), in: c) { context in
            #expect(context.autosaveEnabled == false)
            #expect(context !== c.mainContext)
            #expect(!context.changedModelsArray.contains { ($0 as? PersistentMealComponent)?.id == unchangedID })
            #expect(context.insertedModelsArray.isEmpty)
            #expect(context.deletedModelsArray.isEmpty)
            try context.save()
        }
        #expect(saved.evidenceGradeRawValue == "c")
        #expect(saved.healthKitSyncVersion == 8)
        #expect(saved.components.map(\.id) == baseline.components.map(\.id))
        #expect(saved.components[1] == baseline.components[1])
        #expect(try snapshot(in: c, id: row.id) == saved)
        #expect(try saved.nutrientSnapshot == NutrientValues.sum([first.nutrients, originals[1].nutrients]))
    }

    @Test("Reordering alone preserves inconsistent reported totals instead of recalculating them")
    func reorderingDoesNotRepairTotals() throws {
        let c = try container(); let row = try seed(c)
        row.energyKcal = 900; row.consumedWeightGrams = 700
        row.estimateEvidenceGradeRawValue = "d"
        try c.mainContext.save()
        let before = MealEditSnapshot(row)
        let saved = try MealEditCommand.save(baseline: before,
            changes: MealEditChanges(components: Array(before.originalComponents().reversed())), in: c)
        #expect(saved.components.map(\.id) == before.components.reversed().map(\.id))
        #expect(saved.nutrition == before.nutrition)
        #expect(saved.consumedWeightGrams.bitPattern == before.consumedWeightGrams.bitPattern)
        #expect(saved.evidenceGradeRawValue == "d")
        #expect(try snapshot(in: c, id: row.id) == saved)
    }

    @Test("Adding and removing components updates only the intended UUIDs and inverse relationships")
    func componentMembershipAndRelations() throws {
        let c = try container(); let row = try seed(c)
        let before = MealEditSnapshot(row)
        let retained = try #require(try before.originalComponent(id: before.components[1].id))
        let added = try component(weight: 30)
        let saved = try MealEditCommand.save(baseline: before,
            changes: MealEditChanges(components: [retained, added]), in: c)
        let readContext = ModelContext(c)
        let children = try readContext.fetch(FetchDescriptor<PersistentMealComponent>())
        #expect(Set(children.map(\.id)) == Set([retained.id, added.id]))
        #expect(children.allSatisfy { $0.meal?.id == before.id })
        #expect(try snapshot(in: c, id: row.id) == saved)
        #expect(saved.components[0].sortIndex == before.components[1].sortIndex)
    }

    @Test("A new row at the front or between adjacent indices receives unambiguous order", arguments: [0, 1])
    func insertingBeforeExistingIndexRenumbers(location: Int) throws {
        let c = try container(); let row = try seed(c)
        row.components[0].id = try #require(UUID(uuidString: "80000000-0000-0000-0000-000000000001"))
        row.components[1].id = try #require(UUID(uuidString: "80000000-0000-0000-0000-000000000002"))
        try c.mainContext.save()
        let before = MealEditSnapshot(row)
        let lowID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        let source = try component(weight: 30)
        let added = try MealComponent(id: lowID, foodItemID: source.foodItemID, foodName: source.foodName,
            consumedWeightGrams: source.consumedWeightGrams, unit: source.unit, nutrients: source.nutrients)
        var expected = try before.originalComponents(); expected.insert(added, at: location)
        let saved = try MealEditCommand.save(baseline: before, changes: MealEditChanges(components: expected), in: c)
        #expect(saved.components.map(\.id) == expected.map(\.id))
        #expect(saved.components.map(\.sortIndex) == [0, 1, 2])
        #expect(try snapshot(in: c, id: row.id) == saved)
    }

    @Test("A foreign component UUID never invokes a unique-constraint upsert")
    func componentCollisionProtectsOtherMeals() throws {
        let c = try container(); let row = try seed(c)
        let other = try makeMeal(); c.mainContext.insert(other); try c.mainContext.save()
        let before = MealEditSnapshot(row), otherBefore = MealEditSnapshot(other)
        let foreign = try #require(otherBefore.originalComponents().first)
        #expect(throws: MealEditCommandError.componentIDConflict) {
            try MealEditCommand.save(baseline: before,
                changes: MealEditChanges(components: before.originalComponents() + [foreign]), in: c)
        }
        #expect(try snapshot(in: c, id: row.id) == before)
        #expect(try snapshot(in: c, id: other.id) == otherBefore)
    }

    @Test("Exact target retries do not save twice and stale baselines cannot overwrite later work")
    func idempotentRetryAndStaleBaseline() throws {
        let c = try container(); let row = try seed(c)
        let before = MealEditSnapshot(row), changes = MealEditChanges(title: "synthetic updated")
        var saveCount = 0
        let saved = try MealEditCommand.save(baseline: before, changes: changes, in: c) {
            saveCount += 1; try $0.save()
        }
        let retry = try MealEditCommand.save(baseline: before, changes: changes, in: c) { _ in
            saveCount += 1; throw Injected.beforeCommit
        }
        #expect(retry == saved)
        #expect(saveCount == 1)
        #expect(throws: MealEditCommandError.baselineChanged) {
            try MealEditCommand.save(baseline: before, changes: MealEditChanges(title: "other target"), in: c)
        }
        #expect(try snapshot(in: c, id: row.id) == saved)
    }

    @Test("A committed edit with a failed page refresh retries only the reads and preserves shared drafts")
    func committedRefreshFailureRetriesWithoutSavingAgain() throws {
        let c = try container(); let row = try seed(c)
        let before = MealEditSnapshot(row), parts = try before.originalComponents()
        let heldChild = try #require(row.components.first { $0.id == parts[0].id })
        try #require(heldChild.consumedWeightGrams == 100)
        let changed = try MealComponentEditPolicy.resolve(original: parts[0], id: parts[0].id,
            foodItemID: parts[0].foodItemID, weightGrams: 150, currentFood: nil)
        let changes = MealEditChanges(components: [changed, parts[1]])
        c.mainContext.insert(try makeMeal())
        var saveCount = 0, refreshCount = 0
        let failRefresh: @MainActor (ModelContext, Set<UUID>, UUID) throws -> Void = { context, ids, mealID in
            #expect(context === c.mainContext)
            #expect(ids == Set(before.components.map(\.id)))
            #expect(mealID == before.id)
            refreshCount += 1
            throw Injected.refreshRead
        }
        #expect(throws: MealEditCommandError.savedButRefreshFailed) {
            try MealEditCommand.save(baseline: before, changes: changes, refreshContext: failRefresh, in: c) {
                saveCount += 1; try $0.save()
            }
        }
        let committed = try snapshot(in: c, id: row.id)
        #expect(committed.components.first { $0.id == changed.id }?.consumedWeightGrams == 150)
        #expect(c.mainContext.hasChanges)
        #expect(try ModelContext(c).fetchCount(FetchDescriptor<PersistentMealLog>()) == 1)
        #expect(throws: MealEditCommandError.savedButRefreshFailed) {
            try MealEditCommand.save(baseline: before, changes: changes, refreshContext: failRefresh, in: c) { _ in
                saveCount += 1; throw Injected.beforeCommit
            }
        }
        let retried = try MealEditCommand.save(baseline: before, changes: changes, in: c) { _ in
            saveCount += 1; throw Injected.beforeCommit
        }
        #expect(saveCount == 1)
        #expect(refreshCount == 2)
        #expect(retried == committed)
        #expect(heldChild.consumedWeightGrams == 150)
        #expect(c.mainContext.hasChanges)
        #expect(try ModelContext(c).fetchCount(FetchDescriptor<PersistentMealLog>()) == 1)
        try c.mainContext.save()
        #expect(try ModelContext(c).fetchCount(FetchDescriptor<PersistentMealLog>()) == 2)
        #expect(try snapshot(in: c, id: row.id) == committed)
    }

    @Test("Failures roll back the private edit and retain an unrelated shared draft")
    func failedSaveDoesNotLeakOrCommitDraft() throws {
        let c = try container(); let row = try seed(c)
        let before = MealEditSnapshot(row)
        let draft = try makeMeal(); c.mainContext.insert(draft)
        var attempted: ModelContext?
        #expect(throws: MealEditCommandError.saveFailed) {
            try MealEditCommand.save(baseline: before, changes: MealEditChanges(title: "synthetic failed"), in: c) {
                attempted = $0
                #expect($0 !== c.mainContext)
                #expect($0.autosaveEnabled == false)
                throw Injected.beforeCommit
            }
        }
        #expect(attempted?.hasChanges == false)
        #expect(c.mainContext.hasChanges)
        #expect(try ModelContext(c).fetchCount(FetchDescriptor<PersistentMealLog>()) == 1)
        try attempted?.save(); try c.mainContext.save()
        #expect(try snapshot(in: c, id: row.id) == before)
        #expect(try ModelContext(c).fetchCount(FetchDescriptor<PersistentMealLog>()) == 2)
    }

    @Test("A successful isolated edit does not commit an unrelated shared draft")
    func successfulEditDoesNotCommitDraft() throws {
        let c = try container(); let row = try seed(c)
        let before = MealEditSnapshot(row)
        c.mainContext.insert(try makeMeal())
        let saved = try MealEditCommand.save(baseline: before, changes: MealEditChanges(title: "synthetic updated"), in: c)
        #expect(c.mainContext.hasChanges)
        #expect(try ModelContext(c).fetchCount(FetchDescriptor<PersistentMealLog>()) == 1)
        #expect(try snapshot(in: c, id: row.id) == saved)
    }

    @Test("Shared pending changes to the target are rejected without discarding them", arguments: [0, 1, 2, 3])
    func pendingTargetChangesArePreserved(kind: Int) throws {
        let c = try container(); let row = try seed(c)
        let before = MealEditSnapshot(row)
        switch kind {
        case 0: row.title = "shared draft"
        case 1: row.components[0].consumedWeightGrams = 55
        case 2: c.mainContext.delete(row.components[0])
        default:
            let child = PersistentMealComponent(domain: try component(weight: 20))
            c.mainContext.insert(child); child.meal = row
        }
        #expect(throws: MealEditCommandError.sharedMealHasUnsavedChanges) {
            try MealEditCommand.save(baseline: before, changes: MealEditChanges(title: "private edit"), in: c)
        }
        #expect(c.mainContext.hasChanges)
        #expect(try snapshot(in: c, id: row.id) == before)
    }

    @Test("A real read-only file-store failure preserves the source after reopening")
    func actualReadOnlyFailure() throws {
        let directory = try temporaryDirectory()
        // Do not unlink an asynchronously closing SwiftData store in a defer.
        let url = directory.appendingPathComponent("read-only.store")
        let baseline = try autoreleasepool { let c = try container(url: url); return MealEditSnapshot(try seed(c)) }
        try autoreleasepool {
            let c = try container(url: url, allowsSave: false)
            #expect(throws: MealEditCommandError.saveFailed) {
                try MealEditCommand.save(baseline: baseline, changes: MealEditChanges(title: "cannot write"), in: c)
            }
        }
        try autoreleasepool { () throws -> Void in
            #expect(try snapshot(in: container(url: url), id: baseline.id) == baseline)
        }
    }

    @Test("Only an actual explicit method change remaps valid C evidence", arguments: [false, true])
    func gradeCRequiresActualMethodChange(change: Bool) throws {
        let c = try container(); let row = try seed(c)
        row.estimateEvidenceGradeRawValue = "c"; try c.mainContext.save()
        let saved = try MealEditCommand.save(baseline: MealEditSnapshot(row),
            changes: MealEditChanges(entryMethod: change ? .standardPortionEstimate : .weighed), in: c)
        #expect(saved.evidenceGradeRawValue == (change ? "b" : "c"))
    }

    @Test("Unconfirmed, unknown or invalid remaining data cannot be promoted through a component or method edit",
          arguments: ["d", "future_grade", "inconsistent_total", "unknown_coverage", "invalid_sync"])
    func invalidRemainingDataCannotBeFormalized(issue: String) throws {
        let c = try container(); let row = try seed(c)
        row.estimateEvidenceGradeRawValue = issue == "d" || issue == "future_grade" ? issue : "c"
        if issue == "inconsistent_total" { row.energyKcal = 999 }
        if issue == "unknown_coverage" { row.coverageStatusRawValue = "future_coverage" }
        if issue == "invalid_sync" { row.healthKitSyncVersion = 0 }
        try c.mainContext.save()
        let before = MealEditSnapshot(row)
        #expect(throws: MealEditCommandError.invalidChanges) {
            try MealEditCommand.save(baseline: before,
                changes: MealEditChanges(entryMethod: .standardPortionEstimate), in: c)
        }
        if issue != "inconsistent_total" {
            let old = try before.originalComponents()
            let changed = try MealComponentEditPolicy.resolve(original: old[0], id: old[0].id,
                foodItemID: old[0].foodItemID, weightGrams: 150, currentFood: nil)
            #expect(throws: MealEditCommandError.invalidChanges) {
                try MealEditCommand.save(baseline: before, changes: MealEditChanges(components: [changed, old[1]]), in: c)
            }
        }
        #expect(try snapshot(in: c, id: row.id) == before)
    }

    @Test("A quantity-only save immediately refreshes pre-read main-context children", arguments: [false, true])
    func mainContextVisibilityMeasurement(disk: Bool) throws {
        let url = try disk ? temporaryDirectory().appendingPathComponent("visibility.store") : nil
        let c = try container(url: url); let original = try seed(c)
        let before = MealEditSnapshot(original)
        let parts = try before.originalComponents()
        let originalChild = try #require(original.components.first { $0.id == parts[0].id })
        try #require(originalChild.consumedWeightGrams == 100)
        let changed = try MealComponentEditPolicy.resolve(original: parts[0], id: parts[0].id,
            foodItemID: parts[0].foodItemID, weightGrams: 150, currentFood: nil)
        let saved = try MealEditCommand.save(baseline: before,
            changes: MealEditChanges(components: [changed, parts[1]]), in: c)
        // Read the held child first: neither a relationship access nor a re-fetch
        // may conceal a stale child cache by triggering its refresh for the test.
        #expect(originalChild.consumedWeightGrams == 150)
        #expect(original.components.first { $0.id == changed.id }?.consumedWeightGrams == 150)
        let id = original.id
        let refetched = try #require(c.mainContext.fetch(FetchDescriptor<PersistentMealLog>(predicate: #Predicate { $0.id == id })).first)
        let childID = originalChild.id
        let refetchedChild = try #require(c.mainContext.fetch(FetchDescriptor<PersistentMealComponent>(
            predicate: #Predicate { $0.id == childID })).first)
        #expect(refetchedChild.consumedWeightGrams == 150)
        #expect(MealEditSnapshot(original) == saved)
        #expect(MealEditSnapshot(refetched) == saved)
        #expect(try snapshot(in: c, id: id) == saved)
        #expect(c.mainContext.hasChanges == false)
    }

    private func container(url: URL? = nil, allowsSave: Bool = true) throws -> ModelContainer {
        let schema = Schema(versionedSchema: VersionedSchemaV2.self)
        let configuration: ModelConfiguration
        if let url { configuration = ModelConfiguration(schema: schema, url: url, allowsSave: allowsSave, cloudKitDatabase: .none) }
        else { configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none) }
        let c = try ModelContainer(for: schema, migrationPlan: ShiHengMigrationPlan.self, configurations: configuration)
        c.mainContext.autosaveEnabled = false
        return c
    }
    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("meal-edit-synthetic-\(UUID())")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    private func seed(_ c: ModelContainer) throws -> PersistentMealLog {
        let row = try makeMeal(); c.mainContext.insert(row); try c.mainContext.save(); return row
    }
    private func makeMeal() throws -> PersistentMealLog {
        PersistentMealLog(domain: try MealLog(eatenAt: Date(timeIntervalSince1970: 1_791_633_600),
            title: "synthetic meal", entryMethod: .weighed, coverageStatus: .complete,
            components: [component(weight: 100), component(weight: 50)]))
    }
    private func component(weight: Double) throws -> MealComponent {
        try MealComponent(foodItemID: UUID(), foodName: "synthetic food", consumedWeightGrams: weight, unit: "g",
            nutrients: NutrientValues(energyKcal: weight * 2, fatGrams: weight / 20, saturatedFatGrams: weight / 100,
                carbohydrateGrams: weight / 5, sugarGrams: weight / 25, proteinGrams: weight / 10,
                saltGrams: weight / 1000, fibreGrams: nil))
    }
    private func snapshot(in c: ModelContainer, id: UUID) throws -> MealEditSnapshot {
        let context = ModelContext(c)
        let row = try #require(context.fetch(FetchDescriptor<PersistentMealLog>(predicate: #Predicate { $0.id == id })).first)
        return MealEditSnapshot(row)
    }
    private enum Injected: Error { case beforeCommit, refreshRead }
}
