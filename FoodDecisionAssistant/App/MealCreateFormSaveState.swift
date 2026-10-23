import FoodDecisionCore
import Foundation

enum MealCreateFormSaveStateError: Error, Equatable, LocalizedError {
    case alreadySaved

    var errorDescription: String? {
        "这餐已保存，之后的输入尚未保存。请先核对已保存记录再编辑；未新增另一餐，本次输入仍保留。"
    }
}

/// One presentation keeps one meal identity, including an uncertain-save retry.
/// Raw text remains owned by the existing form and is revalidated on every Save.
@MainActor
struct MealCreateFormSaveState {
    let mealID: UUID
    let sourceTemplateID: UUID?
    private(set) var pendingRequest: MealCreateRequest?
    private var pendingInput: FormDraftSnapshot?
    private var committedRequest: MealCreateRequest?
    private var committedInput: FormDraftSnapshot?

    var hasCommittedResult: Bool { committedRequest != nil }

    func canRetryCommittedRequest(comparedTo input: FormDraftSnapshot) -> Bool {
        committedRequest != nil && input == committedInput
    }

    init(mealID: UUID = UUID(), sourceTemplateID: UUID? = nil) {
        self.mealID = mealID
        self.sourceTemplateID = sourceTemplateID
    }

    mutating func invalidate() {
        pendingRequest = nil
        pendingInput = nil
    }

    mutating func handleSaveError(_ error: Error) {
        guard error as? MealCreateCommandError == .savedButRefreshFailed,
              let pendingRequest, let pendingInput else { return }
        committedRequest = pendingRequest
        committedInput = pendingInput
    }

    mutating func request(
        title: String,
        eatenAt: Date,
        entryMethod: MealEntryMethod,
        coverageStatus: MealCoverageStatus,
        rows: [MealFormComponentDraft],
        foods: [PersistentFoodItem],
        templateUsedAt: Date = .now
    ) throws -> MealCreateRequest {
        let input = FormDraftSnapshot.meal(
            title: title, eatenAt: eatenAt, entryMethod: entryMethod,
            coverageStatus: coverageStatus, components: rows
        )
        if let committedRequest {
            // Refresh retries must not recalculate a committed meal from a food
            // card that changed later, or silently discard subsequently edited text.
            guard input == committedInput else { throw MealCreateFormSaveStateError.alreadySaved }
            return committedRequest
        }
        // Never fall back to a previous valid request when the current raw input
        // is incomplete, invalid, or refers to an unavailable food.
        let components = try MealDraftValidation.components(from: rows.map(\.domainDraft), foods: foods)
        let meal = try MealLog(
            id: mealID, eatenAt: eatenAt, title: title, entryMethod: entryMethod,
            coverageStatus: coverageStatus, components: components
        )
        if let pendingRequest,
           pendingRequest.meal == meal,
           pendingRequest.sourceTemplateID == sourceTemplateID {
            pendingInput = input
            return pendingRequest
        }
        let request = MealCreateRequest(
            meal: meal, sourceTemplateID: sourceTemplateID, templateUsedAt: templateUsedAt
        )
        pendingRequest = request
        pendingInput = input
        return request
    }
}
