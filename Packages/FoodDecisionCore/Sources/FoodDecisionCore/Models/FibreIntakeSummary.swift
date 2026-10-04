/// Summarizes the fibre known in consumed component snapshots without treating unknown data as zero.
///
/// Supply individual meal component snapshots, not pre-aggregated meal totals: an unknown component
/// makes a meal's exact fibre total unknown, but its other components can still have known fibre.
/// This is a derived presentation value, not a replacement for `NutrientValues.sum` or stored data.
public struct FibreIntakeSummary: Equatable, Sendable {
    public let knownSubtotalGrams: Double?
    public let knownComponentCount: Int
    public let unknownComponentCount: Int

    public var totalComponentCount: Int {
        knownComponentCount + unknownComponentCount
    }

    public var hasRecords: Bool {
        totalComponentCount > 0
    }

    /// Completeness here describes fibre data in the supplied records, not daily meal coverage.
    /// With no records there is no confirmed fibre intake, including no confirmed zero.
    public var isComplete: Bool {
        hasRecords && unknownComponentCount == 0
    }

    public var exactGrams: Double? {
        isComplete ? knownSubtotalGrams : nil
    }

    public init(snapshots: [NutrientValues]) throws {
        var subtotal: Double?
        var knownCount = 0

        for snapshot in snapshots {
            guard let fibre = snapshot.fibreGrams else { continue }
            try DomainValidation.nonnegative(fibre, field: "fibreGrams")
            subtotal = try DomainValidation.add(subtotal ?? 0, fibre, field: "knownSubtotalGrams")
            knownCount += 1
        }

        knownSubtotalGrams = subtotal
        knownComponentCount = knownCount
        unknownComponentCount = snapshots.count - knownCount
    }
}
