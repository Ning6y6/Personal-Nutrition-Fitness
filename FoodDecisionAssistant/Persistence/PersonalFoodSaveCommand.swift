import FoodDecisionCore
import Foundation
import SwiftData

enum PersonalFoodSaveIntent: Equatable, Sendable {
    case create
    case edit(original: FoodItem)
}

struct PersonalFoodSaveRequest: Equatable, Sendable {
    let food: FoodItem
    let intent: PersonalFoodSaveIntent
}

enum PersonalFoodSaveCommandError: Error, Equatable, LocalizedError {
    case invalidPersonalFood, reservedFoodID, readFailed, idConflict
    case baselineChanged, sharedFoodHasUnsavedChanges, saveFailed, savedButRefreshFailed

    var errorDescription: String? {
        switch self {
        case .invalidPersonalFood: "这条食品不是本版可编辑的按克个人食物，未修改已有数据。"
        case .reservedFoodID: "食品编号属于内置目录，不能作为个人食物保存；已有数据和本次输入保留。"
        case .readFailed: "无法读取已保存食品，已有数据和本次输入保留，请重试。"
        case .idConflict: "食品编号已对应其他内容，未覆盖已有食品；本次输入保留。"
        case .baselineChanged: "这张食物卡已发生变化，未覆盖已有内容；请保留输入并重新打开核对。"
        case .sharedFoodHasUnsavedChanges: "这张食物卡还有未保存的修改，请先处理；未提交或丢弃任何草稿。"
        case .saveFailed: "食物卡保存失败，本次写入已回滚；已有数据和本次输入保留，请重试。"
        case .savedButRefreshFailed: "食物卡已保存，但暂时无法刷新列表。输入仍保留，可重试核对同一次结果。"
        }
    }
}

/// Commits only one card in its own transaction. In particular it never saves or
/// rolls back the main context containing a meal/template/goal draft.
@MainActor
enum PersonalFoodSaveCommand {
    @discardableResult
    static func save(
        request: PersonalFoodSaveRequest,
        container: ModelContainer,
        identity: PersonalFoodIdentity? = nil,
        saveContext: @MainActor (ModelContext) throws -> Void = { try $0.save() }
    ) throws -> FoodItem {
        let identity = try identity ?? PersonalFoodIdentity()
        let target = request.food
        guard !identity.isReserved(target.id) else { throw PersonalFoodSaveCommandError.reservedFoodID }
        guard identity.isEditable(target) else { throw PersonalFoodSaveCommandError.invalidPersonalFood }
        if case let .edit(original) = request.intent {
            guard original.id == target.id else { throw PersonalFoodSaveCommandError.idConflict }
            guard identity.isEditable(original) else { throw PersonalFoodSaveCommandError.invalidPersonalFood }
        }

        let shared = container.mainContext
        let pending = shared.insertedModelsArray + shared.changedModelsArray + shared.deletedModelsArray
        guard !pending.contains(where: { ($0 as? PersistentFoodItem)?.id == target.id }) else {
            throw PersonalFoodSaveCommandError.sharedFoodHasUnsavedChanges
        }

        let context = ModelContext(container)
        context.autosaveEnabled = false
        do {
            let id = target.id
            let descriptor = FetchDescriptor<PersistentFoodItem>(predicate: #Predicate { $0.id == id })
            let found: [PersistentFoodItem]
            do { found = try context.fetch(descriptor) }
            catch { throw PersonalFoodSaveCommandError.readFailed }
            guard found.count <= 1 else { throw PersonalFoodSaveCommandError.idConflict }

            if let row = found.first {
                let current: FoodItem
                do { current = try row.domainModel }
                catch { throw PersonalFoodSaveCommandError.invalidPersonalFood }
                guard identity.isEditable(current) else { throw PersonalFoodSaveCommandError.invalidPersonalFood }
                // The same operation can be retried after a committed result. It
                // must not rely on @Attribute(.unique)'s automatic upsert behavior.
                if current == target {
                    try refreshSharedFood(id: id, context: shared)
                    return current
                }
                switch request.intent {
                case .create: throw PersonalFoodSaveCommandError.idConflict
                case let .edit(original):
                    guard current == original else { throw PersonalFoodSaveCommandError.baselineChanged }
                    apply(target, to: row)
                }
            } else {
                guard request.intent == .create else { throw PersonalFoodSaveCommandError.baselineChanged }
                context.insert(PersistentFoodItem(domain: target))
            }

            do { try saveContext(context) }
            catch { throw PersonalFoodSaveCommandError.saveFailed }
            try refreshSharedFood(id: target.id, context: shared)
            return target
        } catch {
            // A refresh failure cannot undo a transaction that already committed.
            if error as? PersonalFoodSaveCommandError == .savedButRefreshFailed { throw error }
            context.rollback()
            if let known = error as? PersonalFoodSaveCommandError { throw known }
            throw PersonalFoodSaveCommandError.saveFailed
        }
    }

    private static func refreshSharedFood(id: UUID, context: ModelContext) throws {
        var descriptor = FetchDescriptor<PersistentFoodItem>(predicate: #Predicate { $0.id == id })
        descriptor.includePendingChanges = false
        do { _ = try context.fetch(descriptor) }
        catch { throw PersonalFoodSaveCommandError.savedButRefreshFailed }
    }

    private static func apply(_ food: FoodItem, to row: PersistentFoodItem) {
        let value = food.nutrientsPer100Units
        row.name = food.name
        row.categoryRawValue = food.category.rawValue
        row.energyKcalPer100Units = value.energyKcal
        row.fatGramsPer100Units = value.fatGrams
        row.saturatedFatGramsPer100Units = value.saturatedFatGrams
        row.carbohydrateGramsPer100Units = value.carbohydrateGrams
        row.sugarGramsPer100Units = value.sugarGrams
        row.proteinGramsPer100Units = value.proteinGrams
        row.saltGramsPer100Units = value.saltGrams
        row.fibreGramsPer100Units = value.fibreGrams
        row.unit = food.unit
        row.source = food.source
    }
}
