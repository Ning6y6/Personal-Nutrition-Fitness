import Foundation

/// Navigation may outlive the row that opened it. Never retarget by array index.
enum FoodSelectionDraftUpdate {
    @discardableResult
    static func apply(foodID: UUID?, to rowID: UUID, rows: inout [MealFormComponentDraft]) -> Bool {
        guard let index = rows.firstIndex(where: { $0.id == rowID }) else { return false }
        rows[index].foodItemID = foodID
        return true
    }
}
