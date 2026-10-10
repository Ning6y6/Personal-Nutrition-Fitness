import Foundation

/// Daily target selection is deterministic and does not sample a clock or guess missing history.
public struct GoalSelectionPolicy: Equatable, Sendable {
    public static let v1 = GoalSelectionPolicy(version: 1)
    public let version: Int

    private init(version: Int) { self.version = version }

    public static func select(for day: GoalDay, versions: [GoalVersion]) throws -> GoalVersion? {
        try v1.select(for: day, versions: versions)
    }

    public func select(for day: GoalDay, versions: [GoalVersion]) throws -> GoalVersion? {
        var ids = Set<UUID>()
        var sequences = Set<Int>()
        var selected: GoalVersion?
        for candidate in versions {
            guard ids.insert(candidate.id).inserted else { throw GoalHistoryError.duplicateVersionID(candidate.id) }
            guard sequences.insert(candidate.commitSequence).inserted else {
                throw GoalHistoryError.duplicateCommitSequence(candidate.commitSequence)
            }
            guard candidate.policyVersion == version else {
                throw GoalHistoryError.unsupportedPolicyVersion(candidate.policyVersion)
            }
            guard candidate.effectiveDay <= day else { continue }
            if let current = selected {
                if candidate.effectiveDay > current.effectiveDay
                    || (candidate.effectiveDay == current.effectiveDay && candidate.commitSequence > current.commitSequence) {
                    selected = candidate
                }
            } else {
                selected = candidate
            }
        }
        return selected
    }
}
