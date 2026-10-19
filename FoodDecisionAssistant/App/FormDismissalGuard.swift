/// A per-presentation baseline. Owned with @State so parent redraws cannot replace it.
/// No save, rollback or database access belongs in the cancellation decision.
struct FormDismissalGuard {
    private(set) var baseline: FormDraftSnapshot
    var isConfirmingDiscard = false

    private let allowsEmptyNewDraftCancellation: Bool

    init(baseline: FormDraftSnapshot, allowsEmptyNewDraftCancellation: Bool = false) {
        self.baseline = baseline
        self.allowsEmptyNewDraftCancellation = allowsEmptyNewDraftCancellation
    }

    func hasUnsavedChanges(comparedTo current: FormDraftSnapshot) -> Bool {
        current != baseline
    }

    /// A fresh blank form with all rows removed has no remaining component inputs to discard.
    /// This only relaxes cancellation; strict change detection and load protection stay intact.
    func hasChangesRequiringDiscard(comparedTo current: FormDraftSnapshot) -> Bool {
        if allowsEmptyNewDraftCancellation,
           let emptyNewDraft = baseline.removingInitialEmptyPlaceholder,
           current == emptyNewDraft {
            return false
        }
        return hasUnsavedChanges(comparedTo: current)
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
        isConfirmingDiscard = false
    }
}
