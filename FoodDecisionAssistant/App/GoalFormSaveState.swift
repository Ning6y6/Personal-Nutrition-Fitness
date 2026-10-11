import FoodDecisionCore
import Foundation

/// Transient retry state for the goal form. Only an explicit Save calls request.
struct GoalFormSaveState: Sendable {
    private(set) var pendingRequest: GoalVersionSaveRequest? = nil

    mutating func invalidate() {
        pendingRequest = nil
    }

    /// Confirms a value copy at the Save boundary without confirming the editable draft.
    /// Compare the full current payload here too: a change observer may not have run yet.
    mutating func request(
        draft: GoalInputDraft,
        effectiveDay: GoalDay,
        source: GoalSource,
        sourceNote: String?,
        timeZoneIdentifier: String,
        expectedBaseline: GoalHistoryBaseline,
        decimalSeparator: String,
        confirmedAt: Date = .now,
        operationID: UUID = UUID()
    ) -> GoalVersionSaveRequest {
        var confirmedDraft = draft
        confirmedDraft.isConfirmed = true
        if let pendingRequest,
           pendingRequest.draft == confirmedDraft,
           pendingRequest.effectiveDay == effectiveDay,
           pendingRequest.source == source,
           pendingRequest.sourceNote == sourceNote,
           pendingRequest.timeZoneIdentifier == timeZoneIdentifier,
           pendingRequest.expectedBaseline == expectedBaseline,
           pendingRequest.decimalSeparator == decimalSeparator {
            return pendingRequest
        }
        let request = GoalVersionSaveRequest(
            draft: confirmedDraft,
            effectiveDay: effectiveDay,
            source: source,
            sourceNote: sourceNote,
            timeZoneIdentifier: timeZoneIdentifier,
            confirmedAt: confirmedAt,
            operationID: operationID,
            expectedBaseline: expectedBaseline,
            decimalSeparator: decimalSeparator
        )
        pendingRequest = request
        return request
    }
}
