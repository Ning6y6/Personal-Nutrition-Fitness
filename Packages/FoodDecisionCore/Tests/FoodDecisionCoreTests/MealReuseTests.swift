import Foundation
import Testing

@testable import FoodDecisionCore

@Suite("Recent meals and personal templates")
struct MealReuseTests {
    @Test("Recent meals are newest first, deduplicated, and limited to six")
    func recentMealsAreSortedDeduplicatedAndLimited() throws {
        let food = try makeFood(name: "牛肉")
        var meals = try (0..<7).map { offset in
            try makeMeal(
                title: "餐食 \(offset)",
                date: Date(timeIntervalSince1970: TimeInterval(offset)),
                foods: [food]
            )
        }
        meals.append(
            try makeMeal(
                title: "  餐食 6  ",
                date: Date(timeIntervalSince1970: 100),
                foods: [food]
            )
        )

        let result = RecentMealSelector.select(from: meals)

        #expect(result.count == 6)
        #expect(result.first?.eatenAt == Date(timeIntervalSince1970: 100))
        #expect(result.filter { $0.title.trimmingCharacters(in: .whitespaces) == "餐食 6" }.count == 1)
    }

    @Test("Meals with the same title but different food compositions stay distinct")
    func compositionParticipatesInDeduplication() throws {
        let beef = try makeFood(name: "牛肉")
        let rice = try makeFood(name: "米饭")
        let meals = [
            try makeMeal(title: "晚餐", date: Date(timeIntervalSince1970: 2), foods: [beef]),
            try makeMeal(title: "晚餐", date: Date(timeIntervalSince1970: 1), foods: [beef, rice]),
        ]

        let result = RecentMealSelector.select(from: meals)

        #expect(result.count == 2)
    }

    @Test("Reusing history creates fresh component IDs and evidence B")
    func historyReuseCreatesIndependentDraft() throws {
        let meal = try makeMeal(title: "午餐", date: .now, foods: [makeFood(name: "鸡肉")])

        let draft = MealEntryDraft(reusing: meal, now: Date(timeIntervalSince1970: 50))

        #expect(draft.entryMethod == .standardPortionEstimate)
        #expect(draft.entryMethod.evidenceGrade == .b)
        #expect(draft.coverageStatus == .complete)
        #expect(draft.components.map(\.id) != meal.components.map(\.id))
        #expect(draft.sourceTemplateID == nil)
    }

    @Test("Using a template tracks its source and copies default weights into fresh draft rows")
    func templateCreatesTraceableDraft() throws {
        let food = try makeFood(name: "豆腐")
        let templateComponent = try MealTemplateComponent(
            foodItemID: food.id,
            foodName: food.name,
            defaultWeightGrams: 180
        )
        let template = try MealTemplate(name: "豆腐餐", components: [templateComponent])

        let draft = MealEntryDraft(template: template)

        #expect(draft.sourceTemplateID == template.id)
        #expect(draft.entryMethod == .standardPortionEstimate)
        #expect(draft.components.first?.weightGrams == 180)
        #expect(draft.components.first?.id != templateComponent.id)
    }

    @Test("Template input validation rejects empty names, empty components, and invalid weights")
    func templateValidationRejectsInvalidInput() throws {
        let food = try makeFood(name: "米饭")

        #expect(throws: MealTemplateError.invalidWeight) {
            try MealTemplateComponent(
                foodItemID: food.id,
                foodName: food.name,
                defaultWeightGrams: 0
            )
        }
        #expect(throws: MealTemplateError.emptyComponents) {
            try MealTemplate(name: "空模板", components: [])
        }
        #expect(throws: MealTemplateError.emptyName) {
            try MealTemplate(
                name: "   ",
                components: [
                    try MealTemplateComponent(
                        foodItemID: food.id,
                        foodName: food.name,
                        defaultWeightGrams: 100
                    ),
                ]
            )
        }
    }

    @Test("Templates support Codable round trips and usage recording")
    func templateCodableRoundTrip() throws {
        let food = try makeFood(name: "西红柿")
        var template = try MealTemplate(
            name: "西红柿餐",
            components: [
                try MealTemplateComponent(
                    foodItemID: food.id,
                    foodName: food.name,
                    defaultWeightGrams: 220
                ),
            ]
        )
        try template.recordUse(at: Date(timeIntervalSince1970: 200))

        let data = try JSONEncoder().encode(template)
        let restored = try JSONDecoder().decode(MealTemplate.self, from: data)

        #expect(restored == template)
        #expect(restored.useCount == 1)
        #expect(restored.lastUsedAt == Date(timeIntervalSince1970: 200))
    }

    private func makeFood(name: String) throws -> FoodItem {
        try FoodItem(
            name: name,
            category: .mixedMeal,
            nutrientsPer100Units: NutrientValues(
                energyKcal: 100,
                fatGrams: 2,
                saturatedFatGrams: 0.5,
                carbohydrateGrams: 10,
                sugarGrams: 1,
                proteinGrams: 10,
                saltGrams: 0.1,
                fibreGrams: 2
            ),
            source: "test"
        )
    }

    private func makeMeal(title: String, date: Date, foods: [FoodItem]) throws -> MealLog {
        try MealLog(
            eatenAt: date,
            title: title,
            entryMethod: .weighed,
            coverageStatus: .complete,
            components: try foods.map { try MealComponent(foodItem: $0, consumedWeightGrams: 100) }
        )
    }
}
