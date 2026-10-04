import FoodDecisionCore
import Foundation
import SwiftData
import Testing
@testable import FoodDecisionAssistant

@MainActor
@Suite("Saved meal validation for formal summaries")
struct MealReadValidationTests {
    @Test("Complete evidence C is included; draft D is excluded without changing the row")
    func confirmedPhotoAndDraftAreSeparate() throws {
        let container = try makeContainer()
        let confirmed = try persistentMeal(energy: 100, grade: .c)
        let draft = try persistentMeal(energy: 200)
        container.mainContext.insert(confirmed)
        container.mainContext.insert(draft)
        try container.mainContext.save()
        draft.estimateEvidenceGradeRawValue = EstimateEvidenceGrade.d.rawValue
        let result = MealReadValidation([confirmed, draft])
        #expect(result.meals.map(\.id) == [confirmed.id])
        #expect(result.meals.first?.isCompleteForDailyCoverage == true)
        #expect(result.draftRecordIDs == [draft.id])
        #expect(result.nutrients?.energyKcal == 100)
        #expect(draft.energyKcal == 200)
        #expect(draft.estimateEvidenceGradeRawValue == "d")
    }

    @Test("Invalid old values and unknown enums remain identifiable and unmodified")
    func rejectedHistoryIsPreserved() throws {
        let container = try makeContainer()
        let negative = try persistentMeal(energy: 100)
        container.mainContext.insert(negative)
        negative.energyKcal = -10
        let unknown = try persistentMeal(energy: 200)
        container.mainContext.insert(unknown)
        unknown.coverageStatusRawValue = "legacy_unknown"
        let result = MealReadValidation([negative, unknown])
        #expect(result.invalidRecordIDs == [negative.id, unknown.id])
        #expect(result.meals.isEmpty)
        #expect(negative.energyKcal == -10)
        #expect(unknown.coverageStatusRawValue == "legacy_unknown")
    }

    @Test("Overflow of individually finite meals is not presented as zero intake")
    func summaryOverflowIsUnavailable() throws {
        let container = try makeContainer()
        let first = try persistentMeal(energy: .greatestFiniteMagnitude)
        let second = try persistentMeal(energy: .greatestFiniteMagnitude)
        container.mainContext.insert(first)
        container.mainContext.insert(second)
        try container.mainContext.save()
        let result = MealReadValidation([first, second])
        #expect(result.meals.count == 2)
        #expect(result.invalidRecordIDs.isEmpty)
        #expect(result.nutrients == nil)
    }

    @Test("One invalid draft row rejects the entire set instead of saving a valid subset")
    func mixedDraftCannotPartiallySave() throws {
        let food = PersistentFoodItem(domain: try FoodItem(
            name: "虚构测试食物", category: .mixedMeal, nutrientsPer100Units: .zero, source: "test fixture"
        ))
        let good = MealEntryDraftComponent(foodItemID: food.id, weightGrams: 100)
        let missing = MealEntryDraftComponent(foodItemID: UUID(), weightGrams: 100)
        let infinite = MealEntryDraftComponent(foodItemID: food.id, weightGrams: .infinity)
        #expect(throws: MealDraftValidationError.unavailableFood) {
            try MealDraftValidation.components(from: [good, missing], foods: [food])
        }
        #expect(throws: (any Error).self) {
            try MealDraftValidation.components(from: [good, infinite], foods: [food])
        }
        #expect(try MealDraftValidation.components(from: [good], foods: [food]).count == 1)
    }

    private func persistentMeal(energy: Double, grade: EstimateEvidenceGrade = .a) throws -> PersistentMealLog {
        let nutrients = try NutrientValues(
            energyKcal: energy, fatGrams: 0, saturatedFatGrams: 0,
            carbohydrateGrams: 0, sugarGrams: 0, proteinGrams: 0, saltGrams: 0
        )
        let component = try MealComponent(
            foodItemID: UUID(), foodName: "虚构测试食物", consumedWeightGrams: 1, unit: "g", nutrients: nutrients
        )
        return PersistentMealLog(domain: try MealLog(
            title: "虚构测试餐", consumedWeightGrams: 1, nutrients: nutrients,
            coverageStatus: .complete, estimateEvidenceGrade: grade, components: [component]
        ))
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema(versionedSchema: VersionedSchemaV1.self)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, migrationPlan: ShiHengMigrationPlan.self, configurations: [configuration])
    }
}
