import Testing

@testable import FoodDecisionAssistant

struct EmptyRecordedEnergyTests {
    @Test("Only no records may show the neutral recorded-zero placeholder", arguments: [
        MealIntakeAvailability.noRecords, .noConfirmedRecords, .available, .unavailable,
    ])
    func placeholderDoesNotUnlockNutritionProgress(availability: MealIntakeAvailability) {
        #expect(availability.showsRecordedZeroPlaceholder == (availability == .noRecords))
        #expect(availability.canShowNutritionProgress == (availability == .available))
        if availability.showsRecordedZeroPlaceholder {
            #expect(availability.canShowNutritionProgress == false)
            #expect(availability.explanation.contains("不代表"))
            #expect(availability.explanation.contains("预算剩余") == false)
        }
    }
}
