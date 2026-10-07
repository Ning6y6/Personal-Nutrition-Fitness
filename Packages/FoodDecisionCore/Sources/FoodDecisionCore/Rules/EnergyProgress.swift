import Foundation

public enum EnergyProgressStatus: String, Codable, Sendable, Equatable {
    case withinTarget = "within_target"
    case overTarget = "over_target"
    case significantlyOverTarget = "significantly_over_target"
    case unset, unavailable, invalidInput
}

public struct EnergyProgressSummary: Codable, Sendable, Equatable {
    public let nutritionProgress: NutritionProgressSummary
    public let consumedKcal: Double?
    public let targetKcal: Double?
    public let ratio: Double?
    public let ratioIsSaturated: Bool
    public let ringProgress: Double?
    public let remainingKcal: Double?
    public let overageKcal: Double?
    public let status: EnergyProgressStatus

    /// The first lap and overflow lap are presentation only; intake is never clamped.
    public var baseLap: Double? { ratio.map { min($0, 1) } }
    public var overflowLap: Double? { ratio.map { min(max($0 - 1, 0), 1) } }
    public var multiple: Double? { ratio }

    init(nutritionProgress: NutritionProgressSummary) {
        self.nutritionProgress = nutritionProgress
        consumedKcal = nutritionProgress.consumed
        targetKcal = nutritionProgress.target
        ringProgress = nutritionProgress.progress
        remainingKcal = nutritionProgress.remaining
        overageKcal = nutritionProgress.overage
        switch nutritionProgress.status {
        case .withinBudget, .atBudget: status = .withinTarget
        case .overBudget: status = .overTarget
        case .significantlyOverBudget: status = .significantlyOverTarget
        case .unset: status = .unset
        case .invalidInput: status = .invalidInput
        default: status = .unavailable
        }
        if let consumed = consumedKcal, let target = targetKcal, target > 0, nutritionProgress.progress != nil {
            if consumed <= target {
                ratio = consumed / target
                ratioIsSaturated = false
            } else {
                let inverseRatio = target / consumed
                // The compatibility ratio is display-only. Saturation is explicit, not infinity.
                if inverseRatio <= 0 || inverseRatio < 1 / Double.greatestFiniteMagnitude {
                    ratio = .greatestFiniteMagnitude
                    ratioIsSaturated = true
                } else {
                    let candidate = 1 / inverseRatio
                    ratio = candidate.isFinite ? candidate : .greatestFiniteMagnitude
                    ratioIsSaturated = !candidate.isFinite
                }
            }
        } else {
            ratio = nil
            ratioIsSaturated = false
        }
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let progress = try container.decode(NutritionProgressSummary.self, forKey: .nutritionProgress)
        guard progress.semantics == .budget, progress.target != 0 || progress.status == .invalidInput else {
            throw NutritionDisplayPolicyError.invalidSummary
        }
        let expected = Self(nutritionProgress: progress)
        guard try container.decodeIfPresent(Double.self, forKey: .consumedKcal) == expected.consumedKcal,
              try container.decodeIfPresent(Double.self, forKey: .targetKcal) == expected.targetKcal,
              try container.decodeIfPresent(Double.self, forKey: .ratio) == expected.ratio,
              try container.decode(Bool.self, forKey: .ratioIsSaturated) == expected.ratioIsSaturated,
              try container.decodeIfPresent(Double.self, forKey: .ringProgress) == expected.ringProgress,
              try container.decodeIfPresent(Double.self, forKey: .remainingKcal) == expected.remainingKcal,
              try container.decodeIfPresent(Double.self, forKey: .overageKcal) == expected.overageKcal,
              try container.decode(EnergyProgressStatus.self, forKey: .status) == expected.status else {
            throw NutritionDisplayPolicyError.invalidSummary
        }
        self = expected
    }
}

public struct EnergyProgressPolicy: Codable, Sendable, Equatable {
    public static let v1 = EnergyProgressPolicy(displayPolicy: .v1)
    public static let v2 = EnergyProgressPolicy(displayPolicy: .v2)
    public static let standard = v2
    public let displayPolicy: NutritionDisplayPolicy
    public var significantOverageRatio: Double { displayPolicy.budgetSignificantOverageRatio }

    public init(displayPolicy: NutritionDisplayPolicy) {
        self.displayPolicy = displayPolicy
    }

    public init(significantOverageRatio: Double) throws {
        displayPolicy = try NutritionDisplayPolicy(upperWarningRatio: NutritionDisplayPolicy.v1.upperWarningRatio, budgetSignificantOverageRatio: significantOverageRatio)
    }

    public func evaluate(consumedKcal: Double?, targetKcal: Double?) -> EnergyProgressSummary {
        var progress = displayPolicy.evaluate(consumed: consumedKcal, target: targetKcal, semantics: .budget)
        // An energy target, unlike a zero macro budget, must be strictly positive.
        if targetKcal == 0, progress.status != .invalidInput {
            progress = displayPolicy.invalid(consumed: progress.consumed, target: 0, semantics: .budget, issue: .nonPositiveEnergyTarget)
        }
        return EnergyProgressSummary(nutritionProgress: progress)
    }

    private enum CodingKeys: String, CodingKey { case displayPolicy, significantOverageRatio }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if container.contains(.displayPolicy) {
            guard !container.contains(.significantOverageRatio) else { throw NutritionDisplayPolicyError.invalidSummary }
            self.init(displayPolicy: try container.decode(NutritionDisplayPolicy.self, forKey: .displayPolicy))
        } else {
            try self.init(significantOverageRatio: container.decode(Double.self, forKey: .significantOverageRatio))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(displayPolicy, forKey: .displayPolicy)
    }
}
