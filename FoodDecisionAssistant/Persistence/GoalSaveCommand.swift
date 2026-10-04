import FoodDecisionCore
import Foundation
import SwiftData

enum GoalSaveCommandError: Error, Equatable, LocalizedError {
    case goalNotFound(UUID)
    case goalAlreadyExists(UUID)
    case ambiguousGoalIdentity(UUID)
    case sharedGoalHasUnsavedChanges(UUID)
    case fetchFailed
    case saveFailed

    var errorDescription: String? {
        switch self {
        case .goalNotFound: "要编辑的目标已经不存在；未自动建立替代目标，请重新打开设置。"
        case .goalAlreadyExists: "新目标的标识已存在；未覆盖现有目标，请重新打开设置。"
        case .ambiguousGoalIdentity: "目标标识对应多条记录，未修改任何目标。"
        case .sharedGoalHasUnsavedChanges: "当前目标在另一个上下文中有未保存修改，请先保存或取消该修改。"
        case .fetchFailed: "无法读取要保存的目标，原记录和其他页面草稿均保留。"
        case .saveFailed: "目标保存失败，本次修改已回滚；原目标和其他页面草稿均保留。"
        }
    }
}

/// A confirmed, validated value is the only input to a goal transaction. No shared @Model object
/// is accepted, and no shared context is saved or rolled back to refresh the UI.
@MainActor
enum GoalSaveCommand {
    @discardableResult
    static func save(
        draft: GoalInputDraft,
        existingID: UUID?,
        effectiveFrom: Date,
        container: ModelContainer,
        newGoalID: UUID = UUID(),
        decimalSeparator: String = ".",
        saveContext: @MainActor (ModelContext) throws -> Void = { try $0.save() }
    ) throws -> UUID {
        // Validation (including explicit confirmation) precedes context creation and all writes.
        let profile = try draft.validGoal(
            id: existingID ?? newGoalID,
            effectiveFrom: effectiveFrom,
            decimalSeparator: decimalSeparator
        )
        let context = ModelContext(container)
        context.autosaveEnabled = false
        do {
            let targetID = profile.id
            var descriptor = FetchDescriptor<PersistentGoalProfile>(predicate: #Predicate { $0.id == targetID })
            descriptor.fetchLimit = 2
            let matches: [PersistentGoalProfile]
            do { matches = try context.fetch(descriptor) }
            catch { throw GoalSaveCommandError.fetchFailed }
            guard matches.count <= 1 else { throw GoalSaveCommandError.ambiguousGoalIdentity(targetID) }

            let storedGoal = matches.first
            if existingID != nil {
                guard storedGoal != nil else { throw GoalSaveCommandError.goalNotFound(targetID) }
            } else {
                guard storedGoal == nil else { throw GoalSaveCommandError.goalAlreadyExists(targetID) }
            }
            try ensureSharedGoalIsNotDirty(id: targetID, savedIdentifier: storedGoal?.persistentModelID, container: container)

            if let storedGoal {
                // `profile.id` was derived from existingID; no unrelated row can be updated.
                // effectiveFrom is the caller's captured value, not a new target-version timestamp.
                storedGoal.update(from: profile)
            } else {
                context.insert(PersistentGoalProfile(domain: profile))
            }
            // Test injection must throw before commit or delegate to the single atomic save.
            // Never implement a hook that commits successfully and then throws.
            try saveContext(context)
            return profile.id
        } catch {
            context.rollback()
            if let error = error as? GoalSaveCommandError { throw error }
            // Do not display Core Data diagnostics containing private values or file paths.
            throw GoalSaveCommandError.saveFailed
        }
    }

    private static func ensureSharedGoalIsNotDirty(
        id: UUID, savedIdentifier: PersistentIdentifier?, container: ModelContainer
    ) throws {
        let shared = container.mainContext
        // Inspect only change-tracking identities. Never use a shared draft's target values as
        // inputs, and never block or commit an unrelated meal/template/other-goal draft.
        let changed = shared.insertedModelsArray + shared.changedModelsArray + shared.deletedModelsArray
        let hasConflictingGoal = changed.contains { model in
            guard let goal = model as? PersistentGoalProfile else { return false }
            return goal.id == id || savedIdentifier.map { goal.persistentModelID == $0 } == true
        }
        if hasConflictingGoal { throw GoalSaveCommandError.sharedGoalHasUnsavedChanges(id) }
    }
}
