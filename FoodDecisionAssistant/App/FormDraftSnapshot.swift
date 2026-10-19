import FoodDecisionCore
import Foundation

/// Only editable inputs participate; keyboard focus, disclosure state and errors do not.
/// This is transient App state, not a domain or persistence schema change.
enum FormDraftSnapshot: Equatable {
    case meal(
        title: String,
        eatenAt: Date,
        entryMethod: MealEntryMethod,
        coverageStatus: MealCoverageStatus,
        components: [MealFormComponentDraft]
    )
    case goal(GoalInputDraft)
    case goalHistory(
        draft: GoalInputDraft,
        effectiveDate: Date,
        source: GoalSource,
        sourceNote: String,
        timeZoneIdentifier: String
    )
    case template(name: String, components: [MealFormComponentDraft])

    /// A cancellation-only candidate, never a normalized replacement for the saved baseline.
    /// Raw whitespace, invalid weight text and unresolved food references remain user inputs.
    var removingInitialEmptyPlaceholder: FormDraftSnapshot? {
        switch self {
        case let .meal(title, eatenAt, entryMethod, coverageStatus, components):
            guard Self.hasOnlyEmptyPlaceholder(components) else { return nil }
            return .meal(title: title, eatenAt: eatenAt, entryMethod: entryMethod,
                         coverageStatus: coverageStatus, components: [])
        case let .template(name, components):
            guard Self.hasOnlyEmptyPlaceholder(components) else { return nil }
            return .template(name: name, components: [])
        case .goal, .goalHistory:
            return nil
        }
    }

    private static func hasOnlyEmptyPlaceholder(_ components: [MealFormComponentDraft]) -> Bool {
        guard components.count == 1, let row = components.first else { return false }
        return row.foodItemID == nil && row.foodName == nil && row.weightText.isEmpty
    }
}
