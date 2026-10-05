import FoodDecisionCore
import Foundation
import SwiftData
import Testing
@testable import FoodDecisionAssistant

@MainActor
struct TodayMealSummaryTests {
    @Test("Midnight and backward clock changes regroup saved meals without changing their timestamps")
    func crossingDaysRecomputesSavedSummary() throws {
        let container = try makeContainer()
        let oldMeal = try makeMeal(at: "2026-10-04T14:25:00Z", energy: 634)
        let newMeal = try makeMeal(at: "2026-10-04T23:00:00Z", energy: 200)
        container.mainContext.insert(oldMeal)
        container.mainContext.insert(newMeal)
        try container.mainContext.save()
        let saved = try readMeals(container)
        var now = try date("2026-10-04T22:59:59Z")
        let calendar = try calendar(in: "Europe/London")
        let context = TodayDateContext(now: { now }, calendar: { calendar })
        let before = summary(saved, window: try #require(context.dayWindow))
        #expect(before.meals.map(\.id) == [oldMeal.id])
        #expect(before.nutrients?.energyKcal == 634)

        now = try date("2026-10-04T23:00:00Z")
        context.refresh()
        let after = summary(saved, window: try #require(context.dayWindow))
        #expect(after.meals.map(\.id) == [newMeal.id])
        #expect(after.nutrients?.energyKcal == 200)

        now = try date("2026-10-04T22:59:59Z")
        context.refresh()
        #expect(summary(saved, window: try #require(context.dayWindow)).nutrients?.energyKcal == 634)
        let fresh = try readMeals(container)
        #expect(Set(fresh.map(\.id)) == Set([oldMeal.id, newMeal.id]))
        #expect(fresh.map(\.eatenAt) == saved.map(\.eatenAt))
        #expect(fresh.map(\.energyKcal) == saved.map(\.energyKcal))
    }

    @Test("The new day is neutral and empty while yesterday remains in history")
    func midnightWithNoNewMealsIsNotConfirmedZero() throws {
        let container = try makeContainer()
        let yesterday = try makeMeal(at: "2026-10-04T14:25:00Z", energy: 634)
        container.mainContext.insert(yesterday)
        try container.mainContext.save()
        let saved = try readMeals(container)
        let window = try MealDayWindow(containing: date("2026-10-05T12:00:00Z"), calendar: calendar(in: "Europe/London"))
        let today = summary(saved, window: window)
        #expect(today.availability == .noRecords)
        #expect(today.availability.canShowNutritionProgress == false)
        #expect(today.meals.isEmpty)
        #expect(try readMeals(container).first?.id == yesterday.id)
        #expect(try readMeals(container).first?.energyKcal == 634)
    }

    @Test("Changing timezones reassigns local day membership but does not rewrite the stored date")
    func timezoneChangeRecomputesSummary() throws {
        let container = try makeContainer()
        let meal = try makeMeal(at: "2026-10-04T14:25:00Z", energy: 634)
        container.mainContext.insert(meal)
        try container.mainContext.save()
        let saved = try readMeals(container)
        let now = try date("2026-10-04T23:30:00Z")
        var calendar = try calendar(in: "Europe/London")
        let context = TodayDateContext(now: { now }, calendar: { calendar })
        #expect(summary(saved, window: try #require(context.dayWindow)).availability == .noRecords)
        calendar = try self.calendar(in: "America/New_York")
        context.refresh()
        let changed = summary(saved, window: try #require(context.dayWindow))
        #expect(changed.meals.map(\.id) == [meal.id])
        #expect(changed.nutrients?.energyKcal == 634)
        #expect(try readMeals(container).first?.eatenAt == meal.eatenAt)
    }

    private func summary(_ records: [PersistentMealLog], window: MealDayWindow) -> MealReadValidation {
        MealReadValidation(MealReadValidation.records(in: window, from: records))
    }

    private func readMeals(_ container: ModelContainer) throws -> [PersistentMealLog] {
        let reader = ModelContext(container)
        reader.autosaveEnabled = false
        return try reader.fetch(FetchDescriptor<PersistentMealLog>(sortBy: [SortDescriptor(\.eatenAt)]))
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema(versionedSchema: VersionedSchemaV1.self)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, migrationPlan: ShiHengMigrationPlan.self, configurations: [config])
    }

    private func makeMeal(at text: String, energy: Double) throws -> PersistentMealLog {
        let values = try NutrientValues(energyKcal: energy, fatGrams: 0, saturatedFatGrams: 0, carbohydrateGrams: 0, sugarGrams: 0, proteinGrams: 0, saltGrams: 0)
        let component = try MealComponent(foodItemID: UUID(), foodName: "synthetic fixture", consumedWeightGrams: 1, unit: "g", nutrients: values)
        return PersistentMealLog(domain: try MealLog(eatenAt: date(text), title: "synthetic meal", consumedWeightGrams: 1, nutrients: values, coverageStatus: .complete, estimateEvidenceGrade: .a, components: [component]))
    }

    private func calendar(in zone: String) throws -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: zone))
        return calendar
    }

    private func date(_ value: String) throws -> Date {
        try #require(ISO8601DateFormatter().date(from: value))
    }
}
