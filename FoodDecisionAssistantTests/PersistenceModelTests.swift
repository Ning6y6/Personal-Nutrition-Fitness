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
        let tomato = FoodItem(
            name: "西红柿",
            category: .mixedMeal,
            nutrientsPer100Units: makeNutrients(),
            source: "test"
        )
        let egg = FoodItem(
            name: "鸡蛋",
            category: .proteinMain,
            nutrientsPer100Units: makeNutrients(),
            source: "test"
        )
        let meal = try MealLog(
            title: "Photo-estimated dinner",
            entryMethod: .standardPortionEstimate,
            coverageStatus: .complete,
            components: [
                try MealComponent(foodItem: tomato, consumedWeightGrams: 220),
                try MealComponent(foodItem: egg, consumedWeightGrams: 100),
            ]
        )

        context.insert(PersistentMealLog(domain: meal))
        try context.save()

        let savedMeals = try context.fetch(FetchDescriptor<PersistentMealLog>())
        let restored = try #require(savedMeals.first).domainModel()

        #expect(restored.coverageStatus == .complete)
        #expect(restored.estimateEvidenceGrade == .b)
        #expect(restored.entryMethod == .standardPortionEstimate)
        #expect(restored.isCompleteForDailyCoverage == true)
        #expect(restored.components.map(\.foodName) == ["西红柿", "鸡蛋"])
        #expect(restored.components.map(\.consumedWeightGrams) == [220, 100])
        #expect(restored.components[0].nutrients == meal.components[0].nutrients)
    }

    @Test("The version-one schema includes all current persistent entities")
    func versionOneSchemaIncludesAllEntities() {
        #expect(VersionedSchemaV1.models.count == 12)
    }

    @Test("A personal meal template persists its ordered components and round trips")
    func mealTemplatePersistsAndRoundTrips() throws {
        let context = try makeContext()
        let firstFood = makeFood(name: "西红柿", energyKcal: 20, proteinGrams: 1)
        let secondFood = makeFood(name: "鸡蛋", energyKcal: 150, proteinGrams: 12)
        let template = try MealTemplate(
            id: UUID(),
            name: "西红柿炒鸡蛋",
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 200),
            components: [
                try MealTemplateComponent(
                    foodItemID: firstFood.id,
                    foodName: firstFood.name,
                    defaultWeightGrams: 220
                ),
                try MealTemplateComponent(
                    foodItemID: secondFood.id,
                    foodName: secondFood.name,
                    defaultWeightGrams: 100
                ),
            ]
        )

        context.insert(PersistentMealTemplate(domain: template))
        try context.save()

        let saved = try #require(
            context.fetch(FetchDescriptor<PersistentMealTemplate>()).first
        )
        let restored = try saved.domainModel()

        #expect(restored == template)
        #expect(restored.components.map(\.foodName) == ["西红柿", "鸡蛋"])
        #expect(restored.components.map(\.defaultWeightGrams) == [220, 100])
    }

    @Test("Updating a template replaces obsolete components")
    func templateUpdateReplacesComponents() throws {
        let context = try makeContext()
        let originalFood = makeFood(name: "原食物", energyKcal: 100, proteinGrams: 5)
        let replacementFood = makeFood(name: "替换食物", energyKcal: 200, proteinGrams: 20)
        let original = try MealTemplate(
            name: "原模板",
            components: [
                try MealTemplateComponent(
                    foodItemID: originalFood.id,
                    foodName: originalFood.name,
                    defaultWeightGrams: 100
                ),
            ]
        )
        let persistentTemplate = PersistentMealTemplate(domain: original)
        context.insert(persistentTemplate)
        try context.save()
        let obsoleteID = try #require(persistentTemplate.components.first).id
        let updated = try MealTemplate(
            id: original.id,
            name: "新模板",
            createdAt: original.createdAt,
            updatedAt: Date(timeIntervalSince1970: 300),
            components: [
                try MealTemplateComponent(
                    foodItemID: replacementFood.id,
                    foodName: replacementFood.name,
                    defaultWeightGrams: 160
                ),
            ]
        )

        persistentTemplate.update(from: updated, in: context)
        try context.save()

        let restored = try persistentTemplate.domainModel()
        let savedComponents = try context.fetch(
            FetchDescriptor<PersistentMealTemplateComponent>()
        )
        #expect(restored == updated)
        #expect(savedComponents.count == 1)
        #expect(!savedComponents.contains { $0.id == obsoleteID })
    }

    @Test("Deleting a template cascades its components without deleting meal history")
    func templateDeletionDoesNotAffectHistory() throws {
        let context = try makeContext()
        let food = makeFood(name: "豆腐", energyKcal: 80, proteinGrams: 8)
        let meal = try MealLog(
            title: "豆腐餐",
            entryMethod: .weighed,
            coverageStatus: .complete,
            components: [try MealComponent(foodItem: food, consumedWeightGrams: 200)]
        )
        let template = try MealTemplate(meal: meal)
        let persistentTemplate = PersistentMealTemplate(domain: template)
        context.insert(PersistentMealLog(domain: meal))
        context.insert(persistentTemplate)
        try context.save()

        context.delete(persistentTemplate)
        try context.save()

        #expect(try context.fetch(FetchDescriptor<PersistentMealTemplate>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<PersistentMealTemplateComponent>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<PersistentMealLog>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<PersistentMealComponent>()).count == 1)
    }

    @Test("Template usage metadata changes only when explicitly marked used")
    func templateUsageRequiresExplicitMark() throws {
        let context = try makeContext()
        let food = makeFood(name: "米饭", energyKcal: 130, proteinGrams: 3)
        let template = try MealTemplate(
            name: "米饭",
            components: [
                try MealTemplateComponent(
                    foodItemID: food.id,
                    foodName: food.name,
                    defaultWeightGrams: 180
                ),
            ]
        )
        let persistentTemplate = PersistentMealTemplate(domain: template)
        context.insert(persistentTemplate)
        try context.save()

        #expect(persistentTemplate.useCount == 0)
        #expect(persistentTemplate.lastUsedAt == nil)

        let usedAt = Date(timeIntervalSince1970: 400)
        persistentTemplate.markUsed(at: usedAt)
        try context.save()

        #expect(persistentTemplate.useCount == 1)
        #expect(persistentTemplate.lastUsedAt == usedAt)
    }

    @Test("The personal seed food import is deterministic and idempotent")
    func seedFoodImportIsIdempotent() throws {
        let context = try makeContext()
        let deprecatedFoodID = try #require(
            UUID(uuidString: "20000000-0000-4000-8000-000000018521")
        )
        context.insert(
            PersistentFoodItem(
                domain: FoodItem(
                    id: deprecatedFoodID,
                    name: "Deprecated seed",
                    category: .proteinMain,
                    nutrientsPer100Units: makeNutrients(),
                    source: "legacy"
                )
            )
        )
        try context.save()

        let firstImportCount = try SeedFoodCatalog.importIfNeeded(into: context)
        let secondImportCount = try SeedFoodCatalog.importIfNeeded(into: context)
        let foods = try context.fetch(
            FetchDescriptor<PersistentFoodItem>(sortBy: [SortDescriptor(\.name)])
        )

        #expect(firstImportCount == 12)
        #expect(secondImportCount == 0)
        #expect(foods.count == 12)
        #expect(!foods.contains { $0.id == deprecatedFoodID })
        #expect(foods.contains { $0.name == "西红柿（生）" })
        #expect(foods.contains { $0.name == "鸡胸肉（去皮烤熟）" })
        #expect(foods.allSatisfy { $0.source.contains("CoFID 2021") })
    }

    @Test("Editing a meal replaces its snapshot and removes obsolete components")
    func mealEditReplacesSnapshotAndComponents() throws {
        let context = try makeContext()
        let originalFood = makeFood(name: "原食物", energyKcal: 100, proteinGrams: 5)
        let replacementFood = makeFood(name: "替换食物", energyKcal: 200, proteinGrams: 20)
        let original = try MealLog(
            title: "原餐食",
            entryMethod: .weighed,
            coverageStatus: .complete,
            components: [try MealComponent(foodItem: originalFood, consumedWeightGrams: 100)]
        )
        let persistentMeal = PersistentMealLog(domain: original)
        context.insert(persistentMeal)
        try context.save()

        let obsoleteComponentID = try #require(persistentMeal.components.first).id
        let updated = try MealLog(
            id: original.id,
            eatenAt: original.eatenAt,
            title: "修改后的餐食",
            entryMethod: .standardPortionEstimate,
            coverageStatus: .partial,
            components: [try MealComponent(foodItem: replacementFood, consumedWeightGrams: 150)]
        )

        persistentMeal.update(from: updated, in: context)
        try context.save()

        let restored = try #require(
            context.fetch(FetchDescriptor<PersistentMealLog>()).first
        ).domainModel()
        let savedComponents = try context.fetch(FetchDescriptor<PersistentMealComponent>())

        #expect(restored == updated)
        #expect(savedComponents.count == 1)
        #expect(!savedComponents.contains { $0.id == obsoleteComponentID })
        #expect(savedComponents.first?.foodName == "替换食物")
    }

    @Test("Deleting a meal cascades to all component snapshots")
    func mealDeletionCascadesToComponents() throws {
        let context = try makeContext()
        let food = makeFood(name: "测试食物", energyKcal: 120, proteinGrams: 8)
        let meal = try MealLog(
            title: "待删除餐食",
            entryMethod: .weighed,
            coverageStatus: .complete,
            components: [
                try MealComponent(foodItem: food, consumedWeightGrams: 100),
                try MealComponent(foodItem: food, consumedWeightGrams: 50),
            ]
        )
        let persistentMeal = PersistentMealLog(domain: meal)
        context.insert(persistentMeal)
        try context.save()

        context.delete(persistentMeal)
        try context.save()

        #expect(try context.fetch(FetchDescriptor<PersistentMealLog>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<PersistentMealComponent>()).isEmpty)
    }

    @Test("Today's nutrition recomputes from edited and deleted persisted meals")
    func todayNutritionRecomputesAfterMutations() throws {
        let context = try makeContext()
        let food = makeFood(name: "测试食物", energyKcal: 100, proteinGrams: 10)
        let first = try MealLog(
            eatenAt: .now,
            title: "第一餐",
            entryMethod: .weighed,
            coverageStatus: .complete,
            components: [try MealComponent(foodItem: food, consumedWeightGrams: 100)]
        )
        let second = try MealLog(
            eatenAt: .now,
            title: "第二餐",
            entryMethod: .weighed,
            coverageStatus: .complete,
            components: [try MealComponent(foodItem: food, consumedWeightGrams: 200)]
        )
        let firstPersistent = PersistentMealLog(domain: first)
        let secondPersistent = PersistentMealLog(domain: second)
        context.insert(firstPersistent)
        context.insert(secondPersistent)
        try context.save()

        #expect(try todayNutrients(in: context).energyKcal == 300)

        let editedFirst = try MealLog(
            id: first.id,
            eatenAt: first.eatenAt,
            title: first.title,
            entryMethod: .weighed,
            coverageStatus: .complete,
            components: [try MealComponent(foodItem: food, consumedWeightGrams: 50)]
        )
        firstPersistent.update(from: editedFirst, in: context)
        try context.save()

        #expect(try todayNutrients(in: context).energyKcal == 250)

        let yesterday = try #require(Calendar.current.date(byAdding: .day, value: -1, to: .now))
        let movedFirst = try MealLog(
            id: first.id,
            eatenAt: yesterday,
            title: first.title,
            entryMethod: .weighed,
            coverageStatus: .complete,
            components: [try MealComponent(foodItem: food, consumedWeightGrams: 50)]
        )
        firstPersistent.update(from: movedFirst, in: context)
        try context.save()

        #expect(try todayNutrients(in: context).energyKcal == 200)

        context.delete(secondPersistent)
        try context.save()

        let finalNutrients = try todayNutrients(in: context)
        #expect(finalNutrients.energyKcal == 0)
        #expect(finalNutrients.proteinGrams == 0)
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

    private func makeFood(
        name: String,
        energyKcal: Double,
        proteinGrams: Double
    ) -> FoodItem {
        FoodItem(
            name: name,
            category: .mixedMeal,
            nutrientsPer100Units: NutrientValues(
                energyKcal: energyKcal,
                fatGrams: 1,
                saturatedFatGrams: 0.2,
                carbohydrateGrams: 10,
                sugarGrams: 2,
                proteinGrams: proteinGrams,
                saltGrams: 0.1,
                fibreGrams: 1
            ),
            source: "test"
        )
    }

    private func todayNutrients(in context: ModelContext) throws -> NutrientValues {
        let meals = try context.fetch(FetchDescriptor<PersistentMealLog>())
            .filter { Calendar.current.isDateInToday($0.eatenAt) }
        return NutrientValues.sum(meals.map(\.nutrientSnapshot))
    }
}
