import Foundation

public enum NutritionGoalSemantics: String, Codable, CaseIterable, Sendable, Equatable {
    case minimum, budget, maximum
}

public enum NutritionGoalMetric: String, Codable, CaseIterable, Sendable, Equatable {
    case energy, protein, carbohydrate, fat, saturatedFat, fibre

    public var semantics: NutritionGoalSemantics {
        switch self {
        case .protein, .fibre: .minimum
        case .energy, .carbohydrate, .fat: .budget
        case .saturatedFat: .maximum
        }
    }
}

public enum NutritionProgressStatus: String, Codable, Sendable, Equatable {
    case belowMinimum, minimumMet
    case withinBudget, atBudget, overBudget, significantlyOverBudget
    case belowMaximum, approachingMaximum, atMaximum, overMaximum
    case unset, unavailable, invalidInput
}

public enum NutritionProgressIssue: String, Codable, Sendable, Equatable {
    case nonFiniteConsumed, negativeConsumed, nonFiniteTarget, negativeTarget
    case unknownConsumed, unsetTarget, nonPositiveEnergyTarget
}

public enum NutritionDisplayPolicyError: Error, Sendable, Equatable {
    case unsupportedVersion(Int)
    case invalidSummary
}

/// Interpretation and thresholds travel together; v1 is not a medical recommendation.
public struct NutritionDisplayPolicy: Codable, Sendable, Equatable {
    public static let v1 = NutritionDisplayPolicy(v1: ())
    public let version: Int
    public let upperWarningRatio: Double
    public let budgetSignificantOverageRatio: Double

    private init(v1: ()) {
        version = 1
        upperWarningRatio = 0.80
        budgetSignificantOverageRatio = 1.10
    }

    public init(version: Int = 1, upperWarningRatio: Double, budgetSignificantOverageRatio: Double) throws {
        guard version == 1 else { throw NutritionDisplayPolicyError.unsupportedVersion(version) }
        try DomainValidation.nonnegative(upperWarningRatio, field: "upperWarningRatio")
        guard upperWarningRatio > 0, upperWarningRatio < 1 else {
            throw DomainValidationError.invalidValue(field: "upperWarningRatio")
        }
        try DomainValidation.positive(budgetSignificantOverageRatio, field: "budgetSignificantOverageRatio")
        guard budgetSignificantOverageRatio > 1 else {
            throw DomainValidationError.invalidValue(field: "budgetSignificantOverageRatio")
        }
        self.version = version
        self.upperWarningRatio = upperWarningRatio
        self.budgetSignificantOverageRatio = budgetSignificantOverageRatio
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(version: container.decode(Int.self, forKey: .version), upperWarningRatio: container.decode(Double.self, forKey: .upperWarningRatio), budgetSignificantOverageRatio: container.decode(Double.self, forKey: .budgetSignificantOverageRatio))
    }

    public func evaluate(consumed: Double?, target: Double?, semantics: NutritionGoalSemantics) -> NutritionProgressSummary {
        let safeConsumed = consumed.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
        let safeTarget = target.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
        if let consumed, !consumed.isFinite {
            return invalid(consumed: safeConsumed, target: safeTarget, semantics: semantics, issue: .nonFiniteConsumed)
        }
        if let consumed, consumed < 0 {
            return invalid(consumed: safeConsumed, target: safeTarget, semantics: semantics, issue: .negativeConsumed)
        }
        if let target, !target.isFinite {
            return invalid(consumed: safeConsumed, target: safeTarget, semantics: semantics, issue: .nonFiniteTarget)
        }
        if let target, target < 0 {
            return invalid(consumed: safeConsumed, target: safeTarget, semantics: semantics, issue: .negativeTarget)
        }
        guard let consumed else {
            return summary(consumed: nil, target: target, semantics: semantics, status: .unavailable, issue: .unknownConsumed)
        }
        guard let target else {
            return summary(consumed: consumed, target: nil, semantics: semantics, status: .unset, issue: .unsetTarget)
        }
        // Only divide when the result is bounded by one. Explicit zero never means nil.
        let progress = target == 0 || consumed >= target ? 1 : consumed / target
        let remaining = max(target - consumed, 0)
        let overage = semantics == .minimum ? nil : max(consumed - target, 0)
        let status: NutritionProgressStatus
        switch semantics {
        case .minimum:
            status = consumed >= target ? .minimumMet : .belowMinimum
        case .maximum:
            if consumed > target { status = .overMaximum }
            else if consumed == target { status = .atMaximum }
            else if progress >= upperWarningRatio { status = .approachingMaximum }
            else { status = .belowMaximum }
        case .budget:
            if consumed < target { status = .withinBudget }
            else if consumed == target { status = .atBudget }
            else if target == 0 || consumed / budgetSignificantOverageRatio > target {
                // Division by a finite number >1 cannot overflow, unlike target * ratio.
                status = .significantlyOverBudget
            } else { status = .overBudget }
        }
        return NutritionProgressSummary(consumed: consumed, target: target, semantics: semantics, status: status, progress: progress, remaining: remaining, overage: overage, displayPolicy: self, issue: nil)
    }

    func invalid(consumed: Double?, target: Double?, semantics: NutritionGoalSemantics, issue: NutritionProgressIssue) -> NutritionProgressSummary {
        summary(consumed: consumed, target: target, semantics: semantics, status: .invalidInput, issue: issue)
    }

    private func summary(consumed: Double?, target: Double?, semantics: NutritionGoalSemantics, status: NutritionProgressStatus, issue: NutritionProgressIssue) -> NutritionProgressSummary {
        NutritionProgressSummary(consumed: consumed, target: target, semantics: semantics, status: status, progress: nil, remaining: nil, overage: nil, displayPolicy: self, issue: issue)
    }
}

/// Derived output. Invalid or unavailable data cannot carry fabricated progress.
public struct NutritionProgressSummary: Codable, Sendable, Equatable {
    public let consumed: Double?
    public let target: Double?
    public let semantics: NutritionGoalSemantics
    public let status: NutritionProgressStatus
    public let progress: Double?
    public let remaining: Double?
    public let overage: Double?
    public let displayPolicy: NutritionDisplayPolicy
    public let policyVersion: Int
    public let issue: NutritionProgressIssue?

    init(consumed: Double?, target: Double?, semantics: NutritionGoalSemantics, status: NutritionProgressStatus, progress: Double?, remaining: Double?, overage: Double?, displayPolicy: NutritionDisplayPolicy, issue: NutritionProgressIssue?) {
        self.consumed = consumed
        self.target = target
        self.semantics = semantics
        self.status = status
        self.progress = progress
        self.remaining = remaining
        self.overage = overage
        self.displayPolicy = displayPolicy
        policyVersion = displayPolicy.version
        self.issue = issue
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let policy = try container.decode(NutritionDisplayPolicy.self, forKey: .displayPolicy)
        let consumed = try container.decodeIfPresent(Double.self, forKey: .consumed)
        let target = try container.decodeIfPresent(Double.self, forKey: .target)
        let progress = try container.decodeIfPresent(Double.self, forKey: .progress)
        let remaining = try container.decodeIfPresent(Double.self, forKey: .remaining)
        let overage = try container.decodeIfPresent(Double.self, forKey: .overage)
        for (field, value) in [("consumed", consumed), ("target", target), ("progress", progress), ("remaining", remaining), ("overage", overage)] {
            if let value { try DomainValidation.nonnegative(value, field: field) }
        }
        if let progress, progress > 1 { throw NutritionDisplayPolicyError.invalidSummary }
        let semantics = try container.decode(NutritionGoalSemantics.self, forKey: .semantics)
        let status = try container.decode(NutritionProgressStatus.self, forKey: .status)
        let issue = try container.decodeIfPresent(NutritionProgressIssue.self, forKey: .issue)
        let expected: NutritionProgressSummary
        if status == .invalidInput {
            switch issue {
            case .nonFiniteConsumed, .negativeConsumed:
                guard consumed == nil else { throw NutritionDisplayPolicyError.invalidSummary }
            case .nonFiniteTarget, .negativeTarget:
                guard target == nil else { throw NutritionDisplayPolicyError.invalidSummary }
            case .nonPositiveEnergyTarget:
                guard semantics == .budget, target == 0 else { throw NutritionDisplayPolicyError.invalidSummary }
            default: throw NutritionDisplayPolicyError.invalidSummary
            }
            guard let issue else { throw NutritionDisplayPolicyError.invalidSummary }
            expected = policy.invalid(consumed: consumed, target: target, semantics: semantics, issue: issue)
        } else {
            expected = policy.evaluate(consumed: consumed, target: target, semantics: semantics)
        }
        guard status == expected.status, issue == expected.issue,
              progress == expected.progress, remaining == expected.remaining, overage == expected.overage,
              try container.decode(Int.self, forKey: .policyVersion) == policy.version else {
            throw NutritionDisplayPolicyError.invalidSummary
        }
        self = expected
    }
}
