import Foundation

public struct GoalProfile: Codable, Identifiable, Sendable, Equatable {
    public let id: UUID
    public let effectiveFrom: Date
    public let energyKcal: Double
    public let proteinGrams: Double
    public let carbohydrateGrams: Double
    public let fatGrams: Double
    public let saturatedFatLimitGrams: Double?
    public let fibreGrams: Double?

    public init(
        id: UUID = UUID(),
        effectiveFrom: Date = .now,
        energyKcal: Double,
        proteinGrams: Double,
        carbohydrateGrams: Double,
        fatGrams: Double,
        saturatedFatLimitGrams: Double? = nil,
        fibreGrams: Double? = nil
    ) throws {
        try DomainValidation.date(effectiveFrom, field: "effectiveFrom")
        try DomainValidation.positive(energyKcal, field: "energyKcal")
        try DomainValidation.nonnegative(proteinGrams, field: "proteinGrams")
        try DomainValidation.nonnegative(carbohydrateGrams, field: "carbohydrateGrams")
        try DomainValidation.nonnegative(fatGrams, field: "fatGrams")
        if let saturatedFatLimitGrams { try DomainValidation.nonnegative(saturatedFatLimitGrams, field: "saturatedFatLimitGrams") }
        if let fibreGrams { try DomainValidation.nonnegative(fibreGrams, field: "fibreGrams") }
        self.id = id
        self.effectiveFrom = effectiveFrom
        self.energyKcal = energyKcal
        self.proteinGrams = proteinGrams
        self.carbohydrateGrams = carbohydrateGrams
        self.fatGrams = fatGrams
        self.saturatedFatLimitGrams = saturatedFatLimitGrams
        self.fibreGrams = fibreGrams
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            id: container.decode(UUID.self, forKey: .id),
            effectiveFrom: container.decode(Date.self, forKey: .effectiveFrom),
            energyKcal: container.decode(Double.self, forKey: .energyKcal),
            proteinGrams: container.decode(Double.self, forKey: .proteinGrams),
            carbohydrateGrams: container.decode(Double.self, forKey: .carbohydrateGrams),
            fatGrams: container.decode(Double.self, forKey: .fatGrams),
            saturatedFatLimitGrams: container.decodeIfPresent(Double.self, forKey: .saturatedFatLimitGrams),
            fibreGrams: container.decodeIfPresent(Double.self, forKey: .fibreGrams)
        )
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
    public let energyKcal: Double
    public let fatGrams: Double
    public let saturatedFatGrams: Double
    public let carbohydrateGrams: Double
    public let sugarGrams: Double
    public let proteinGrams: Double
    public let saltGrams: Double
    public let fibreGrams: Double?

    public static let zero = NutrientValues(zero: ())

    private init(zero: ()) {
        energyKcal = 0
        fatGrams = 0
        saturatedFatGrams = 0
        carbohydrateGrams = 0
        sugarGrams = 0
        proteinGrams = 0
        saltGrams = 0
        fibreGrams = 0
    }

    public init(
        energyKcal: Double,
        fatGrams: Double,
        saturatedFatGrams: Double,
        carbohydrateGrams: Double,
        sugarGrams: Double,
        proteinGrams: Double,
        saltGrams: Double,
        fibreGrams: Double? = nil
    ) throws {
        try DomainValidation.nonnegative(energyKcal, field: "energyKcal")
        try DomainValidation.nonnegative(fatGrams, field: "fatGrams")
        try DomainValidation.nonnegative(saturatedFatGrams, field: "saturatedFatGrams")
        try DomainValidation.nonnegative(carbohydrateGrams, field: "carbohydrateGrams")
        try DomainValidation.nonnegative(sugarGrams, field: "sugarGrams")
        try DomainValidation.nonnegative(proteinGrams, field: "proteinGrams")
        try DomainValidation.nonnegative(saltGrams, field: "saltGrams")
        if let fibreGrams { try DomainValidation.nonnegative(fibreGrams, field: "fibreGrams") }
        self.energyKcal = energyKcal
        self.fatGrams = fatGrams
        self.saturatedFatGrams = saturatedFatGrams
        self.carbohydrateGrams = carbohydrateGrams
        self.sugarGrams = sugarGrams
        self.proteinGrams = proteinGrams
        self.saltGrams = saltGrams
        self.fibreGrams = fibreGrams
    }

    public func scaled(by multiplier: Double) throws -> NutrientValues {
        try DomainValidation.nonnegative(multiplier, field: "multiplier")
        return try NutrientValues(
            energyKcal: DomainValidation.multiply(energyKcal, multiplier, field: "energyKcal"),
            fatGrams: DomainValidation.multiply(fatGrams, multiplier, field: "fatGrams"),
            saturatedFatGrams: DomainValidation.multiply(saturatedFatGrams, multiplier, field: "saturatedFatGrams"),
            carbohydrateGrams: DomainValidation.multiply(carbohydrateGrams, multiplier, field: "carbohydrateGrams"),
            sugarGrams: DomainValidation.multiply(sugarGrams, multiplier, field: "sugarGrams"),
            proteinGrams: DomainValidation.multiply(proteinGrams, multiplier, field: "proteinGrams"),
            saltGrams: DomainValidation.multiply(saltGrams, multiplier, field: "saltGrams"),
            fibreGrams: fibreGrams.map { try DomainValidation.multiply($0, multiplier, field: "fibreGrams") }
        )
    }

    public static func sum(_ values: [NutrientValues]) throws -> NutrientValues {
        let fibreValues = values.compactMap(\.fibreGrams)
        let hasCompleteFibreData = fibreValues.count == values.count

        return try NutrientValues(
            energyKcal: sumField(values.map(\.energyKcal), field: "energyKcal"),
            fatGrams: sumField(values.map(\.fatGrams), field: "fatGrams"),
            saturatedFatGrams: sumField(values.map(\.saturatedFatGrams), field: "saturatedFatGrams"),
            carbohydrateGrams: sumField(values.map(\.carbohydrateGrams), field: "carbohydrateGrams"),
            sugarGrams: sumField(values.map(\.sugarGrams), field: "sugarGrams"),
            proteinGrams: sumField(values.map(\.proteinGrams), field: "proteinGrams"),
            saltGrams: sumField(values.map(\.saltGrams), field: "saltGrams"),
            fibreGrams: hasCompleteFibreData ? sumField(fibreValues, field: "fibreGrams") : nil
        )
    }

    private static func sumField(_ values: [Double], field: String) throws -> Double {
        try values.reduce(0) { try DomainValidation.add($0, $1, field: field) }
    }

    func approximatelyEquals(_ other: NutrientValues) -> Bool {
        let values = [energyKcal, fatGrams, saturatedFatGrams, carbohydrateGrams, sugarGrams, proteinGrams, saltGrams]
        let otherValues = [other.energyKcal, other.fatGrams, other.saturatedFatGrams, other.carbohydrateGrams, other.sugarGrams, other.proteinGrams, other.saltGrams]
        guard zip(values, otherValues).allSatisfy({ DomainValidation.approximatelyEqual($0, $1) }) else { return false }
        switch (fibreGrams, other.fibreGrams) {
        case (nil, nil): return true
        case let (lhs?, rhs?): return DomainValidation.approximatelyEqual(lhs, rhs)
        default: return false
        }
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            energyKcal: container.decode(Double.self, forKey: .energyKcal),
            fatGrams: container.decode(Double.self, forKey: .fatGrams),
            saturatedFatGrams: container.decode(Double.self, forKey: .saturatedFatGrams),
            carbohydrateGrams: container.decode(Double.self, forKey: .carbohydrateGrams),
            sugarGrams: container.decode(Double.self, forKey: .sugarGrams),
            proteinGrams: container.decode(Double.self, forKey: .proteinGrams),
            saltGrams: container.decode(Double.self, forKey: .saltGrams),
            fibreGrams: container.decodeIfPresent(Double.self, forKey: .fibreGrams)
        )
    }
}

public struct FoodItem: Codable, Identifiable, Sendable, Equatable {
    public let id: UUID
    public let name: String
    public let category: FoodCategory
    public let nutrientsPer100Units: NutrientValues
    public let unit: String
    public let source: String

    public init(
        id: UUID = UUID(),
        name: String,
        category: FoodCategory,
        nutrientsPer100Units: NutrientValues,
        unit: String = "g",
        source: String
    ) throws {
        try DomainValidation.text(name, field: "name")
        try DomainValidation.text(unit, field: "unit")
        try DomainValidation.text(source, field: "source")
        self.id = id
        self.name = name
        self.category = category
        self.nutrientsPer100Units = nutrientsPer100Units
        self.unit = unit
        self.source = source
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            id: container.decode(UUID.self, forKey: .id),
            name: container.decode(String.self, forKey: .name),
            category: container.decode(FoodCategory.self, forKey: .category),
            nutrientsPer100Units: container.decode(NutrientValues.self, forKey: .nutrientsPer100Units),
            unit: container.decode(String.self, forKey: .unit),
            source: container.decode(String.self, forKey: .source)
        )
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
    case nonFiniteWeight
    case unsupportedUnit(String)
    case duplicateComponentID(UUID)
    case inconsistentTotals
    case invalidSyncVersion
    case unconfirmedEstimate

    public var errorDescription: String? {
        switch self {
        case .emptyTitle:
            "请输入餐食名称。"
        case .emptyComponents:
            "请至少添加一个食物分项。"
        case .invalidWeight:
            "每个食物分项的重量必须大于 0 克。"
        case .nonFiniteWeight:
            "食物重量必须是有限数值。"
        case let .unsupportedUnit(unit):
            "当前版本尚不支持单位“\(unit)”。"
        case .duplicateComponentID:
            "食物分项标识重复，请重新添加分项。"
        case .inconsistentTotals:
            "餐食总量与食物分项不一致。"
        case .invalidSyncVersion:
            "餐食同步版本必须大于 0。"
        case .unconfirmedEstimate:
            "尚未确认的估算草稿不能保存为正式餐食。"
        }
    }
}

public struct MealComponent: Codable, Identifiable, Sendable, Equatable {
    public let id: UUID
    public let foodItemID: UUID
    public let foodName: String
    public let consumedWeightGrams: Double
    public let unit: String
    public let nutrients: NutrientValues

    public init(
        id: UUID = UUID(),
        foodItemID: UUID,
        foodName: String,
        consumedWeightGrams: Double,
        unit: String,
        nutrients: NutrientValues
    ) throws {
        guard consumedWeightGrams.isFinite else { throw MealLoggingError.nonFiniteWeight }
        guard consumedWeightGrams > 0 else {
            throw MealLoggingError.invalidWeight
        }
        guard unit == "g" else {
            throw MealLoggingError.unsupportedUnit(unit)
        }
        try DomainValidation.text(foodName, field: "foodName")

        self.id = id
        self.foodItemID = foodItemID
        self.foodName = foodName
        self.consumedWeightGrams = consumedWeightGrams
        self.unit = unit
        self.nutrients = nutrients
    }

    public init(id: UUID = UUID(), foodItem: FoodItem, consumedWeightGrams: Double) throws {
        guard consumedWeightGrams.isFinite else { throw MealLoggingError.nonFiniteWeight }
        guard consumedWeightGrams > 0 else { throw MealLoggingError.invalidWeight }
        try self.init(
            id: id,
            foodItemID: foodItem.id,
            foodName: foodItem.name,
            consumedWeightGrams: consumedWeightGrams,
            unit: foodItem.unit,
            nutrients: foodItem.nutrientsPer100Units.scaled(by: consumedWeightGrams / 100)
        )
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
    public let id: UUID
    public let name: String
    public let tareWeightGrams: Double

    public init(id: UUID = UUID(), name: String, tareWeightGrams: Double) throws {
        try DomainValidation.text(name, field: "name")
        try DomainValidation.nonnegative(tareWeightGrams, field: "tareWeightGrams")
        self.id = id
        self.name = name
        self.tareWeightGrams = tareWeightGrams
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(id: container.decode(UUID.self, forKey: .id), name: container.decode(String.self, forKey: .name), tareWeightGrams: container.decode(Double.self, forKey: .tareWeightGrams))
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
    public let id: UUID
    public let eatenAt: Date
    public let title: String
    public let consumedWeightGrams: Double
    public let nutrients: NutrientValues
    public let entryMethod: MealEntryMethod
    public let coverageStatus: MealCoverageStatus
    public let estimateEvidenceGrade: EstimateEvidenceGrade
    public let healthKitSyncVersion: Int
    public let components: [MealComponent]

    public var isCompleteForDailyCoverage: Bool {
        coverageStatus == .complete && estimateEvidenceGrade != .d
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
    ) throws {
        let trimmedTitle = try Self.validatedTitle(title, components: components, syncVersion: healthKitSyncVersion, evidenceGrade: estimateEvidenceGrade)
        try DomainValidation.date(eatenAt, field: "eatenAt")
        guard consumedWeightGrams.isFinite else { throw MealLoggingError.nonFiniteWeight }
        guard consumedWeightGrams > 0 else { throw MealLoggingError.invalidWeight }
        let computedWeight = try Self.totalWeight(of: components)
        let computedNutrients = try NutrientValues.sum(components.map(\.nutrients))
        guard DomainValidation.approximatelyEqual(consumedWeightGrams, computedWeight), nutrients.approximatelyEquals(computedNutrients) else {
            throw MealLoggingError.inconsistentTotals
        }
        self.id = id
        self.eatenAt = eatenAt
        self.title = trimmedTitle
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
        // Validate structure before calculating, so empty/draft input never enters a formal meal.
        _ = try Self.validatedTitle(title, components: components, syncVersion: healthKitSyncVersion, evidenceGrade: entryMethod.evidenceGrade)
        try self.init(
            id: id,
            eatenAt: eatenAt,
            title: title,
            consumedWeightGrams: Self.totalWeight(of: components),
            nutrients: NutrientValues.sum(components.map(\.nutrients)),
            entryMethod: entryMethod,
            coverageStatus: coverageStatus,
            estimateEvidenceGrade: entryMethod.evidenceGrade,
            healthKitSyncVersion: healthKitSyncVersion,
            components: components
        )
    }

    private static func validatedTitle(_ title: String, components: [MealComponent], syncVersion: Int, evidenceGrade: EstimateEvidenceGrade) throws -> String {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            throw MealLoggingError.emptyTitle
        }
        guard !components.isEmpty else {
            throw MealLoggingError.emptyComponents
        }
        var ids = Set<UUID>()
        for component in components {
            guard ids.insert(component.id).inserted else { throw MealLoggingError.duplicateComponentID(component.id) }
        }
        guard syncVersion > 0 else { throw MealLoggingError.invalidSyncVersion }
        guard evidenceGrade != .d else { throw MealLoggingError.unconfirmedEstimate }
        return trimmedTitle
    }

    private static func totalWeight(of components: [MealComponent]) throws -> Double {
        try components.reduce(0) { try DomainValidation.add($0, $1.consumedWeightGrams, field: "consumedWeightGrams") }
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            id: container.decode(UUID.self, forKey: .id),
            eatenAt: container.decode(Date.self, forKey: .eatenAt),
            title: container.decode(String.self, forKey: .title),
            consumedWeightGrams: container.decode(Double.self, forKey: .consumedWeightGrams),
            nutrients: container.decode(NutrientValues.self, forKey: .nutrients),
            entryMethod: container.decode(MealEntryMethod.self, forKey: .entryMethod),
            coverageStatus: container.decode(MealCoverageStatus.self, forKey: .coverageStatus),
            estimateEvidenceGrade: container.decode(EstimateEvidenceGrade.self, forKey: .estimateEvidenceGrade),
            healthKitSyncVersion: container.decode(Int.self, forKey: .healthKitSyncVersion),
            components: container.decode([MealComponent].self, forKey: .components)
        )
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
