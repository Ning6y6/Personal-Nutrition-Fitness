import FoodDecisionCore
import Foundation

/// A presentation-local raw draft. Saving a food never saves its presenting meal.
struct PersonalFoodFormState {
    let foodID: UUID
    let originalFood: FoodItem?
    let decimalSeparator: String
    private let baseline: PersonalFoodDraft

    var draft: PersonalFoodDraft {
        didSet { pendingRequest = nil }
    }
    private(set) var pendingRequest: PersonalFoodSaveRequest?

    init(
        initialName: String = "",
        foodID: UUID = UUID(),
        decimalSeparator: String = Locale.current.decimalSeparator ?? "."
    ) {
        originalFood = nil
        self.foodID = foodID
        self.decimalSeparator = decimalSeparator
        var initialDraft = PersonalFoodDraft()
        initialDraft.name = initialName
        draft = initialDraft
        baseline = initialDraft
    }

    init(originalFood: FoodItem, decimalSeparator: String = Locale.current.decimalSeparator ?? ".") throws {
        self.originalFood = originalFood
        foodID = originalFood.id
        self.decimalSeparator = decimalSeparator
        let initialDraft = try PersonalFoodDraft(food: originalFood, decimalSeparator: decimalSeparator)
        draft = initialDraft
        baseline = initialDraft
    }

    var hasUnsavedChanges: Bool { draft != baseline }

    func validFood() throws -> FoodItem {
        try draft.validFood(id: foodID, decimalSeparator: decimalSeparator)
    }

    mutating func request() throws -> PersonalFoodSaveRequest {
        let current = PersonalFoodSaveRequest(
            food: try validFood(),
            intent: originalFood.map { .edit(original: $0) } ?? .create
        )
        // Check the complete current value at Save as well as invalidating on every
        // raw edit; a failed request can never silently save older text.
        if pendingRequest == current { return current }
        pendingRequest = current
        return current
    }
}
