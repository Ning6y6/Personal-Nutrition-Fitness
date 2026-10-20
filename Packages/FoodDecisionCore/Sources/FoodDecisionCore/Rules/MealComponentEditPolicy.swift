import Foundation

public enum MealComponentEditError: Error, Codable, Sendable, Equatable, LocalizedError {
    case unavailableFood
    case mismatchedOriginalID
    case calculationUnderflow(field: String)

    public var errorDescription: String? {
        switch self {
        case .unavailableFood:
            "有食物尚未选择或已不可用，请检查这个分项。"
        case .mismatchedOriginalID:
            "原食物分项与正在编辑的分项不一致，请重新打开餐食。"
        case let .calculationUnderflow(field):
            "字段“\(field)”的计算结果小于可表示范围，请检查重量。"
        }
    }
}

/// Resolves one row without consulting current source data for an unchanged food identity.
/// Callers must keep `original` fixed for the entire editing session and every save retry;
/// feeding a previous preview back as `original` would compound rounding and quantity edits.
public enum MealComponentEditPolicy {
    public static func resolve(
        original: MealComponent?,
        id: UUID,
        foodItemID: UUID?,
        weightGrams: Double?,
        currentFood: FoodItem?
    ) throws -> MealComponent {
        guard let foodItemID else { throw MealComponentEditError.unavailableFood }
        guard let weightGrams else { throw MealLoggingError.invalidWeight }
        try validateWeight(weightGrams)

        if let original {
            guard original.id == id else { throw MealComponentEditError.mismatchedOriginalID }
            if original.foodItemID == foodItemID {
                guard original.unit == "g" else { throw MealLoggingError.unsupportedUnit(original.unit) }
                try validateWeight(original.consumedWeightGrams)
                // Preserve the complete saved snapshot, including exact values, on a no-op.
                if original.consumedWeightGrams == weightGrams { return original }

                let ratio = try checkedRatio(weightGrams, original.consumedWeightGrams)
                return try MealComponent(
                    id: original.id,
                    foodItemID: original.foodItemID,
                    foodName: original.foodName,
                    consumedWeightGrams: weightGrams,
                    unit: original.unit,
                    nutrients: checkedScale(original.nutrients, by: ratio)
                )
            }
        }

        guard let currentFood, currentFood.id == foodItemID else {
            throw MealComponentEditError.unavailableFood
        }
        guard currentFood.unit == "g" else { throw MealLoggingError.unsupportedUnit(currentFood.unit) }
        return try MealComponent(
            id: id,
            foodItemID: currentFood.id,
            foodName: currentFood.name,
            consumedWeightGrams: weightGrams,
            unit: currentFood.unit,
            nutrients: checkedScale(currentFood.nutrientsPer100Units, by: checkedRatio(weightGrams, 100))
        )
    }

    private static func validateWeight(_ weight: Double) throws {
        guard weight.isFinite else { throw MealLoggingError.nonFiniteWeight }
        guard weight > 0 else { throw MealLoggingError.invalidWeight }
    }

    private static func checkedRatio(_ amount: Double, _ originalAmount: Double) throws -> Double {
        let ratio = amount / originalAmount
        guard ratio.isFinite else { throw DomainValidationError.calculationOverflow(field: "weightRatio") }
        guard ratio > 0 else { throw MealComponentEditError.calculationUnderflow(field: "weightRatio") }
        return ratio
    }

    private static func checkedScale(_ original: NutrientValues, by ratio: Double) throws -> NutrientValues {
        let scaled = try original.scaled(by: ratio)
        let fields = [
            ("energyKcal", original.energyKcal, scaled.energyKcal),
            ("fatGrams", original.fatGrams, scaled.fatGrams),
            ("saturatedFatGrams", original.saturatedFatGrams, scaled.saturatedFatGrams),
            ("carbohydrateGrams", original.carbohydrateGrams, scaled.carbohydrateGrams),
            ("sugarGrams", original.sugarGrams, scaled.sugarGrams),
            ("proteinGrams", original.proteinGrams, scaled.proteinGrams),
            ("saltGrams", original.saltGrams, scaled.saltGrams),
        ]
        for (field, before, after) in fields {
            try rejectLostPositiveValue(before, scaled: after, field: field)
        }
        if let before = original.fibreGrams, let after = scaled.fibreGrams {
            try rejectLostPositiveValue(before, scaled: after, field: "fibreGrams")
        }
        return scaled
    }

    private static func rejectLostPositiveValue(_ original: Double, scaled: Double, field: String) throws {
        if original > 0 && scaled == 0 {
            throw MealComponentEditError.calculationUnderflow(field: field)
        }
    }
}
