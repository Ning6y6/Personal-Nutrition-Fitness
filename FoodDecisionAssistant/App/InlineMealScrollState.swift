import Foundation

/// Coordinates one UI scroll after the selected row has both laid out and finished expanding.
/// The token distinguishes separate expansions of the same meal, including A → B → A.
struct InlineMealScrollState: Equatable, Sendable {
    struct Request: Equatable, Sendable {
        let token: UUID
        let mealID: UUID
    }

    private(set) var request: Request?
    private var hasRecordedLayout = false
    private var hasCompletedAnimation = false

    @discardableResult
    mutating func begin(expandedMealID: UUID?) -> Request? {
        invalidate()
        guard let expandedMealID else { return nil }

        let next = Request(token: UUID(), mealID: expandedMealID)
        request = next
        return next
    }

    mutating func recordLayout(for incoming: Request) {
        guard request == incoming else { return }
        hasRecordedLayout = true
    }

    mutating func completeAnimation(for incoming: Request) {
        guard request == incoming else { return }
        hasCompletedAnimation = true
    }

    mutating func takeReadyTarget(
        expandedMealID: UUID?,
        visibleIDs: [UUID],
        isActive: Bool
    ) -> UUID? {
        guard let current = request else { return nil }

        // Validate context before the gates: invalid requests must not revive after a late callback.
        guard isActive,
              expandedMealID == current.mealID,
              visibleIDs.contains(current.mealID)
        else {
            invalidate()
            return nil
        }

        guard hasRecordedLayout, hasCompletedAnimation else { return nil }
        invalidate()
        return current.mealID
    }

    mutating func invalidate() {
        request = nil
        hasRecordedLayout = false
        hasCompletedAnimation = false
    }
}
