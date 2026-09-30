import Testing
@testable import FoodDecisionCore

@Test func weightedScoreUsesOnlyAvailableOptionalComponents() throws {
    let profile = try ScoreProfile.bundled()
    let result = try NutritionScoreEngine.score(
        componentScores: [
            .proteinDensity: 80,
            .saturatedFat: 60,
            .sugar: 100,
            .salt: 40,
            .energyDensity: 70,
        ],
        category: .proteinMain,
        profile: profile
    )

    #expect(result == 68)
}

@Test func scoreIsClampedToValidRange() throws {
    let profile = try ScoreProfile.bundled()
    let result = try NutritionScoreEngine.score(
        componentScores: [.sugar: 140, .salt: -20],
        category: .beverage,
        profile: profile
    )

    #expect(result == 80)
}

