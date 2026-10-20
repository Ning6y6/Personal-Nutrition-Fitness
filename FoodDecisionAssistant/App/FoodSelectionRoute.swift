import Foundation

struct FoodSelectionRoute: Hashable {
    let rowID: UUID
    // Keep the destination valid during a pop, even after its draft row is removed.
    let selectedFoodID: UUID?
}
