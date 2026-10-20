import FoodDecisionCore
import Foundation
import SwiftData

/// A value baseline for one editing session. Preview and save resolve each row
/// from this baseline, never from a previous preview or a refreshed food row.
@MainActor
struct MealEditFormState {
    let baseline: MealEditSnapshot
    let initialRows: [MealFormComponentDraft]
    let initialTitle: String
    let initialDate: Date
    let initialMethod: MealEntryMethod
    let initialCoverage: MealCoverageStatus

    func isOriginalFood(_ row: MealFormComponentDraft) -> Bool {
        initialRows.contains { $0.id == row.id && $0.foodItemID == row.foodItemID }
    }

    func componentsAreUnchanged(_ rows: [MealFormComponentDraft]) -> Bool {
        guard rows.count == initialRows.count else { return false }
        return zip(rows, initialRows).allSatisfy { row, original in
            guard row.id == original.id, row.foodItemID == original.foodItemID else { return false }
            if row.weightText == original.weightText { return true }
            guard let value = row.weightGrams, let originalValue = original.weightGrams else { return false }
            return value == originalValue
        }
    }

    func resolve(_ row: MealFormComponentDraft, foods: [PersistentFoodItem]) throws -> MealComponent {
        let stored = baseline.components.filter { $0.id == row.id }
        guard stored.count <= 1 else { throw MealEditCommandError.invalidChanges }
        // Explicitly replacing a damaged row does not decode its old nutrients.
        // Keeping that same food must still validate its original snapshot.
        let original = try stored.first.flatMap { snapshot in
            snapshot.foodItemID == row.foodItemID ? try snapshot.domainModel() : nil
        }
        // Existing, same-food snapshots are self-contained. Do not even decode
        // a changed or damaged current food when only its weight is edited.
        let current: FoodItem?
        if let original, original.foodItemID == row.foodItemID {
            current = nil
        } else {
            current = try foods.first { $0.id == row.foodItemID }?.domainModel
        }
        return try MealComponentEditPolicy.resolve(
            original: original, id: row.id, foodItemID: row.foodItemID,
            weightGrams: row.weightGrams, currentFood: current
        )
    }

    func changes(
        title: String, eatenAt: Date, entryMethod: MealEntryMethod,
        coverageStatus: MealCoverageStatus, rows: [MealFormComponentDraft],
        foods: [PersistentFoodItem]
    ) throws -> MealEditChanges {
        let components: [MealComponent]?
        if componentsAreUnchanged(rows) {
            components = nil
        } else {
            guard !rows.isEmpty else { throw MealLoggingError.emptyComponents }
            components = try rows.map { try resolve($0, foods: foods) }
        }
        return MealEditChanges(
            title: title == initialTitle ? nil : title,
            eatenAt: eatenAt.timeIntervalSinceReferenceDate.bitPattern == initialDate.timeIntervalSinceReferenceDate.bitPattern ? nil : eatenAt,
            entryMethod: entryMethod == initialMethod ? nil : entryMethod,
            coverageStatus: coverageStatus == initialCoverage ? nil : coverageStatus,
            components: components
        )
    }
}
