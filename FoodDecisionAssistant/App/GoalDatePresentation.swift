import FoodDecisionCore

/// Formats an already validated civil date without converting it through an instant or time zone.
enum GoalDatePresentation {
    static func text(for day: GoalDay, referenceDay: GoalDay?) -> String {
        let year = day.key / 10_000
        let month = day.key / 100 % 100
        let dayOfMonth = day.key % 100
        let monthAndDay = "\(month)月\(dayOfMonth)日"
        if let referenceDay, referenceDay.key / 10_000 == year {
            return monthAndDay
        }
        return "\(year)年\(monthAndDay)"
    }
}
