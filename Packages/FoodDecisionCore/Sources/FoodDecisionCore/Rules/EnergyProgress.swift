import Foundation

public enum EnergyProgressStatus: String, Codable, Sendable, Equatable {
    case withinTarget = "within_target"
    case overTarget = "over_target"
    case significantlyOverTarget = "significantly_over_target"
}

public struct EnergyProgressSummary: Codable, Sendable, Equatable {
    public let consumedKcal: Double
    public let targetKcal: Double
    public let ratio: Double
    public let ringProgress: Double
    public let remainingKcal: Double
    public let overageKcal: Double
    public let status: EnergyProgressStatus
}

public struct EnergyProgressPolicy: Codable, Sendable, Equatable {
    public static let standard = EnergyProgressPolicy(significantOverageRatio: 1.10)

    public let significantOverageRatio: Double

    public init(significantOverageRatio: Double) {
        precondition(significantOverageRatio > 1)
        self.significantOverageRatio = significantOverageRatio
    }

    public func evaluate(consumedKcal: Double, targetKcal: Double) -> EnergyProgressSummary {
        let safeConsumed = max(consumedKcal, 0)
        let safeTarget = max(targetKcal, 0)
        let ratio = safeTarget > 0 ? safeConsumed / safeTarget : 0

        let status: EnergyProgressStatus
        if ratio <= 1 {
            status = .withinTarget
        } else if ratio <= significantOverageRatio {
            status = .overTarget
        } else {
            status = .significantlyOverTarget
        }

        return EnergyProgressSummary(
            consumedKcal: safeConsumed,
            targetKcal: safeTarget,
            ratio: ratio,
            ringProgress: min(ratio, 1),
            remainingKcal: max(safeTarget - safeConsumed, 0),
            overageKcal: max(safeConsumed - safeTarget, 0),
            status: status
        )
    }
}
