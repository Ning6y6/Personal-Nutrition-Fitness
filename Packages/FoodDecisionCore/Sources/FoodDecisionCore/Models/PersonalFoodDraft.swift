import Foundation

public enum PersonalFoodInputError: Error, Sendable, Equatable, LocalizedError {
    case missingRequiredField(String)
    case invalidNumber(String)
    case unsupportedDecimalSeparator(String)
    case notPersonalFood

    public var errorDescription: String? {
        switch self {
        case let .missingRequiredField(field):
            "请输入\(Self.label(for: field))；未知值不能按 0 保存。"
        case let .invalidNumber(field):
            "\(Self.label(for: field))须为有限、非负数值；不接受单位、千位分隔符、Tr 或 <0.1。"
        case .unsupportedDecimalSeparator:
            "当前仅支持点号或逗号作为明确的小数分隔符。"
        case .notPersonalFood:
            "此食物没有可识别的个人食物卡信息，不能在这里编辑。"
        }
    }

    private static func label(for field: String) -> String {
        switch field {
        case "name": "食物名称"
        case "energyKcal": "热量"
        case "fatGrams": "脂肪"
        case "saturatedFatGrams": "饱和脂肪"
        case "carbohydrateGrams": "碳水化合物"
        case "sugarGrams": "糖"
        case "proteinGrams": "蛋白质"
        case "saltGrams": "盐"
        case "fibreGrams": "纤维"
        default: field
        }
    }
}

/// Unvalidated raw form text. Saving a card does not itself create a meal or intake.
/// All nutrition values describe 100 g; there is deliberately no ml or serving conversion.
public struct PersonalFoodDraft: Sendable, Equatable {
    public var name = ""
    public var category: FoodCategory = .snackDessert
    public var sourceNote = ""
    public var energyKcal = ""
    public var fatGrams = ""
    public var saturatedFatGrams = ""
    public var carbohydrateGrams = ""
    public var sugarGrams = ""
    public var proteinGrams = ""
    public var saltGrams = ""
    public var fibreGrams = ""

    public init() {}

    /// Preserves stored precision instead of prefilling rounded display values.
    /// Catalog/reserved-ID protection remains the responsibility of the app identity adapter.
    public init(food: FoodItem, decimalSeparator: String = ".") throws {
        try Self.validate(separator: decimalSeparator)
        guard food.unit == "g",
              let source = PersonalFoodSource.decode(source: food.source, foodID: food.id) else {
            throw PersonalFoodInputError.notPersonalFood
        }
        self.init()
        name = food.name
        category = food.category
        sourceNote = source.note
        let nutrients = food.nutrientsPer100Units
        energyKcal = Self.text(nutrients.energyKcal, decimalSeparator: decimalSeparator)
        fatGrams = Self.text(nutrients.fatGrams, decimalSeparator: decimalSeparator)
        saturatedFatGrams = Self.text(nutrients.saturatedFatGrams, decimalSeparator: decimalSeparator)
        carbohydrateGrams = Self.text(nutrients.carbohydrateGrams, decimalSeparator: decimalSeparator)
        sugarGrams = Self.text(nutrients.sugarGrams, decimalSeparator: decimalSeparator)
        proteinGrams = Self.text(nutrients.proteinGrams, decimalSeparator: decimalSeparator)
        saltGrams = Self.text(nutrients.saltGrams, decimalSeparator: decimalSeparator)
        fibreGrams = nutrients.fibreGrams.map { Self.text($0, decimalSeparator: decimalSeparator) } ?? ""
    }

    public func validFood(id: UUID, decimalSeparator: String = ".") throws -> FoodItem {
        try Self.validate(separator: decimalSeparator)
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedName.isEmpty == false else { throw PersonalFoodInputError.missingRequiredField("name") }

        let nutrients = try NutrientValues(
            energyKcal: Self.requiredNumber(energyKcal, field: "energyKcal", decimalSeparator: decimalSeparator),
            fatGrams: Self.requiredNumber(fatGrams, field: "fatGrams", decimalSeparator: decimalSeparator),
            saturatedFatGrams: Self.requiredNumber(saturatedFatGrams, field: "saturatedFatGrams", decimalSeparator: decimalSeparator),
            carbohydrateGrams: Self.requiredNumber(carbohydrateGrams, field: "carbohydrateGrams", decimalSeparator: decimalSeparator),
            sugarGrams: Self.requiredNumber(sugarGrams, field: "sugarGrams", decimalSeparator: decimalSeparator),
            proteinGrams: Self.requiredNumber(proteinGrams, field: "proteinGrams", decimalSeparator: decimalSeparator),
            saltGrams: Self.requiredNumber(saltGrams, field: "saltGrams", decimalSeparator: decimalSeparator),
            fibreGrams: Self.optionalNumber(fibreGrams, field: "fibreGrams", decimalSeparator: decimalSeparator)
        )
        return try FoodItem(
            id: id,
            name: trimmedName,
            category: category,
            nutrientsPer100Units: nutrients,
            unit: "g",
            source: PersonalFoodSource.encode(foodID: id, note: sourceNote)
        )
    }

    private static func validate(separator: String) throws {
        guard separator == "." || separator == "," else {
            throw PersonalFoodInputError.unsupportedDecimalSeparator(separator)
        }
    }

    private static func requiredNumber(_ input: String, field: String, decimalSeparator: String) throws -> Double {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { throw PersonalFoodInputError.missingRequiredField(field) }
        return try number(trimmed, field: field, decimalSeparator: decimalSeparator)
    }

    private static func optionalNumber(_ input: String, field: String, decimalSeparator: String) throws -> Double? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return nil }
        return try number(trimmed, field: field, decimalSeparator: decimalSeparator)
    }

    private static func number(_ input: String, field: String, decimalSeparator: String) throws -> Double {
        let otherSeparator = decimalSeparator == "." ? "," : "."
        guard input.contains(otherSeparator) == false else { throw PersonalFoodInputError.invalidNumber(field) }
        let normalized = input.replacingOccurrences(of: decimalSeparator, with: ".")
        let grammar = #"^[+-]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][+-]?[0-9]+)?$"#
        guard normalized.range(of: grammar, options: .regularExpression) != nil,
              let value = Double(normalized), value.isFinite, value >= 0 else {
            throw PersonalFoodInputError.invalidNumber(field)
        }
        // A nonzero label value too small for Double must not silently become a known zero.
        if value == 0 {
            let mantissa = normalized.split(whereSeparator: { $0 == "e" || $0 == "E" }).first ?? ""
            guard mantissa.contains(where: { ("1"..."9").contains(String($0)) }) == false else {
                throw PersonalFoodInputError.invalidNumber(field)
            }
        }
        return value
    }

    private static func text(_ value: Double, decimalSeparator: String) -> String {
        String(value).replacingOccurrences(of: ".", with: decimalSeparator)
    }
}
