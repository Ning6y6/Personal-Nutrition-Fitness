import FoodDecisionCore

/// Presents the saved civil key without reinterpreting its effectiveFrom audit instant.
enum GoalDatePresentation {
    static func text(
        for day: GoalDay,
        referenceDay: GoalDay?,
        display: AppDateDisplayContext = .init()
    ) -> String {
        display.civilDate(for: day, referenceDay: referenceDay)
    }
}
