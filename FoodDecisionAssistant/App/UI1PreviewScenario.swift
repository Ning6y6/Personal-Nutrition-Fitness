import FoodDecisionCore

/// Fictitious, transient fixtures only. Never inserted into the user's model container.
enum UI1PreviewScenario: String, CaseIterable {
    case empty, withinBudget, atBudget, overflow, multiple, unknown

    var energyKcal: Double {
        switch self {
        case .empty, .unknown: 0
        case .withinBudget: 1_420
        case .atBudget: 2_000
        case .overflow: 2_600
        case .multiple: 6_400
        }
    }

    func goal() throws -> GoalProfile {
        try GoalProfile(
            energyKcal: 2_000, proteinGrams: 140, carbohydrateGrams: 210, fatGrams: 60,
            saturatedFatLimitGrams: 15, fibreGrams: 30
        )
    }

    func nutrients() throws -> NutrientValues {
        try NutrientValues(
            energyKcal: energyKcal, fatGrams: 42, saturatedFatGrams: 12,
            carbohydrateGrams: 150, sugarGrams: 20, proteinGrams: 96,
            saltGrams: 3, fibreGrams: 18
        )
    }
}
