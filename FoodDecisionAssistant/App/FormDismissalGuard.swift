/// A per-presentation baseline. Owned with @State so parent redraws cannot replace it.
/// No save, rollback or database access belongs in the cancellation decision.
struct FormDismissalGuard {
    private(set) var baseline: FormDraftSnapshot
    var isConfirmingDiscard = false

    private let allowsInitialPlaceholderRemoval: Bool
    private var removedInitialPlaceholderSnapshot: FormDraftSnapshot?

    init(baseline: FormDraftSnapshot, allowsInitialPlaceholderRemoval: Bool = false) {
        self.baseline = baseline
        self.allowsInitialPlaceholderRemoval = allowsInitialPlaceholderRemoval
    }

    func hasUnsavedChanges(comparedTo current: FormDraftSnapshot) -> Bool {
        current != baseline
    }

    /// Only cancellation can ignore the deliberate removal of an untouched placeholder.
    /// Strict change detection and load protection still compare against the original baseline.
    func hasChangesRequiringDiscard(comparedTo current: FormDraftSnapshot) -> Bool {
        if let removedInitialPlaceholderSnapshot, current == removedInitialPlaceholderSnapshot {
            return false
        }
        return hasUnsavedChanges(comparedTo: current)
    }

    /// Every deletion replaces the prior exception, including deletion of later typed inputs.
    mutating func recordComponentRemoval(from previous: FormDraftSnapshot, to current: FormDraftSnapshot) {
        removedInitialPlaceholderSnapshot = nil
        guard allowsInitialPlaceholderRemoval,
              previous == baseline,
              let withoutPlaceholder = baseline.removingInitialEmptyPlaceholder,
              current == withoutPlaceholder else { return }
        removedInitialPlaceholderSnapshot = current
    }

    /// A load retry must never overwrite edited inputs or reclassify them as saved data.
    func canLoadInitialValues(comparedTo current: FormDraftSnapshot) -> Bool {
        !hasUnsavedChanges(comparedTo: current)
    }

    /// True means the caller can dismiss immediately; false presents the discard dialog.
    mutating func requestCancellation(comparedTo current: FormDraftSnapshot) -> Bool {
        isConfirmingDiscard = hasChangesRequiringDiscard(comparedTo: current)
        return !isConfirmingDiscard
    }

    /// Only for synchronous initial loading, never after a failed save or a redraw.
    mutating func resetBaseline(to snapshot: FormDraftSnapshot) {
        baseline = snapshot
        removedInitialPlaceholderSnapshot = nil
        isConfirmingDiscard = false
    }
}
