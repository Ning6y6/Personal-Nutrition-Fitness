import Foundation

public enum MealTemplateError: Error, Codable, Sendable, Equatable, LocalizedError {
    case emptyName
    case emptyComponents
    case invalidWeight
    case unsupportedUnit(String)

    public var errorDescription: String? {
        switch self {
        case .emptyName:
            "请输入模板名称。"
        case .emptyComponents:
            "请至少添加一个食物分项。"
        case .invalidWeight:
            "每个模板分项的默认重量必须大于 0 克。"
        case let .unsupportedUnit(unit):
            "当前版本尚不支持单位“\(unit)”。"
        }
    }
}

public struct MealTemplateComponent: Codable, Identifiable, Sendable, Equatable {
    public var id: UUID
    public var foodItemID: UUID
    public var foodName: String
    public var defaultWeightGrams: Double
    public var unit: String

    public init(
        id: UUID = UUID(),
        foodItemID: UUID,
        foodName: String,
        defaultWeightGrams: Double,
        unit: String = "g"
    ) throws {
        guard defaultWeightGrams > 0 else {
            throw MealTemplateError.invalidWeight
        }
        guard unit == "g" else {
            throw MealTemplateError.unsupportedUnit(unit)
        }

        self.id = id
        self.foodItemID = foodItemID
        self.foodName = foodName
        self.defaultWeightGrams = defaultWeightGrams
        self.unit = unit
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            id: container.decode(UUID.self, forKey: .id),
            foodItemID: container.decode(UUID.self, forKey: .foodItemID),
            foodName: container.decode(String.self, forKey: .foodName),
            defaultWeightGrams: container.decode(Double.self, forKey: .defaultWeightGrams),
            unit: container.decode(String.self, forKey: .unit)
        )
    }
}

public struct MealTemplate: Codable, Identifiable, Sendable, Equatable {
    public var id: UUID
    public var name: String
    public var createdAt: Date
    public var updatedAt: Date
    public var lastUsedAt: Date?
    public var useCount: Int
    public var components: [MealTemplateComponent]

    public init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        lastUsedAt: Date? = nil,
        useCount: Int = 0,
        components: [MealTemplateComponent]
    ) throws {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw MealTemplateError.emptyName
        }
        guard !components.isEmpty else {
            throw MealTemplateError.emptyComponents
        }

        self.id = id
        self.name = trimmedName
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastUsedAt = lastUsedAt
        self.useCount = max(0, useCount)
        self.components = components
    }

    public init(meal: MealLog, now: Date = .now) throws {
        try self.init(
            name: meal.title,
            createdAt: now,
            updatedAt: now,
            components: try meal.components.map {
                try MealTemplateComponent(
                    foodItemID: $0.foodItemID,
                    foodName: $0.foodName,
                    defaultWeightGrams: $0.consumedWeightGrams,
                    unit: $0.unit
                )
            }
        )
    }

    public mutating func recordUse(at date: Date = .now) {
        lastUsedAt = date
        useCount += 1
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            id: container.decode(UUID.self, forKey: .id),
            name: container.decode(String.self, forKey: .name),
            createdAt: container.decode(Date.self, forKey: .createdAt),
            updatedAt: container.decode(Date.self, forKey: .updatedAt),
            lastUsedAt: container.decodeIfPresent(Date.self, forKey: .lastUsedAt),
            useCount: container.decode(Int.self, forKey: .useCount),
            components: container.decode([MealTemplateComponent].self, forKey: .components)
        )
    }
}

public struct MealEntryDraftComponent: Codable, Identifiable, Sendable, Equatable {
    public var id: UUID
    public var foodItemID: UUID?
    public var foodName: String?
    public var weightGrams: Double?

    public init(
        id: UUID = UUID(),
        foodItemID: UUID? = nil,
        foodName: String? = nil,
        weightGrams: Double? = nil
    ) {
        self.id = id
        self.foodItemID = foodItemID
        self.foodName = foodName
        self.weightGrams = weightGrams
    }
}

public struct MealEntryDraft: Codable, Identifiable, Sendable, Equatable {
    public var id: UUID
    public var title: String
    public var eatenAt: Date
    public var entryMethod: MealEntryMethod
    public var coverageStatus: MealCoverageStatus
    public var sourceTemplateID: UUID?
    public var components: [MealEntryDraftComponent]

    public init(
        id: UUID = UUID(),
        title: String,
        eatenAt: Date = .now,
        entryMethod: MealEntryMethod,
        coverageStatus: MealCoverageStatus,
        sourceTemplateID: UUID? = nil,
        components: [MealEntryDraftComponent]
    ) {
        self.id = id
        self.title = title
        self.eatenAt = eatenAt
        self.entryMethod = entryMethod
        self.coverageStatus = coverageStatus
        self.sourceTemplateID = sourceTemplateID
        self.components = components
    }

    public init(reusing meal: MealLog, now: Date = .now) {
        self.init(
            title: meal.title,
            eatenAt: now,
            entryMethod: .standardPortionEstimate,
            coverageStatus: .complete,
            components: meal.components.map {
                MealEntryDraftComponent(
                    foodItemID: $0.foodItemID,
                    foodName: $0.foodName,
                    weightGrams: $0.consumedWeightGrams
                )
            }
        )
    }

    public init(template: MealTemplate, now: Date = .now) {
        self.init(
            title: template.name,
            eatenAt: now,
            entryMethod: .standardPortionEstimate,
            coverageStatus: .complete,
            sourceTemplateID: template.id,
            components: template.components.map {
                MealEntryDraftComponent(
                    foodItemID: $0.foodItemID,
                    foodName: $0.foodName,
                    weightGrams: $0.defaultWeightGrams
                )
            }
        )
    }
}

public enum RecentMealSelector {
    public static func select(
        from meals: [MealLog],
        historyLimit: Int = 30,
        resultLimit: Int = 6
    ) -> [MealLog] {
        guard historyLimit > 0, resultLimit > 0 else { return [] }

        var seenKeys = Set<String>()
        var result: [MealLog] = []

        for meal in meals.sorted(by: { $0.eatenAt > $1.eatenAt }).prefix(historyLimit) {
            guard !meal.components.isEmpty else { continue }

            let key = deduplicationKey(for: meal)
            guard seenKeys.insert(key).inserted else { continue }

            result.append(meal)
            if result.count == resultLimit {
                break
            }
        }

        return result
    }

    private static func deduplicationKey(for meal: MealLog) -> String {
        let normalizedTitle = meal.title
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let foodComposition = meal.components
            .map { $0.foodItemID.uuidString.lowercased() }
            .sorted()
            .joined(separator: ",")
        return "\(normalizedTitle)|\(foodComposition)"
    }
}
