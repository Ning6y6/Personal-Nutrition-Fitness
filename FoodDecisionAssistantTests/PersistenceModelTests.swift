import FoodDecisionCore
import Foundation
import SwiftData
import Testing

@testable import FoodDecisionAssistant

@Suite("SwiftData persistence")
struct PersistenceModelTests {
    @Test("A saved goal can be fetched and converted back to its domain model")
    func goalProfilePersistsAndRoundTrips() throws {
        let context = try makeContext()
        let goal = GoalProfile(
            id: UUID(),
            effectiveFrom: Date(timeIntervalSince1970: 1_700_000_000),
            energyKcal: 2_100,
            proteinGrams: 150,
            carbohydrateGrams: 220,
            fatGrams: 65,
            saturatedFatLimitGrams: 18,
            fibreGrams: 32
        )

        context.insert(PersistentGoalProfile(domain: goal))
        try context.save()

        let savedGoals = try context.fetch(FetchDescriptor<PersistentGoalProfile>())

        #expect(savedGoals.count == 1)
        #expect(savedGoals.first?.domainModel == goal)
    }

    @Test("A photo estimate persists its components and domain conversion")
    func mealPhotoEstimatePersistsAndRoundTrips() throws {
        let context = try makeContext()
        let estimate = try makePhotoEstimate()

        context.insert(PersistentMealPhotoEstimate(domain: estimate))
        try context.save()

        let savedEstimates = try context.fetch(FetchDescriptor<PersistentMealPhotoEstimate>())
        let restored = try #require(savedEstimates.first).domainModel()

        #expect(savedEstimates.count == 1)
        #expect(restored.components.count == 2)
        #expect(restored.components[1].isHiddenOilOrSauce)
        #expect(restored.imageReference == "sha256:meal")
        #expect(restored.providerName == "fixture")
        #expect(restored == estimate)
    }

    @Test("A portion calibration persists and converts back to the domain model")
    func portionCalibrationPersistsAndRoundTrips() throws {
        let context = try makeContext()
        let calibration = try PortionCalibration(
            photoEstimateID: UUID(),
            componentID: UUID(),
            estimatedWeightGrams: 200,
            actualWeightGrams: 185
        )

        context.insert(PersistentPortionCalibration(domain: calibration))
        try context.save()

        let savedCalibrations = try context.fetch(FetchDescriptor<PersistentPortionCalibration>())

        let restored = try #require(savedCalibrations.first).domainModel()

        #expect(savedCalibrations.count == 1)
        #expect(restored == calibration)
    }

    @Test("Meal coverage and evidence grade persist independently")
    func mealLogCoverageAndEvidencePersistAndRoundTrip() throws {
        let context = try makeContext()
        let meal = MealLog(
            title: "Photo-estimated dinner",
            consumedWeightGrams: 420,
            nutrients: makeNutrients(),
            coverageStatus: .complete,
            estimateEvidenceGrade: .c
        )

        context.insert(PersistentMealLog(domain: meal))
        try context.save()

        let savedMeals = try context.fetch(FetchDescriptor<PersistentMealLog>())

        #expect(savedMeals.first?.domainModel.coverageStatus == .complete)
        #expect(savedMeals.first?.domainModel.estimateEvidenceGrade == .c)
        #expect(savedMeals.first?.domainModel.isCompleteForDailyCoverage == true)
    }

    @Test("The version-one schema includes all current persistent entities")
    func versionOneSchemaIncludesAllEntities() {
        #expect(VersionedSchemaV1.models.count == 9)
    }

    private func makeContext() throws -> ModelContext {
        let schema = Schema(versionedSchema: VersionedSchemaV1.self)
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        return ModelContext(try ModelContainer(for: schema, configurations: configuration))
    }

    private func makePhotoEstimate() throws -> MealPhotoEstimate {
        let estimateID = UUID()
        let chicken = try MealPhotoComponent(
            foodItemID: UUID(),
            freeTextName: "Grilled chicken",
            cookingMethod: .grilled,
            portionRange: try PortionEstimateRange(
                lowGrams: 160,
                midpointGrams: 200,
                highGrams: 240
            ),
            confidence: 0.9,
            userCorrectedWeightGrams: 190
        )
        let oil = try MealPhotoComponent(
            freeTextName: "Cooking oil",
            cookingMethod: .stirFried,
            portionRange: try PortionEstimateRange(
                lowGrams: 8,
                midpointGrams: 12,
                highGrams: 18
            ),
            confidence: 0.6,
            isHiddenOilOrSauce: true
        )
        let calibration = try PortionCalibration(
            photoEstimateID: estimateID,
            componentID: chicken.id,
            estimatedWeightGrams: 200,
            actualWeightGrams: 190
        )

        return try MealPhotoEstimate(
            id: estimateID,
            mealTitle: "Chicken rice",
            imageReference: "sha256:meal",
            providerName: "fixture",
            modelVersion: "fixture-1.0",
            outputSchemaVersion: "meal-vision-v1",
            confirmationStatus: .confirmed,
            consumedShareRatio: 0.5,
            components: [chicken, oil],
            calibrations: [calibration]
        )
    }

    private func makeNutrients() -> NutrientValues {
        NutrientValues(
            energyKcal: 600,
            fatGrams: 20,
            saturatedFatGrams: 5,
            carbohydrateGrams: 70,
            sugarGrams: 8,
            proteinGrams: 45,
            saltGrams: 1.2,
            fibreGrams: 9
        )
    }
}
