import FoodDecisionCore
import Foundation
import SwiftData
import Testing

@testable import FoodDecisionAssistant

@MainActor
struct GoalSaveCommandTests {
    @Test("A confirmed new goal is committed once and readable through an independent context")
    func newGoalSavesAndFreshReadMatches() throws {
        let container = try makeContainer()
        let goal = try makeGoal()
        let id = try GoalSaveCommand.save(draft: confirmedDraft(goal), existingID: nil, effectiveFrom: goal.effectiveFrom, container: container, newGoalID: goal.id)
        #expect(id == goal.id)
        #expect(try freshGoal(id: id, in: container) == goal)
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<PersistentGoalProfile>()) == 1)
        #expect(container.mainContext.hasChanges == false)
    }

    @Test("Editing updates only the selected goal and preserves its captured effective date")
    func editedGoalPreservesIdentityAndEffectiveDate() throws {
        let container = try makeContainer()
        let original = try makeGoal()
        try seed(original, in: container)
        var draft = confirmedDraft(original)
        draft.energyKcal = "2300"
        draft.proteinGrams = "150"
        let id = try GoalSaveCommand.save(draft: draft, existingID: original.id, effectiveFrom: original.effectiveFrom, container: container)
        let saved = try #require(try freshGoal(id: id, in: container))
        #expect(id == original.id)
        #expect(saved.energyKcal == 2300)
        #expect(saved.proteinGrams == 150)
        #expect(saved.effectiveFrom == original.effectiveFrom)
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<PersistentGoalProfile>()) == 1)
    }

    @Test("A missing edit target cannot become an upsert")
    func deletedTargetDoesNotUpsert() throws {
        let container = try makeContainer()
        let goal = try makeGoal()
        #expect(throws: GoalSaveCommandError.goalNotFound(goal.id)) {
            try GoalSaveCommand.save(draft: confirmedDraft(goal), existingID: goal.id, effectiveFrom: goal.effectiveFrom, container: container)
        }
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<PersistentGoalProfile>()) == 0)
    }

    @Test("An explicit new identity collision cannot invoke unique-constraint upsert")
    func newIdentityCollisionCannotOverwrite() throws {
        let container = try makeContainer()
        let original = try makeGoal()
        try seed(original, in: container)
        var draft = confirmedDraft(original)
        draft.energyKcal = "2800"
        #expect(throws: GoalSaveCommandError.goalAlreadyExists(original.id)) {
            try GoalSaveCommand.save(draft: draft, existingID: nil, effectiveFrom: original.effectiveFrom, container: container, newGoalID: original.id)
        }
        #expect(try freshGoal(id: original.id, in: container) == original)
    }

    @Test("Goal save neither commits an unrelated shared meal draft nor loses the goal on a later meal save")
    func sharedMealDraftStaysUncommittedUntilItsOwnSave() throws {
        let container = try makeContainer()
        let original = try makeGoal()
        try seed(original, in: container)
        let shared = container.mainContext
        shared.autosaveEnabled = false
        // Register the old goal before the independent write to exercise stale-context behavior.
        let registeredGoal = try #require(try shared.fetch(FetchDescriptor<PersistentGoalProfile>()).first)
        #expect(registeredGoal.energyKcal == original.energyKcal)
        let meal = try makeMeal()
        shared.insert(meal)
        var draft = confirmedDraft(original)
        draft.energyKcal = "2400"
        try GoalSaveCommand.save(draft: draft, existingID: original.id, effectiveFrom: original.effectiveFrom, container: container)
        #expect(try freshGoal(id: original.id, in: container)?.energyKcal == 2400)
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<PersistentMealLog>()) == 0)
        #expect(shared.hasChanges)
        #expect(shared.insertedModelsArray.contains { ($0 as? PersistentMealLog)?.id == meal.id })

        try shared.save()
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<PersistentMealLog>()) == 1)
        #expect(try freshGoal(id: original.id, in: container)?.energyKcal == 2400)
    }

    @Test("A registered but untouched stale goal cannot overwrite a fresh edit on an empty shared save")
    func emptySharedSaveCannotOverwriteFreshGoal() throws {
        let container = try makeContainer()
        let original = try makeGoal()
        try seed(original, in: container)
        let shared = container.mainContext
        shared.autosaveEnabled = false
        let old = try #require(try shared.fetch(FetchDescriptor<PersistentGoalProfile>()).first)
        #expect(old.energyKcal == 2000)
        var draft = confirmedDraft(original)
        draft.energyKcal = "2500"
        try GoalSaveCommand.save(draft: draft, existingID: original.id, effectiveFrom: original.effectiveFrom, container: container)
        #expect(try freshGoal(id: original.id, in: container)?.energyKcal == 2500)
        try shared.save()
        #expect(try freshGoal(id: original.id, in: container)?.energyKcal == 2500)
    }

    @Test("A failed insert or update rolls back only its private context", arguments: [false, true])
    func injectedFailureLeavesNoTargetResidue(isEdit: Bool) throws {
        let container = try makeContainer()
        let original = try makeGoal()
        if isEdit { try seed(original, in: container) }
        let shared = container.mainContext
        shared.autosaveEnabled = false
        shared.insert(try makeMeal())
        var draft = confirmedDraft(original)
        draft.energyKcal = "2900"
        var attemptedContext: ModelContext?
        #expect(throws: GoalSaveCommandError.saveFailed) {
            try GoalSaveCommand.save(draft: draft, existingID: isEdit ? original.id : nil, effectiveFrom: original.effectiveFrom, container: container, newGoalID: original.id) { context in
                attemptedContext = context
                #expect(context !== shared)
                #expect(context.autosaveEnabled == false)
                #expect(context.hasChanges)
                #expect(try context.fetch(FetchDescriptor<PersistentGoalProfile>()).first?.energyKcal == 2900)
                throw SaveFailure.beforeCommit
            }
        }
        let rolledBack = try #require(attemptedContext)
        #expect(rolledBack.hasChanges == false)
        #expect(rolledBack.insertedModelsArray.isEmpty)
        #expect(rolledBack.changedModelsArray.isEmpty)
        #expect(shared.hasChanges)
        #expect(try freshGoal(id: original.id, in: container) == (isEdit ? original : nil))
        // Closing/cancelling the goal form needs no shared rollback. Even a later save of both
        // contexts cannot commit the failed goal operation, while the meal remains independently valid.
        try rolledBack.save()
        try shared.save()
        #expect(try freshGoal(id: original.id, in: container) == (isEdit ? original : nil))
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<PersistentMealLog>()) == 1)
    }

    @Test("An actual read-only SQLite save failure leaves the old goal unchanged after reopening")
    func realReadOnlyFailureDoesNotPersist() throws {
        let directory = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("goal-command-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("goals.store")
        let original = try makeGoal()
        try autoreleasepool { try seed(original, in: makeContainer(at: storeURL)) }
        try autoreleasepool {
            let readOnly = try makeContainer(at: storeURL, allowsSave: false)
            var draft = confirmedDraft(original)
            draft.energyKcal = "3100"
            #expect(throws: GoalSaveCommandError.saveFailed) {
                try GoalSaveCommand.save(draft: draft, existingID: original.id, effectiveFrom: original.effectiveFrom, container: readOnly)
            }
            #expect(try freshGoal(id: original.id, in: readOnly) == original)
        }
        let reopened = try makeContainer(at: storeURL)
        #expect(try freshGoal(id: original.id, in: reopened) == original)
        #expect(try StoreSchemaCompatibility.modelHashes(at: storeURL) == StoreSchemaCompatibility.frozenModelHashes)
    }

    @Test("Dirty shared state for the same goal is rejected, without saving or rolling it back")
    func sameGoalDirtyConflictIsPreserved() throws {
        let container = try makeContainer()
        let original = try makeGoal()
        try seed(original, in: container)
        let shared = container.mainContext
        shared.autosaveEnabled = false
        let dirty = try #require(try shared.fetch(FetchDescriptor<PersistentGoalProfile>()).first)
        dirty.energyKcal = 2600
        var draft = confirmedDraft(original)
        draft.energyKcal = "2300"
        var saveWasCalled = false
        #expect(throws: GoalSaveCommandError.sharedGoalHasUnsavedChanges(original.id)) {
            try GoalSaveCommand.save(draft: draft, existingID: original.id, effectiveFrom: original.effectiveFrom, container: container) { _ in
                saveWasCalled = true
            }
        }
        #expect(saveWasCalled == false)
        #expect(dirty.energyKcal == 2600)
        #expect(shared.hasChanges)
        #expect(try freshGoal(id: original.id, in: container) == original)
    }

    @Test("A dirty different goal does not block or join the selected goal transaction")
    func otherGoalDraftIsIndependent() throws {
        let container = try makeContainer()
        let original = try makeGoal()
        let other = try makeGoal(energy: 1800)
        try seed(original, in: container)
        try seed(other, in: container)
        let shared = container.mainContext
        shared.autosaveEnabled = false
        let unrelated = try #require(try shared.fetch(FetchDescriptor<PersistentGoalProfile>()).first { $0.id == other.id })
        unrelated.energyKcal = 1900
        var draft = confirmedDraft(original)
        draft.energyKcal = "2200"
        try GoalSaveCommand.save(draft: draft, existingID: original.id, effectiveFrom: original.effectiveFrom, container: container)
        #expect(try freshGoal(id: original.id, in: container)?.energyKcal == 2200)
        #expect(try freshGoal(id: other.id, in: container) == other)
        #expect(unrelated.energyKcal == 1900)
        try shared.save()
        #expect(try freshGoal(id: original.id, in: container)?.energyKcal == 2200)
        #expect(try freshGoal(id: other.id, in: container)?.energyKcal == 1900)
    }

    @Test("Blank optional values stay nil; explicit zeros stay zeros", arguments: [false, true])
    func optionalLimitsAreNotInvented(explicitZero: Bool) throws {
        let container = try makeContainer()
        let original = try makeGoal()
        try seed(original, in: container)
        var draft = confirmedDraft(original)
        draft.saturatedFatLimitGrams = explicitZero ? "0" : "  "
        draft.fibreGrams = explicitZero ? "0" : "\n"
        try GoalSaveCommand.save(draft: draft, existingID: original.id, effectiveFrom: original.effectiveFrom, container: container)
        let result = try #require(try freshGoal(id: original.id, in: container))
        #expect(result.saturatedFatLimitGrams == (explicitZero ? 0 : nil))
        #expect(result.fibreGrams == (explicitZero ? 0 : nil))
    }

    @Test("Unconfirmed or invalid draft input cannot reach the saver", arguments: ["unconfirmed", "missing", "number", "negative", "nonfinite"])
    func invalidDraftCannotMutateStore(kind: String) throws {
        let container = try makeContainer()
        let original = try makeGoal()
        try seed(original, in: container)
        var draft = confirmedDraft(original)
        let expected: any Error
        switch kind {
        case "unconfirmed": draft.isConfirmed = false; expected = GoalInputError.confirmationRequired
        case "missing": draft.energyKcal = ""; expected = GoalInputError.missingRequiredField("energyKcal")
        case "number": draft.energyKcal = "not-a-number"; expected = GoalInputError.invalidNumber("energyKcal")
        case "negative": draft.energyKcal = "-1"; expected = DomainValidationError.invalidValue(field: "energyKcal")
        default: draft.energyKcal = "1e309"; expected = DomainValidationError.nonFiniteValue(field: "energyKcal")
        }
        var saveWasCalled = false
        do {
            try GoalSaveCommand.save(draft: draft, existingID: original.id, effectiveFrom: original.effectiveFrom, container: container) { _ in saveWasCalled = true }
            Issue.record("The invalid goal draft unexpectedly passed validation")
        } catch {
            if let expected = expected as? GoalInputError { #expect(error as? GoalInputError == expected) }
            else if let expected = expected as? DomainValidationError { #expect(error as? DomainValidationError == expected) }
            else { Issue.record("Unexpected test error fixture") }
        }
        #expect(saveWasCalled == false)
        #expect(container.mainContext.hasChanges == false)
        #expect(try freshGoal(id: original.id, in: container) == original)
    }

    private enum SaveFailure: Error { case beforeCommit }

    private func makeGoal(energy: Double = 2000) throws -> GoalProfile {
        try GoalProfile(effectiveFrom: Date(timeIntervalSince1970: 1_700_000_000), energyKcal: energy, proteinGrams: 140, carbohydrateGrams: 210, fatGrams: 60, saturatedFatLimitGrams: nil, fibreGrams: nil)
    }

    private func confirmedDraft(_ goal: GoalProfile) -> GoalInputDraft {
        var draft = GoalInputDraft(existingGoal: goal)
        draft.isConfirmed = true
        return draft
    }

    private func makeMeal() throws -> PersistentMealLog {
        let component = try MealComponent(foodItemID: UUID(), foodName: "synthetic fixture", consumedWeightGrams: 100, unit: "g", nutrients: .zero)
        return PersistentMealLog(domain: try MealLog(title: "independent meal draft", entryMethod: .weighed, coverageStatus: .complete, components: [component]))
    }

    private func seed(_ profile: GoalProfile, in container: ModelContainer) throws {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        context.insert(PersistentGoalProfile(domain: profile))
        try context.save()
    }

    private func freshGoal(id: UUID, in container: ModelContainer) throws -> GoalProfile? {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let descriptor = FetchDescriptor<PersistentGoalProfile>(predicate: #Predicate { $0.id == id })
        return try context.fetch(descriptor).first?.domainModel
    }

    private func makeContainer(at url: URL? = nil, allowsSave: Bool = true) throws -> ModelContainer {
        let schema = Schema(versionedSchema: VersionedSchemaV1.self)
        let configuration: ModelConfiguration
        if let url { configuration = ModelConfiguration(schema: schema, url: url, allowsSave: allowsSave, cloudKitDatabase: .none) }
        else { configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, allowsSave: allowsSave, cloudKitDatabase: .none) }
        return try ModelContainer(for: schema, migrationPlan: ShiHengMigrationPlan.self, configurations: configuration)
    }
}
