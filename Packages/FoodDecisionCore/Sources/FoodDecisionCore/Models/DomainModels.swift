import Foundation

public struct GoalProfile: Codable, Identifiable, Sendable, Equatable {
    public var id: UUID
    public var effectiveFrom: Date
    public var energyKcal: Double
    public var proteinGrams: Double
    public var carbohydrateGrams: Double
    public var fatGrams: Double
    public var saturatedFatLimitGrams: Double?
    public var fibreGrams: Double?

    public init(
        id: UUID = UUID(),
        effectiveFrom: Date = .now,
        energyKcal: Double,
        proteinGrams: Double,
        carbohydrateGrams: Double,
        fatGrams: Double,
        saturatedFatLimitGrams: Double? = nil,
        fibreGrams: Double? = nil
    ) {
        self.id = id
        self.effectiveFrom = effectiveFrom
        self.energyKcal = energyKcal
        self.proteinGrams = proteinGrams
        self.carbohydrateGrams = carbohydrateGrams
        self.fatGrams = fatGrams
        self.saturatedFatLimitGrams = saturatedFatLimitGrams
        self.fibreGrams = fibreGrams
    }
}

public enum ConstraintKind: String, Codable, Sendable {
    case medication
    case halal
    case allergen
    case nutrition
}

public struct ConstraintRule: Codable, Identifiable, Sendable, Equatable {
    public var id: String
    public var version: Int
    public var kind: ConstraintKind
    public var matchTerms: [String]
    public var outcome: AssessmentConclusion
    public var reason: String

    public init(
        id: String,
        version: Int,
        kind: ConstraintKind,
        matchTerms: [String],
        outcome: AssessmentConclusion,
        reason: String
    ) {
        self.id = id
        self.version = version
        self.kind = kind
        self.matchTerms = matchTerms
        self.outcome = outcome
        self.reason = reason
    }
}

public enum FoodCategory: String, Codable, CaseIterable, Sendable {
    case proteinMain = "protein_main"
    case stapleGrain = "staple_grain"
    case mixedMeal = "mixed_meal"
    case snackDessert = "snack_dessert"
    case beverage
    case oil
    case sauce
}

public struct NutrientValues: Codable, Sendable, Equatable {
    public var energyKcal: Double
    public var fatGrams: Double
    public var saturatedFatGrams: Double
    public var carbohydrateGrams: Double
    public var sugarGrams: Double
    public var proteinGrams: Double
    public var saltGrams: Double
    public var fibreGrams: Double?

    public init(
        energyKcal: Double,
        fatGrams: Double,
        saturatedFatGrams: Double,
        carbohydrateGrams: Double,
        sugarGrams: Double,
        proteinGrams: Double,
        saltGrams: Double,
        fibreGrams: Double? = nil
    ) {
        self.energyKcal = energyKcal
        self.fatGrams = fatGrams
        self.saturatedFatGrams = saturatedFatGrams
        self.carbohydrateGrams = carbohydrateGrams
        self.sugarGrams = sugarGrams
        self.proteinGrams = proteinGrams
        self.saltGrams = saltGrams
        self.fibreGrams = fibreGrams
    }
}

public struct FoodItem: Codable, Identifiable, Sendable, Equatable {
    public var id: UUID
    public var name: String
    public var category: FoodCategory
    public var nutrientsPer100Units: NutrientValues
    public var unit: String
    public var source: String

    public init(
        id: UUID = UUID(),
        name: String,
        category: FoodCategory,
        nutrientsPer100Units: NutrientValues,
        unit: String = "g",
        source: String
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.nutrientsPer100Units = nutrientsPer100Units
        self.unit = unit
        self.source = source
    }
}

public struct ContainerProfile: Codable, Identifiable, Sendable, Equatable {
    public var id: UUID
    public var name: String
    public var tareWeightGrams: Double

    public init(id: UUID = UUID(), name: String, tareWeightGrams: Double) {
        self.id = id
        self.name = name
        self.tareWeightGrams = tareWeightGrams
    }
}

public enum ReviewStatus: String, Codable, Sendable {
    case pending
    case confirmed
    case dismissed
}

public struct ReviewQueueItem: Codable, Identifiable, Sendable, Equatable {
    public var id: UUID
    public var createdAt: Date
    public var sourceImageIdentifier: String?
    public var missingFields: [String]
    public var status: ReviewStatus

    public init(
        id: UUID = UUID(),
        createdAt: Date = .now,
        sourceImageIdentifier: String? = nil,
        missingFields: [String],
        status: ReviewStatus = .pending
    ) {
        self.id = id
        self.createdAt = createdAt
        self.sourceImageIdentifier = sourceImageIdentifier
        self.missingFields = missingFields
        self.status = status
    }
}

public struct MealLog: Codable, Identifiable, Sendable, Equatable {
    public var id: UUID
    public var eatenAt: Date
    public var title: String
    public var consumedWeightGrams: Double
    public var nutrients: NutrientValues
    public var coverageStatus: MealCoverageStatus
    public var estimateEvidenceGrade: EstimateEvidenceGrade
    public var healthKitSyncVersion: Int

    public var isCompleteForDailyCoverage: Bool {
        coverageStatus == .complete
    }

    public init(
        id: UUID = UUID(),
        eatenAt: Date = .now,
        title: String,
        consumedWeightGrams: Double,
        nutrients: NutrientValues,
        coverageStatus: MealCoverageStatus,
        estimateEvidenceGrade: EstimateEvidenceGrade,
        healthKitSyncVersion: Int = 1
    ) {
        self.id = id
        self.eatenAt = eatenAt
        self.title = title
        self.consumedWeightGrams = consumedWeightGrams
        self.nutrients = nutrients
        self.coverageStatus = coverageStatus
        self.estimateEvidenceGrade = estimateEvidenceGrade
        self.healthKitSyncVersion = healthKitSyncVersion
    }
}

public enum HealthKitObjectType: String, Codable, Sendable {
    case correlation
    case energy
    case protein
    case carbohydrate
    case totalFat
    case saturatedFat
    case fibre
}

public struct HealthKitSyncRecord: Codable, Identifiable, Sendable, Equatable {
    public var id: UUID
    public var mealID: UUID
    public var objectType: HealthKitObjectType
    public var syncIdentifier: String
    public var syncVersion: Int
    public var healthKitUUID: UUID?
    public var isDeleted: Bool

    public init(
        id: UUID = UUID(),
        mealID: UUID,
        objectType: HealthKitObjectType,
        syncIdentifier: String,
        syncVersion: Int,
        healthKitUUID: UUID? = nil,
        isDeleted: Bool = false
    ) {
        self.id = id
        self.mealID = mealID
        self.objectType = objectType
        self.syncIdentifier = syncIdentifier
        self.syncVersion = syncVersion
        self.healthKitUUID = healthKitUUID
        self.isDeleted = isDeleted
    }
}

public enum AssessmentConclusion: String, Codable, Sendable {
    case prohibited
    case consultPharmacist = "consult_pharmacist"
    case notRecommended = "not_recommended"
    case consider
    case worthBuying = "worth_buying"
    case pendingReview = "pending_review"
}

public struct Assessment: Codable, Identifiable, Sendable, Equatable {
    public var id: UUID
    public var conclusion: AssessmentConclusion
    public var nutritionScore: Int?
    public var reasons: [String]
    public var comparisonHint: String?
    public var ruleVersion: String

    public init(
        id: UUID = UUID(),
        conclusion: AssessmentConclusion,
        nutritionScore: Int? = nil,
        reasons: [String],
        comparisonHint: String? = nil,
        ruleVersion: String
    ) {
        self.id = id
        self.conclusion = conclusion
        self.nutritionScore = nutritionScore
        self.reasons = reasons
        self.comparisonHint = comparisonHint
        self.ruleVersion = ruleVersion
    }
}
