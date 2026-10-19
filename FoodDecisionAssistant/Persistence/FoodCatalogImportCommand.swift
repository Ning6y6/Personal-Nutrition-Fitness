import FoodDecisionCore
import Foundation
import SwiftData

struct FoodCatalogImportResult: Equatable, Sendable {
    let insertedIDs: [UUID]
    let unchangedIDs: [UUID]
    let conflictingIDs: [UUID]

    var insertedCount: Int { insertedIDs.count }
}

enum FoodCatalogImportError: Error, Equatable, LocalizedError {
    case catalogUnavailable
    case conflictingCatalogID(UUID)
    case readFailed
    case saveFailed

    var errorDescription: String? {
        switch self {
        case .catalogUnavailable: "无法读取随包食品目录，已有食品和本次输入仍保留。请重试。"
        case .conflictingCatalogID: "食品目录内有重复编号但内容不同的条目，未追加目录。已有食品仍保留。"
        case .readFailed: "无法读取已有食品，未追加目录。已有记录和本次输入仍保留。请重试。"
        case .saveFailed: "食品目录追加失败，本次新增已回滚。已有记录和本次输入仍保留。请重试。"
        }
    }
}

/// Appends a catalog in one synchronous transaction, without saving a form's shared context.
/// Existing rows are compared as stored values, so unknown legacy values remain untouched.
@MainActor
enum FoodCatalogImportCommand {
    @discardableResult
    static func importIfNeeded(
        into container: ModelContainer,
        foods: [FoodItem]? = nil,
        saveContext: @MainActor (ModelContext) throws -> Void = { try $0.save() }
    ) throws -> FoodCatalogImportResult {
        let incoming: [FoodItem]
        if let foods {
            incoming = foods
        } else {
            do { incoming = try FoodCatalog.bundled().entries.map(\.food) }
            catch { throw FoodCatalogImportError.catalogUnavailable }
        }

        // Reject contradictory inputs before creating models. Identical duplicate entries are
        // collapsed, rather than relying on SwiftData's uniqueness upsert behavior.
        var catalogByID: [UUID: FoodItem] = [:]
        for food in incoming {
            if let previous = catalogByID[food.id], previous != food {
                throw FoodCatalogImportError.conflictingCatalogID(food.id)
            }
            catalogByID[food.id] = food
        }

        // Do not race a later parent-context save or resurrect a pending local deletion.
        // Reading these IDs never commits or rolls back the parent's edits.
        let shared = container.mainContext
        let pending = shared.insertedModelsArray + shared.changedModelsArray + shared.deletedModelsArray
        let pendingFoodIDs = Set(pending.compactMap { ($0 as? PersistentFoodItem)?.id })
        let context = ModelContext(container)
        context.autosaveEnabled = false
        do {
            let existing: [PersistentFoodItem]
            do { existing = try context.fetch(FetchDescriptor<PersistentFoodItem>()) }
            catch { throw FoodCatalogImportError.readFailed }
            let existingByID = Dictionary(grouping: existing, by: \.id)
            var inserted: [UUID] = []
            var unchanged: [UUID] = []
            var conflicting: [UUID] = []

            for food in catalogByID.values.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
                if pendingFoodIDs.contains(food.id) {
                    conflicting.append(food.id)
                } else if let rows = existingByID[food.id] {
                    if rows.count == 1, let row = rows.first, matches(row, food: food) {
                        unchanged.append(food.id)
                    } else {
                        conflicting.append(food.id)
                    }
                } else {
                    context.insert(PersistentFoodItem(domain: food))
                    inserted.append(food.id)
                }
            }

            if !inserted.isEmpty {
                do { try saveContext(context) }
                catch { throw FoodCatalogImportError.saveFailed }
            }
            return FoodCatalogImportResult(insertedIDs: inserted, unchangedIDs: unchanged, conflictingIDs: conflicting)
        } catch {
            context.rollback()
            // Framework errors can include private values or paths. Expose only safe categories.
            if let known = error as? FoodCatalogImportError { throw known }
            throw FoodCatalogImportError.saveFailed
        }
    }

    private static func matches(_ row: PersistentFoodItem, food: FoodItem) -> Bool {
        let nutrients = food.nutrientsPer100Units
        return row.name == food.name
            && row.categoryRawValue == food.category.rawValue
            && row.unit == food.unit
            && row.source == food.source
            && row.energyKcalPer100Units == nutrients.energyKcal
            && row.fatGramsPer100Units == nutrients.fatGrams
            && row.saturatedFatGramsPer100Units == nutrients.saturatedFatGrams
            && row.carbohydrateGramsPer100Units == nutrients.carbohydrateGrams
            && row.sugarGramsPer100Units == nutrients.sugarGrams
            && row.proteinGramsPer100Units == nutrients.proteinGrams
            && row.saltGramsPer100Units == nutrients.saltGrams
            && row.fibreGramsPer100Units == nutrients.fibreGrams
    }
}
