import FoodDecisionCore
import Foundation
import SwiftData

/// The saved baseline, independent of any unsaved text in the card editor.
struct PersonalFoodDeleteRequest: Equatable, Sendable {
    let originalFood: FoodItem
}

enum PersonalFoodDeleteCommandError: Error, Equatable, LocalizedError {
    case invalidPersonalFood, reservedFoodID, readFailed, idConflict
    case baselineChanged, sharedFoodHasUnsavedChanges, saveFailed, deletedButRefreshFailed

    var errorDescription: String? {
        switch self {
        case .invalidPersonalFood: "这条食品不是本版可删除的按克个人食物，未删除已有数据。"
        case .reservedFoodID: "食品编号属于内置目录，不能删除；已有数据保留。"
        case .readFailed: "无法核对已保存食物卡，已有数据和本次输入保留，请重试。"
        case .idConflict: "食品编号对应的数据异常，未删除任何食品，请重新打开核对。"
        case .baselineChanged: "这张食物卡已发生变化，未删除已有内容；请保留输入并重新打开核对。"
        case .sharedFoodHasUnsavedChanges: "这张食物卡还有未保存的修改，请先处理；未提交或丢弃任何草稿。"
        case .saveFailed: "未能确认食物卡删除完成，本次输入保留。请重试核对同一次结果。"
        case .deletedButRefreshFailed: "食物卡已删除，但暂时无法刷新列表。可重试核对同一次结果；已有餐食和模板保留。"
        }
    }
}

/// Deletes only one verified personal card in a private transaction. Food UUIDs
/// in meal snapshots and templates are value references and remain untouched.
@MainActor
enum PersonalFoodDeleteCommand {
    static func delete(
        request: PersonalFoodDeleteRequest,
        container: ModelContainer,
        verifyOnly: Bool = false,
        identity: PersonalFoodIdentity? = nil,
        saveContext: @MainActor (ModelContext) throws -> Void = { try $0.save() },
        refreshContext: @MainActor (ModelContext, UUID) throws -> Void = { context, id in
            try refreshSharedFood(id: id, context: context)
        }
    ) throws {
        let identity = try identity ?? PersonalFoodIdentity()
        let original = request.originalFood
        guard !identity.isReserved(original.id) else { throw PersonalFoodDeleteCommandError.reservedFoodID }
        guard identity.isEditable(original) else { throw PersonalFoodDeleteCommandError.invalidPersonalFood }

        let shared = container.mainContext
        let pending = shared.insertedModelsArray + shared.changedModelsArray + shared.deletedModelsArray
        guard !pending.contains(where: { ($0 as? PersistentFoodItem)?.id == original.id }) else {
            throw PersonalFoodDeleteCommandError.sharedFoodHasUnsavedChanges
        }

        let context = ModelContext(container)
        context.autosaveEnabled = false
        do {
            let id = original.id
            let found: [PersistentFoodItem]
            do { found = try context.fetch(FetchDescriptor<PersistentFoodItem>(predicate: #Predicate { $0.id == id })) }
            catch { throw PersonalFoodDeleteCommandError.readFailed }
            guard found.count <= 1 else { throw PersonalFoodDeleteCommandError.idConflict }
            if let row = found.first {
                // Once the caller has observed a committed deletion, a later
                // same-ID row may have come from a restore. Never delete it again.
                guard !verifyOnly else { throw PersonalFoodDeleteCommandError.baselineChanged }
                let current: FoodItem
                do { current = try row.domainModel }
                catch { throw PersonalFoodDeleteCommandError.invalidPersonalFood }
                guard identity.isEditable(current) else { throw PersonalFoodDeleteCommandError.invalidPersonalFood }
                guard matches(row, original) else { throw PersonalFoodDeleteCommandError.baselineChanged }
                context.delete(row)
                do { try saveContext(context) }
                catch { throw PersonalFoodDeleteCommandError.saveFailed }
            }
            // An absent row is the same completed result on a retry. Never save
            // or discard the main context to make its list observe this result.
            do { try refreshContext(shared, original.id) }
            catch { throw PersonalFoodDeleteCommandError.deletedButRefreshFailed }
        } catch {
            // Refresh cannot roll back a committed deletion. A save callback may
            // also commit before throwing; the immutable baseline can be retried.
            if error as? PersonalFoodDeleteCommandError == .deletedButRefreshFailed { throw error }
            context.rollback()
            if let known = error as? PersonalFoodDeleteCommandError { throw known }
            throw PersonalFoodDeleteCommandError.saveFailed
        }
    }

    private static func refreshSharedFood(id: UUID, context: ModelContext) throws {
        var descriptor = FetchDescriptor<PersistentFoodItem>(predicate: #Predicate { $0.id == id })
        descriptor.includePendingChanges = false
        _ = try context.fetch(descriptor)
    }

    private static func matches(_ row: PersistentFoodItem, _ original: FoodItem) -> Bool {
        let nutrients = original.nutrientsPer100Units
        let stored = [row.energyKcalPer100Units, row.fatGramsPer100Units, row.saturatedFatGramsPer100Units,
            row.carbohydrateGramsPer100Units, row.sugarGramsPer100Units, row.proteinGramsPer100Units,
            row.saltGramsPer100Units, row.fibreGramsPer100Units]
        let baseline = [nutrients.energyKcal, nutrients.fatGrams, nutrients.saturatedFatGrams,
            nutrients.carbohydrateGrams, nutrients.sugarGrams, nutrients.proteinGrams,
            nutrients.saltGrams, nutrients.fibreGrams]
        return row.id == original.id && row.name == original.name
            && row.categoryRawValue == original.category.rawValue
            && row.unit == original.unit && row.source == original.source
            && zip(stored, baseline).allSatisfy { $0?.bitPattern == $1?.bitPattern }
    }
}
