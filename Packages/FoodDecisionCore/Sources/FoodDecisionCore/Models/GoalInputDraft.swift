import Foundation

public enum GoalInputError: Error, Sendable, Equatable, LocalizedError {
    case confirmationRequired
    case missingRequiredField(String)
    case invalidNumber(String)
    case unsupportedDecimalSeparator(String)

    public var errorDescription: String? {
        switch self {
        case .confirmationRequired:
            "请先确认这些是你希望保存的每日目标。"
        case let .missingRequiredField(field):
            "请输入\(Self.label(for: field))；未设置不能按 0 保存。"
        case let .invalidNumber(field):
            "\(Self.label(for: field))格式无效。请只输入数值，不含单位或千位分隔符，并使用当前小数分隔符。"
        case .unsupportedDecimalSeparator:
            "当前仅支持点号或逗号作为明确的小数分隔符。"
        }
    }

    private static func label(for field: String) -> String {
        switch field {
        case "energyKcal": "热量目标"
        case "proteinGrams": "蛋白质目标"
        case "carbohydrateGrams": "碳水化合物目标"
        case "fatGrams": "脂肪目标"
        case "saturatedFatLimitGrams": "饱和脂肪上限"
        case "fibreGrams": "纤维目标"
        default: field
        }
    }
}

/// Unvalidated, editable form state. No defaults here represent a user's dietary targets.
/// Only validGoal creates the immutable, validated GoalProfile used by the rest of the app.
public struct GoalInputDraft: Sendable, Equatable {
    public var energyKcal = ""
    public var proteinGrams = ""
    public var carbohydrateGrams = ""
    public var fatGrams = ""
    public var saturatedFatLimitGrams = ""
    public var fibreGrams = ""
    public var isConfirmed = false

    public init() {}

    /// Copies existing user data without rounding, supplying examples, or pre-confirming edits.
    /// Pass the same explicit decimal separator to validGoal when validating this form.
    public init(existingGoal: GoalProfile, decimalSeparator: String = ".") {
        self.init()
        energyKcal = Self.text(existingGoal.energyKcal, decimalSeparator: decimalSeparator)
        proteinGrams = Self.text(existingGoal.proteinGrams, decimalSeparator: decimalSeparator)
        carbohydrateGrams = Self.text(existingGoal.carbohydrateGrams, decimalSeparator: decimalSeparator)
        fatGrams = Self.text(existingGoal.fatGrams, decimalSeparator: decimalSeparator)
        saturatedFatLimitGrams = existingGoal.saturatedFatLimitGrams.map { Self.text($0, decimalSeparator: decimalSeparator) } ?? ""
        fibreGrams = existingGoal.fibreGrams.map { Self.text($0, decimalSeparator: decimalSeparator) } ?? ""
    }

    public func validGoal(id: UUID, effectiveFrom: Date, decimalSeparator: String = ".") throws -> GoalProfile {
        guard isConfirmed else { throw GoalInputError.confirmationRequired }
        guard decimalSeparator == "." || decimalSeparator == "," else {
            throw GoalInputError.unsupportedDecimalSeparator(decimalSeparator)
        }

        return try GoalProfile(
            id: id,
            effectiveFrom: effectiveFrom,
            energyKcal: Self.requiredNumber(energyKcal, field: "energyKcal", decimalSeparator: decimalSeparator),
            proteinGrams: Self.requiredNumber(proteinGrams, field: "proteinGrams", decimalSeparator: decimalSeparator),
            carbohydrateGrams: Self.requiredNumber(carbohydrateGrams, field: "carbohydrateGrams", decimalSeparator: decimalSeparator),
            fatGrams: Self.requiredNumber(fatGrams, field: "fatGrams", decimalSeparator: decimalSeparator),
            saturatedFatLimitGrams: Self.optionalNumber(saturatedFatLimitGrams, field: "saturatedFatLimitGrams", decimalSeparator: decimalSeparator),
            fibreGrams: Self.optionalNumber(fibreGrams, field: "fibreGrams", decimalSeparator: decimalSeparator)
        )
    }

    private static func requiredNumber(_ input: String, field: String, decimalSeparator: String) throws -> Double {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw GoalInputError.missingRequiredField(field) }
        return try number(trimmed, field: field, decimalSeparator: decimalSeparator)
    }

    private static func optionalNumber(_ input: String, field: String, decimalSeparator: String) throws -> Double? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return try number(trimmed, field: field, decimalSeparator: decimalSeparator)
    }

    private static func number(_ input: String, field: String, decimalSeparator: String) throws -> Double {
        // Recognize non-finite numeric tokens so GoalProfile emits its stable finite-value error.
        switch input.lowercased() {
        case "nan", "+nan", "-nan": return .nan
        case "inf", "+inf", "infinity", "+infinity": return .infinity
        case "-inf", "-infinity": return -.infinity
        default: break
        }

        // No grouping separators are accepted. A comma is a decimal only when explicitly chosen.
        let otherSeparator = decimalSeparator == "." ? "," : "."
        guard !input.contains(otherSeparator) else { throw GoalInputError.invalidNumber(field) }
        let normalized = input.replacingOccurrences(of: decimalSeparator, with: ".")
        let grammar = #"^[+-]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][+-]?[0-9]+)?$"#
        guard normalized.range(of: grammar, options: .regularExpression) != nil,
              let value = Double(normalized) else { throw GoalInputError.invalidNumber(field) }
        return value
    }

    private static func text(_ value: Double, decimalSeparator: String) -> String {
        // Double's round-trip representation avoids lossy number formatter rounding.
        String(value).replacingOccurrences(of: ".", with: decimalSeparator)
    }
}
