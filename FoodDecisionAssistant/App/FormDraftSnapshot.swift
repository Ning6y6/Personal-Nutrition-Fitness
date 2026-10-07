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
    case template(name: String, components: [MealFormComponentDraft])
}
