import FoodDecisionCore
import Foundation
import SwiftData

enum VersionedSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version {
        Schema.Version(1, 0, 0)
    }

    static var models: [any PersistentModel.Type] {
        [
            PersistentGoalProfile.self,
            PersistentFoodItem.self,
            PersistentContainerProfile.self,
            PersistentMealLog.self,
            PersistentMealComponent.self,
            PersistentReviewQueueItem.self,
            PersistentHealthKitSyncRecord.self,
            PersistentMealPhotoEstimate.self,
            PersistentMealPhotoComponent.self,
            PersistentPortionCalibration.self,
        ]
    }
}

@Model
final class PersistentGoalProfile {
    @Attribute(.unique) var id: UUID
    var effectiveFrom: Date
    var energyKcal: Double
    var proteinGrams: Double
    var carbohydrateGrams: Double
    var fatGrams: Double
    var saturatedFatLimitGrams: Double?
    var fibreGrams: Double?

    init(domain: GoalProfile) {
        id = domain.id
        effectiveFrom = domain.effectiveFrom
        energyKcal = domain.energyKcal
        proteinGrams = domain.proteinGrams
        carbohydrateGrams = domain.carbohydrateGrams
        fatGrams = domain.fatGrams
        saturatedFatLimitGrams = domain.saturatedFatLimitGrams
        fibreGrams = domain.fibreGrams
    }

    var domainModel: GoalProfile {
        GoalProfile(
            id: id,
            effectiveFrom: effectiveFrom,
            energyKcal: energyKcal,
            proteinGrams: proteinGrams,
            carbohydrateGrams: carbohydrateGrams,
            fatGrams: fatGrams,
            saturatedFatLimitGrams: saturatedFatLimitGrams,
            fibreGrams: fibreGrams
        )
    }

    func update(from domain: GoalProfile) {
        effectiveFrom = domain.effectiveFrom
        energyKcal = domain.energyKcal
        proteinGrams = domain.proteinGrams
        carbohydrateGrams = domain.carbohydrateGrams
        fatGrams = domain.fatGrams
        saturatedFatLimitGrams = domain.saturatedFatLimitGrams
        fibreGrams = domain.fibreGrams
    }
}

@Model
final class PersistentFoodItem {
    @Attribute(.unique) var id: UUID
    var name: String
    var categoryRawValue: String
    var energyKcalPer100Units: Double
    var fatGramsPer100Units: Double
    var saturatedFatGramsPer100Units: Double
    var carbohydrateGramsPer100Units: Double
    var sugarGramsPer100Units: Double
    var proteinGramsPer100Units: Double
    var saltGramsPer100Units: Double
    var fibreGramsPer100Units: Double?
    var unit: String
    var source: String

    init(domain: FoodItem) {
        id = domain.id
        name = domain.name
        categoryRawValue = domain.category.rawValue
        energyKcalPer100Units = domain.nutrientsPer100Units.energyKcal
        fatGramsPer100Units = domain.nutrientsPer100Units.fatGrams
        saturatedFatGramsPer100Units = domain.nutrientsPer100Units.saturatedFatGrams
        carbohydrateGramsPer100Units = domain.nutrientsPer100Units.carbohydrateGrams
        sugarGramsPer100Units = domain.nutrientsPer100Units.sugarGrams
        proteinGramsPer100Units = domain.nutrientsPer100Units.proteinGrams
        saltGramsPer100Units = domain.nutrientsPer100Units.saltGrams
        fibreGramsPer100Units = domain.nutrientsPer100Units.fibreGrams
        unit = domain.unit
        source = domain.source
    }

    var domainModel: FoodItem {
        FoodItem(
            id: id,
            name: name,
            category: FoodCategory(rawValue: categoryRawValue) ?? .mixedMeal,
            nutrientsPer100Units: nutrients,
            unit: unit,
            source: source
        )
    }

    private var nutrients: NutrientValues {
        NutrientValues(
            energyKcal: energyKcalPer100Units,
            fatGrams: fatGramsPer100Units,
            saturatedFatGrams: saturatedFatGramsPer100Units,
            carbohydrateGrams: carbohydrateGramsPer100Units,
            sugarGrams: sugarGramsPer100Units,
            proteinGrams: proteinGramsPer100Units,
            saltGrams: saltGramsPer100Units,
            fibreGrams: fibreGramsPer100Units
        )
    }
}

@Model
final class PersistentContainerProfile {
    @Attribute(.unique) var id: UUID
    var name: String
    var tareWeightGrams: Double

    init(domain: ContainerProfile) {
        id = domain.id
        name = domain.name
        tareWeightGrams = domain.tareWeightGrams
    }

    var domainModel: ContainerProfile {
        ContainerProfile(id: id, name: name, tareWeightGrams: tareWeightGrams)
    }
}

@Model
final class PersistentMealLog {
    @Attribute(.unique) var id: UUID
    var eatenAt: Date
    var title: String
    var consumedWeightGrams: Double
    var energyKcal: Double
    var fatGrams: Double
    var saturatedFatGrams: Double
    var carbohydrateGrams: Double
    var sugarGrams: Double
    var proteinGrams: Double
    var saltGrams: Double
    var fibreGrams: Double?
    var entryMethodRawValue: String
    var coverageStatusRawValue: String
    var estimateEvidenceGradeRawValue: String
    var healthKitSyncVersion: Int
    @Relationship(deleteRule: .cascade, inverse: \PersistentMealComponent.meal)
    var components: [PersistentMealComponent]

    init(domain: MealLog) {
        id = domain.id
        eatenAt = domain.eatenAt
        title = domain.title
        consumedWeightGrams = domain.consumedWeightGrams
        energyKcal = domain.nutrients.energyKcal
        fatGrams = domain.nutrients.fatGrams
        saturatedFatGrams = domain.nutrients.saturatedFatGrams
        carbohydrateGrams = domain.nutrients.carbohydrateGrams
        sugarGrams = domain.nutrients.sugarGrams
        proteinGrams = domain.nutrients.proteinGrams
        saltGrams = domain.nutrients.saltGrams
        fibreGrams = domain.nutrients.fibreGrams
        entryMethodRawValue = domain.entryMethod.rawValue
        coverageStatusRawValue = domain.coverageStatus.rawValue
        estimateEvidenceGradeRawValue = domain.estimateEvidenceGrade.rawValue
        healthKitSyncVersion = domain.healthKitSyncVersion
        components = domain.components.enumerated().map {
            PersistentMealComponent(domain: $0.element, sortIndex: $0.offset)
        }

        for component in components {
            component.meal = self
        }
    }

    func domainModel() throws -> MealLog {
        MealLog(
            id: id,
            eatenAt: eatenAt,
            title: title,
            consumedWeightGrams: consumedWeightGrams,
            nutrients: nutrientSnapshot,
            entryMethod: MealEntryMethod(rawValue: entryMethodRawValue) ?? .weighed,
            coverageStatus: MealCoverageStatus(rawValue: coverageStatusRawValue) ?? .incomplete,
            estimateEvidenceGrade: EstimateEvidenceGrade(rawValue: estimateEvidenceGradeRawValue) ?? .d,
            healthKitSyncVersion: healthKitSyncVersion,
            components: try components
                .sorted { $0.sortIndex < $1.sortIndex }
                .map { try $0.domainModel() }
        )
    }

    var nutrientSnapshot: NutrientValues {
        NutrientValues(
            energyKcal: energyKcal,
            fatGrams: fatGrams,
            saturatedFatGrams: saturatedFatGrams,
            carbohydrateGrams: carbohydrateGrams,
            sugarGrams: sugarGrams,
            proteinGrams: proteinGrams,
            saltGrams: saltGrams,
            fibreGrams: fibreGrams
        )
    }

    func update(from domain: MealLog, in modelContext: ModelContext) {
        precondition(id == domain.id, "A persisted meal can only be updated from the same meal ID.")

        eatenAt = domain.eatenAt
        title = domain.title
        consumedWeightGrams = domain.consumedWeightGrams
        energyKcal = domain.nutrients.energyKcal
        fatGrams = domain.nutrients.fatGrams
        saturatedFatGrams = domain.nutrients.saturatedFatGrams
        carbohydrateGrams = domain.nutrients.carbohydrateGrams
        sugarGrams = domain.nutrients.sugarGrams
        proteinGrams = domain.nutrients.proteinGrams
        saltGrams = domain.nutrients.saltGrams
        fibreGrams = domain.nutrients.fibreGrams
        entryMethodRawValue = domain.entryMethod.rawValue
        coverageStatusRawValue = domain.coverageStatus.rawValue
        estimateEvidenceGradeRawValue = domain.estimateEvidenceGrade.rawValue
        healthKitSyncVersion = domain.healthKitSyncVersion

        let previousComponents = components
        components = []
        for component in previousComponents {
            modelContext.delete(component)
        }

        components = domain.components.enumerated().map {
            let component = PersistentMealComponent(domain: $0.element, sortIndex: $0.offset)
            component.meal = self
            modelContext.insert(component)
            return component
        }
    }
}

@Model
final class PersistentMealComponent {
    @Attribute(.unique) var id: UUID
    var foodItemID: UUID
    var foodName: String
    var consumedWeightGrams: Double
    var unit: String
    var energyKcal: Double
    var fatGrams: Double
    var saturatedFatGrams: Double
    var carbohydrateGrams: Double
    var sugarGrams: Double
    var proteinGrams: Double
    var saltGrams: Double
    var fibreGrams: Double?
    var sortIndex: Int
    var meal: PersistentMealLog?

    init(domain: MealComponent, sortIndex: Int = 0) {
        id = domain.id
        foodItemID = domain.foodItemID
        foodName = domain.foodName
        consumedWeightGrams = domain.consumedWeightGrams
        unit = domain.unit
        energyKcal = domain.nutrients.energyKcal
        fatGrams = domain.nutrients.fatGrams
        saturatedFatGrams = domain.nutrients.saturatedFatGrams
        carbohydrateGrams = domain.nutrients.carbohydrateGrams
        sugarGrams = domain.nutrients.sugarGrams
        proteinGrams = domain.nutrients.proteinGrams
        saltGrams = domain.nutrients.saltGrams
        fibreGrams = domain.nutrients.fibreGrams
        self.sortIndex = sortIndex
    }

    func domainModel() throws -> MealComponent {
        try MealComponent(
            id: id,
            foodItemID: foodItemID,
            foodName: foodName,
            consumedWeightGrams: consumedWeightGrams,
            unit: unit,
            nutrients: NutrientValues(
                energyKcal: energyKcal,
                fatGrams: fatGrams,
                saturatedFatGrams: saturatedFatGrams,
                carbohydrateGrams: carbohydrateGrams,
                sugarGrams: sugarGrams,
                proteinGrams: proteinGrams,
                saltGrams: saltGrams,
                fibreGrams: fibreGrams
            )
        )
    }
}

@Model
final class PersistentReviewQueueItem {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var sourceImageIdentifier: String?
    var missingFields: [String]
    var statusRawValue: String

    init(domain: ReviewQueueItem) {
        id = domain.id
        createdAt = domain.createdAt
        sourceImageIdentifier = domain.sourceImageIdentifier
        missingFields = domain.missingFields
        statusRawValue = domain.status.rawValue
    }

    var domainModel: ReviewQueueItem {
        ReviewQueueItem(
            id: id,
            createdAt: createdAt,
            sourceImageIdentifier: sourceImageIdentifier,
            missingFields: missingFields,
            status: ReviewStatus(rawValue: statusRawValue) ?? .pending
        )
    }
}

@Model
final class PersistentHealthKitSyncRecord {
    @Attribute(.unique) var id: UUID
    var mealID: UUID
    var objectTypeRawValue: String
    var syncIdentifier: String
    var syncVersion: Int
    var healthKitUUID: UUID?
    var isDeleted: Bool

    init(domain: HealthKitSyncRecord) {
        id = domain.id
        mealID = domain.mealID
        objectTypeRawValue = domain.objectType.rawValue
        syncIdentifier = domain.syncIdentifier
        syncVersion = domain.syncVersion
        healthKitUUID = domain.healthKitUUID
        isDeleted = domain.isDeleted
    }

    var domainModel: HealthKitSyncRecord {
        HealthKitSyncRecord(
            id: id,
            mealID: mealID,
            objectType: HealthKitObjectType(rawValue: objectTypeRawValue) ?? .correlation,
            syncIdentifier: syncIdentifier,
            syncVersion: syncVersion,
            healthKitUUID: healthKitUUID,
            isDeleted: isDeleted
        )
    }
}

@Model
final class PersistentMealPhotoEstimate {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var mealTitle: String
    var imageReference: String
    var providerName: String
    var modelVersion: String
    var outputSchemaVersion: String
    var confirmationStatusRawValue: String
    var consumedShareRatio: Double
    @Relationship(deleteRule: .cascade, inverse: \PersistentMealPhotoComponent.estimate)
    var components: [PersistentMealPhotoComponent]
    @Relationship(deleteRule: .cascade, inverse: \PersistentPortionCalibration.estimate)
    var calibrations: [PersistentPortionCalibration]

    init(domain: MealPhotoEstimate) {
        id = domain.id
        createdAt = domain.createdAt
        mealTitle = domain.mealTitle
        imageReference = domain.imageReference
        providerName = domain.providerName
        modelVersion = domain.modelVersion
        outputSchemaVersion = domain.outputSchemaVersion
        confirmationStatusRawValue = domain.confirmationStatus.rawValue
        consumedShareRatio = domain.consumedShareRatio
        components = domain.components.enumerated().map {
            PersistentMealPhotoComponent(domain: $0.element, sortIndex: $0.offset)
        }
        calibrations = domain.calibrations.enumerated().map {
            PersistentPortionCalibration(domain: $0.element, sortIndex: $0.offset)
        }

        for component in components {
            component.estimate = self
        }
        for calibration in calibrations {
            calibration.estimate = self
        }
    }

    func domainModel() throws -> MealPhotoEstimate {
        try MealPhotoEstimate(
            id: id,
            createdAt: createdAt,
            mealTitle: mealTitle,
            imageReference: imageReference,
            providerName: providerName,
            modelVersion: modelVersion,
            outputSchemaVersion: outputSchemaVersion,
            confirmationStatus: EstimateConfirmationStatus(rawValue: confirmationStatusRawValue) ?? .failed,
            consumedShareRatio: consumedShareRatio,
            components: try components
                .sorted { $0.sortIndex < $1.sortIndex }
                .map { try $0.domainModel() },
            calibrations: try calibrations
                .sorted { $0.sortIndex < $1.sortIndex }
                .map { try $0.domainModel() }
        )
    }
}

@Model
final class PersistentMealPhotoComponent {
    @Attribute(.unique) var id: UUID
    var foodItemID: UUID?
    var templateID: String?
    var freeTextName: String
    var cookingMethodRawValue: String
    var lowGrams: Double
    var midpointGrams: Double
    var highGrams: Double
    var confidence: Double
    var isHiddenOilOrSauce: Bool
    var userCorrectedWeightGrams: Double?
    var sortIndex: Int
    var estimate: PersistentMealPhotoEstimate?

    init(domain: MealPhotoComponent, sortIndex: Int = 0) {
        id = domain.id
        foodItemID = domain.foodItemID
        templateID = domain.templateID
        freeTextName = domain.freeTextName
        cookingMethodRawValue = domain.cookingMethod.rawValue
        lowGrams = domain.portionRange.lowGrams
        midpointGrams = domain.portionRange.midpointGrams
        highGrams = domain.portionRange.highGrams
        confidence = domain.confidence
        isHiddenOilOrSauce = domain.isHiddenOilOrSauce
        userCorrectedWeightGrams = domain.userCorrectedWeightGrams
        self.sortIndex = sortIndex
    }

    func domainModel() throws -> MealPhotoComponent {
        try MealPhotoComponent(
            id: id,
            foodItemID: foodItemID,
            templateID: templateID,
            freeTextName: freeTextName,
            cookingMethod: CookingMethod(rawValue: cookingMethodRawValue) ?? .unknown,
            portionRange: try PortionEstimateRange(
                lowGrams: lowGrams,
                midpointGrams: midpointGrams,
                highGrams: highGrams
            ),
            confidence: confidence,
            isHiddenOilOrSauce: isHiddenOilOrSauce,
            userCorrectedWeightGrams: userCorrectedWeightGrams
        )
    }
}

@Model
final class PersistentPortionCalibration {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var photoEstimateID: UUID
    var componentID: UUID?
    var estimatedWeightGrams: Double
    var actualWeightGrams: Double
    var sortIndex: Int
    var estimate: PersistentMealPhotoEstimate?

    init(domain: PortionCalibration, sortIndex: Int = 0) {
        id = domain.id
        createdAt = domain.createdAt
        photoEstimateID = domain.photoEstimateID
        componentID = domain.componentID
        estimatedWeightGrams = domain.estimatedWeightGrams
        actualWeightGrams = domain.actualWeightGrams
        self.sortIndex = sortIndex
    }

    func domainModel() throws -> PortionCalibration {
        try PortionCalibration(
            id: id,
            createdAt: createdAt,
            photoEstimateID: photoEstimateID,
            componentID: componentID,
            estimatedWeightGrams: estimatedWeightGrams,
            actualWeightGrams: actualWeightGrams
        )
    }
}
