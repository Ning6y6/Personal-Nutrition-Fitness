import Foundation
import Testing

@testable import FoodDecisionCore

@Suite("Meal logging")
struct MealLoggingTests {
    @Test("A food item scales its per-100-gram nutrition into a component snapshot")
    func componentScalesNutrition() throws {
        let component = try MealComponent(foodItem: tomato, consumedWeightGrams: 250)

        #expect(component.consumedWeightGrams == 250)
        #expect(component.nutrients.energyKcal == 50)
        #expect(component.nutrients.proteinGrams == 2.5)
        #expect(component.nutrients.fibreGrams == 3.75)
    }

    @Test("A meal totals ordered components and derives evidence from its method")
    func mealTotalsComponents() throws {
        let tomatoComponent = try MealComponent(foodItem: tomato, consumedWeightGrams: 200)
        let eggComponent = try MealComponent(foodItem: egg, consumedWeightGrams: 100)

        let meal = try MealLog(
            title: "西红柿炒鸡蛋",
            entryMethod: .weighed,
            coverageStatus: .complete,
            components: [tomatoComponent, eggComponent]
        )

        #expect(meal.consumedWeightGrams == 300)
        #expect(meal.nutrients.energyKcal == 190)
        #expect(meal.nutrients.proteinGrams == 14)
        #expect(meal.estimateEvidenceGrade == .a)
        #expect(meal.components.map(\.foodName) == ["西红柿", "鸡蛋"])
    }

    @Test("Unknown fibre in one component keeps the meal fibre unknown")
    func mealPreservesUnknownFibre() throws {
        var unknownFibreFood = egg
        unknownFibreFood.nutrientsPer100Units.fibreGrams = nil

        let meal = try MealLog(
            title: "测试餐",
            entryMethod: .standardPortionEstimate,
            coverageStatus: .partial,
            components: [
                try MealComponent(foodItem: tomato, consumedWeightGrams: 100),
                try MealComponent(foodItem: unknownFibreFood, consumedWeightGrams: 100),
            ]
        )

        #expect(meal.nutrients.fibreGrams == nil)
        #expect(meal.estimateEvidenceGrade == .b)
    }

    @Test("Invalid meal inputs are rejected")
    func invalidInputsAreRejected() throws {
        #expect(throws: MealLoggingError.invalidWeight) {
            try MealComponent(foodItem: tomato, consumedWeightGrams: 0)
        }
        #expect(throws: MealLoggingError.emptyTitle) {
            try MealLog(
                title: "  ",
                entryMethod: .weighed,
                coverageStatus: .complete,
                components: [try MealComponent(foodItem: tomato, consumedWeightGrams: 100)]
            )
        }
        #expect(throws: MealLoggingError.emptyComponents) {
            try MealLog(
                title: "空餐",
                entryMethod: .weighed,
                coverageStatus: .complete,
                components: []
            )
        }
    }

    @Test("Meal logs support Codable round trips")
    func codableRoundTrip() throws {
        let meal = try MealLog(
            title: "西红柿",
            entryMethod: .standardPortionEstimate,
            coverageStatus: .complete,
            components: [try MealComponent(foodItem: tomato, consumedWeightGrams: 180)]
        )

        let encoded = try JSONEncoder().encode(meal)
        let decoded = try JSONDecoder().decode(MealLog.self, from: encoded)

        #expect(decoded == meal)
    }

    private var tomato: FoodItem {
        FoodItem(
            name: "西红柿",
            category: .mixedMeal,
            nutrientsPer100Units: NutrientValues(
                energyKcal: 20,
                fatGrams: 0.2,
                saturatedFatGrams: 0.05,
                carbohydrateGrams: 3,
                sugarGrams: 2.5,
                proteinGrams: 1,
                saltGrams: 0.01,
                fibreGrams: 1.5
            ),
            source: "test"
        )
    }

    private var egg: FoodItem {
        FoodItem(
            name: "鸡蛋",
            category: .proteinMain,
            nutrientsPer100Units: NutrientValues(
                energyKcal: 150,
                fatGrams: 10,
                saturatedFatGrams: 3,
                carbohydrateGrams: 1,
                sugarGrams: 0.5,
                proteinGrams: 12,
                saltGrams: 0.35,
                fibreGrams: 0
            ),
            source: "test"
        )
    }
}
