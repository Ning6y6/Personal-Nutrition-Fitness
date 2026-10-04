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

    public func scaled(by multiplier: Double) -> NutrientValues {
        NutrientValues(
            energyKcal: energyKcal * multiplier,
            fatGrams: fatGrams * multiplier,
            saturatedFatGrams: saturatedFatGrams * multiplier,
            carbohydrateGrams: carbohydrateGrams * multiplier,
            sugarGrams: sugarGrams * multiplier,
            proteinGrams: proteinGrams * multiplier,
            saltGrams: saltGrams * multiplier,
            fibreGrams: fibreGrams.map { $0 * multiplier }
        )
    }

    public static func sum(_ values: [NutrientValues]) -> NutrientValues {
        let fibreValues = values.compactMap(\.fibreGrams)
        let hasCompleteFibreData = fibreValues.count == values.count

        return NutrientValues(
            energyKcal: values.reduce(0) { $0 + $1.energyKcal },
            fatGrams: values.reduce(0) { $0 + $1.fatGrams },
            saturatedFatGrams: values.reduce(0) { $0 + $1.saturatedFatGrams },
            carbohydrateGrams: values.reduce(0) { $0 + $1.carbohydrateGrams },
            sugarGrams: values.reduce(0) { $0 + $1.sugarGrams },
            proteinGrams: values.reduce(0) { $0 + $1.proteinGrams },
            saltGrams: values.reduce(0) { $0 + $1.saltGrams },
            fibreGrams: hasCompleteFibreData ? fibreValues.reduce(0, +) : nil
        )
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

public enum MealEntryMethod: String, Codable, CaseIterable, Sendable, Equatable {
    case weighed
    case standardPortionEstimate = "standard_portion_estimate"

    public var evidenceGrade: EstimateEvidenceGrade {
        switch self {
        case .weighed:
            .a
        case .standardPortionEstimate:
            .b
        }
    }
}

public enum MealLoggingError: Error, Codable, Sendable, Equatable, LocalizedError {
    case emptyTitle
    case emptyComponents
    case invalidWeight
    case unsupportedUnit(String)

    public var errorDescription: String? {
        switch self {
        case .emptyTitle:
            "请输入餐食名称。"
        case .emptyComponents:
            "请至少添加一个食物分项。"
        case .invalidWeight:
            "每个食物分项的重量必须大于 0 克。"
        case let .unsupportedUnit(unit):
            "当前版本尚不支持单位“\(unit)”。"
        }
    }
}

public struct MealComponent: Codable, Identifiable, Sendable, Equatable {
    public var id: UUID
    public var foodItemID: UUID
    public var foodName: String
    public var consumedWeightGrams: Double
    public var unit: String
    public var nutrients: NutrientValues

    public init(
        id: UUID = UUID(),
        foodItemID: UUID,
        foodName: String,
        consumedWeightGrams: Double,
        unit: String,
        nutrients: NutrientValues
    ) throws {
        guard consumedWeightGrams > 0 else {
            throw MealLoggingError.invalidWeight
        }
        guard unit == "g" else {
            throw MealLoggingError.unsupportedUnit(unit)
        }

        self.id = id
        self.foodItemID = foodItemID
        self.foodName = foodName
        self.consumedWeightGrams = consumedWeightGrams
        self.unit = unit
        self.nutrients = nutrients
    }

    public init(id: UUID = UUID(), foodItem: FoodItem, consumedWeightGrams: Double) throws {
        guard foodItem.unit == "g" else {
            throw MealLoggingError.unsupportedUnit(foodItem.unit)
        }
        guard consumedWeightGrams > 0 else {
            throw MealLoggingError.invalidWeight
        }

        self.id = id
        foodItemID = foodItem.id
        foodName = foodItem.name
        self.consumedWeightGrams = consumedWeightGrams
        unit = foodItem.unit
        nutrients = foodItem.nutrientsPer100Units.scaled(by: consumedWeightGrams / 100)
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            id: container.decode(UUID.self, forKey: .id),
            foodItemID: container.decode(UUID.self, forKey: .foodItemID),
            foodName: container.decode(String.self, forKey: .foodName),
            consumedWeightGrams: container.decode(Double.self, forKey: .consumedWeightGrams),
            unit: container.decode(String.self, forKey: .unit),
            nutrients: container.decode(NutrientValues.self, forKey: .nutrients)
        )
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
    public var entryMethod: MealEntryMethod
    public var coverageStatus: MealCoverageStatus
    public var estimateEvidenceGrade: EstimateEvidenceGrade
    public var healthKitSyncVersion: Int
    public var components: [MealComponent]

    public var isCompleteForDailyCoverage: Bool {
        coverageStatus == .complete
    }

    public init(
        id: UUID = UUID(),
        eatenAt: Date = .now,
        title: String,
        consumedWeightGrams: Double,
        nutrients: NutrientValues,
        entryMethod: MealEntryMethod = .weighed,
        coverageStatus: MealCoverageStatus,
        estimateEvidenceGrade: EstimateEvidenceGrade,
        healthKitSyncVersion: Int = 1,
        components: [MealComponent] = []
    ) {
        self.id = id
        self.eatenAt = eatenAt
        self.title = title
        self.consumedWeightGrams = consumedWeightGrams
        self.nutrients = nutrients
        self.entryMethod = entryMethod
        self.coverageStatus = coverageStatus
        self.estimateEvidenceGrade = estimateEvidenceGrade
        self.healthKitSyncVersion = healthKitSyncVersion
        self.components = components
    }

    public init(
        id: UUID = UUID(),
        eatenAt: Date = .now,
        title: String,
        entryMethod: MealEntryMethod,
        coverageStatus: MealCoverageStatus,
        components: [MealComponent],
        healthKitSyncVersion: Int = 1
    ) throws {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            throw MealLoggingError.emptyTitle
        }
        guard !components.isEmpty else {
            throw MealLoggingError.emptyComponents
        }

        self.id = id
        self.eatenAt = eatenAt
        self.title = trimmedTitle
        consumedWeightGrams = components.reduce(0) { $0 + $1.consumedWeightGrams }
        nutrients = NutrientValues.sum(components.map(\.nutrients))
        self.entryMethod = entryMethod
        self.coverageStatus = coverageStatus
        estimateEvidenceGrade = entryMethod.evidenceGrade
        self.healthKitSyncVersion = healthKitSyncVersion
        self.components = components
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
