import Foundation

/// Errors at the formal domain boundary. Raw historical storage is deliberately a separate layer.
public enum DomainValidationError: Error, Codable, Sendable, Equatable, LocalizedError {
    case nonFiniteValue(field: String)
    case invalidValue(field: String)
    case emptyText(field: String)
    case calculationOverflow(field: String)

    public var errorDescription: String? {
        switch self {
        case let .nonFiniteValue(field): "字段“\(field)”必须是有限数值。"
        case let .invalidValue(field): "字段“\(field)”的数值无效。"
        case let .emptyText(field): "字段“\(field)”不能为空。"
        case let .calculationOverflow(field): "字段“\(field)”的计算结果超出可表示范围。"
        }
    }
}

enum DomainValidation {
    static func nonnegative(_ value: Double, field: String) throws {
        guard value.isFinite else { throw DomainValidationError.nonFiniteValue(field: field) }
        guard value >= 0 else { throw DomainValidationError.invalidValue(field: field) }
    }

    static func positive(_ value: Double, field: String) throws {
        guard value.isFinite else { throw DomainValidationError.nonFiniteValue(field: field) }
        guard value > 0 else { throw DomainValidationError.invalidValue(field: field) }
    }

    static func text(_ value: String, field: String) throws {
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DomainValidationError.emptyText(field: field)
        }
    }

    static func date(_ value: Date, field: String) throws {
        guard value.timeIntervalSinceReferenceDate.isFinite else {
            throw DomainValidationError.nonFiniteValue(field: field)
        }
    }

    static func add(_ lhs: Double, _ rhs: Double, field: String) throws -> Double {
        let result = lhs + rhs
        guard result.isFinite else { throw DomainValidationError.calculationOverflow(field: field) }
        return result
    }

    static func multiply(_ lhs: Double, _ rhs: Double, field: String) throws -> Double {
        let result = lhs * rhs
        guard result.isFinite else { throw DomainValidationError.calculationOverflow(field: field) }
        return result
    }

    /// Allows round-off from previously saved decimal totals, never a material discrepancy.
    static func approximatelyEqual(_ lhs: Double, _ rhs: Double) -> Bool {
        abs(lhs - rhs) <= max(1, max(abs(lhs), abs(rhs))) * 1e-9
    }
}
