import Foundation
import Testing
@testable import FoodDecisionCore

struct GoalInputDraftTests {
    private let profileID = UUID(uuid: (1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16))
    private let effectiveFrom = Date(timeIntervalSince1970: 1_700_000_000)

    @Test("A new target form is empty and unconfirmed, not populated with example or medical values")
    func newDraftIsEmpty() {
        let draft = GoalInputDraft()
        #expect(draft.energyKcal.isEmpty == true)
        #expect(draft.proteinGrams.isEmpty == true)
        #expect(draft.carbohydrateGrams.isEmpty == true)
        #expect(draft.fatGrams.isEmpty == true)
        #expect(draft.saturatedFatLimitGrams.isEmpty == true)
        #expect(draft.fibreGrams.isEmpty == true)
        #expect(draft.isConfirmed == false)
    }

    @Test("Entering all values does not implicitly confirm a goal")
    func explicitConfirmationIsRequired() {
        var draft = validDraft()
        draft.isConfirmed = false
        #expect(throws: GoalInputError.confirmationRequired) {
            try draft.validGoal(id: profileID, effectiveFrom: effectiveFrom)
        }
    }

    @Test("Each required target rejects whitespace-only input", arguments: ["energyKcal", "proteinGrams", "carbohydrateGrams", "fatGrams"])
    func requiredFieldsCannotBeMissing(field: String) {
        var draft = validDraft()
        set(" \n", field: field, in: &draft)
        #expect(throws: GoalInputError.missingRequiredField(field)) {
            try draft.validGoal(id: profileID, effectiveFrom: effectiveFrom)
        }
    }

    @Test("Malformed text and grouped numbers are never silently truncated", arguments: ["energyKcal", "proteinGrams", "carbohydrateGrams", "fatGrams", "saturatedFatLimitGrams", "fibreGrams"], ["abc", "2,000", "1 000", "1_000", "1.2.3", "12 kcal", "0x10", "5%"])
    func invalidNumericText(field: String, text: String) {
        var draft = validDraft()
        set(text, field: field, in: &draft)
        #expect(throws: GoalInputError.invalidNumber(field)) {
            try draft.validGoal(id: profileID, effectiveFrom: effectiveFrom)
        }
    }

    @Test("NaN and infinity go through the same finite boundary as direct GoalProfile input", arguments: ["energyKcal", "proteinGrams", "carbohydrateGrams", "fatGrams", "saturatedFatLimitGrams", "fibreGrams"], ["NaN", "Inf", "-Infinity", "1e309"])
    func nonFiniteInput(field: String, text: String) {
        var draft = validDraft()
        set(text, field: field, in: &draft)
        #expect(throws: DomainValidationError.nonFiniteValue(field: field)) {
            try draft.validGoal(id: profileID, effectiveFrom: effectiveFrom)
        }
    }

    @Test("Negative targets are rejected without clamping", arguments: ["energyKcal", "proteinGrams", "carbohydrateGrams", "fatGrams", "saturatedFatLimitGrams", "fibreGrams"])
    func negativeInput(field: String) {
        var draft = validDraft()
        set("-0.5", field: field, in: &draft)
        #expect(throws: DomainValidationError.invalidValue(field: field)) {
            try draft.validGoal(id: profileID, effectiveFrom: effectiveFrom)
        }
    }

    @Test("Energy must be positive while explicitly entered zero macro targets remain zero")
    func energyZeroAndExplicitMacroZero() throws {
        var draft = validDraft()
        draft.energyKcal = "0"
        #expect(throws: DomainValidationError.invalidValue(field: "energyKcal")) {
            try draft.validGoal(id: profileID, effectiveFrom: effectiveFrom)
        }
        draft.energyKcal = "1"
        draft.proteinGrams = "0"
        draft.carbohydrateGrams = "0"
        draft.fatGrams = "0"
        let goal = try draft.validGoal(id: profileID, effectiveFrom: effectiveFrom)
        #expect(goal.proteinGrams == 0)
        #expect(goal.carbohydrateGrams == 0)
        #expect(goal.fatGrams == 0)
    }

    @Test("Blank optional targets stay nil, and explicit zero stays a known zero")
    func optionalTargetsPreserveNilVersusZero() throws {
        var draft = validDraft()
        draft.saturatedFatLimitGrams = " \n"
        draft.fibreGrams = ""
        let unknown = try draft.validGoal(id: profileID, effectiveFrom: effectiveFrom)
        #expect(unknown.saturatedFatLimitGrams == nil)
        #expect(unknown.fibreGrams == nil)
        draft.saturatedFatLimitGrams = "0"
        draft.fibreGrams = "0.0"
        let known = try draft.validGoal(id: profileID, effectiveFrom: effectiveFrom)
        #expect(known.saturatedFatLimitGrams == 0)
        #expect(known.fibreGrams == 0)
    }

    @Test("Existing targets prefill their exact values but still require fresh confirmation")
    func existingGoalIsNotPreconfirmed() throws {
        let oldGoal = try GoalProfile(id: profileID, effectiveFrom: effectiveFrom, energyKcal: 2_000.5, proteinGrams: 125.25, carbohydrateGrams: 0, fatGrams: 50, saturatedFatLimitGrams: 0, fibreGrams: nil)
        var draft = GoalInputDraft(existingGoal: oldGoal)
        #expect(draft.isConfirmed == false)
        #expect(draft.fibreGrams.isEmpty == true)
        #expect(throws: GoalInputError.confirmationRequired) {
            try draft.validGoal(id: profileID, effectiveFrom: effectiveFrom)
        }
        draft.isConfirmed = true
        #expect(try draft.validGoal(id: profileID, effectiveFrom: effectiveFrom) == oldGoal)
    }

    @Test("Prefilling an unchanged valid target does not round away stored precision")
    func existingPrecisionIsPreserved() throws {
        let oldGoal = try GoalProfile(id: profileID, effectiveFrom: effectiveFrom, energyKcal: Double(2_000).nextUp, proteinGrams: Double(0.1).nextUp, carbohydrateGrams: 0, fatGrams: Double(50).nextDown, saturatedFatLimitGrams: Double.leastNonzeroMagnitude, fibreGrams: Double(0.3).nextUp)
        var draft = GoalInputDraft(existingGoal: oldGoal)
        draft.isConfirmed = true
        #expect(try draft.validGoal(id: profileID, effectiveFrom: effectiveFrom) == oldGoal)
        var commaDraft = GoalInputDraft(existingGoal: oldGoal, decimalSeparator: ",")
        commaDraft.isConfirmed = true
        #expect(try commaDraft.validGoal(id: profileID, effectiveFrom: effectiveFrom, decimalSeparator: ",") == oldGoal)
    }

    @Test("Dot decimal input preserves fractional quantities and supplied identity/time")
    func decimalInput() throws {
        var draft = validDraft()
        draft.energyKcal = " 2000.5 "
        draft.proteinGrams = "125.25"
        draft.carbohydrateGrams = ".5"
        draft.fatGrams = "50."
        draft.fibreGrams = "3.75"
        let goal = try draft.validGoal(id: profileID, effectiveFrom: effectiveFrom, decimalSeparator: ".")
        #expect(goal.id == profileID)
        #expect(goal.effectiveFrom == effectiveFrom)
        #expect(goal.energyKcal == 2_000.5)
        #expect(goal.proteinGrams == 125.25)
        #expect(goal.carbohydrateGrams == 0.5)
        #expect(goal.fatGrams == 50)
        #expect(goal.fibreGrams == 3.75)
    }

    @Test("The selected decimal separator is explicit, with no automatic grouping/locale guessing")
    func commaDecimalInput() throws {
        var draft = validDraft()
        draft.energyKcal = "2000,5"
        draft.proteinGrams = "125,25"
        draft.carbohydrateGrams = "0,5"
        draft.fatGrams = "50"
        let goal = try draft.validGoal(id: profileID, effectiveFrom: effectiveFrom, decimalSeparator: ",")
        #expect(goal.energyKcal == 2_000.5)
        #expect(goal.proteinGrams == 125.25)
        #expect(goal.carbohydrateGrams == 0.5)
        let existingDraft = GoalInputDraft(existingGoal: goal, decimalSeparator: ",")
        #expect(existingDraft.energyKcal == "2000,5")
        #expect(existingDraft.isConfirmed == false)
        draft.energyKcal = "2.000,5"
        #expect(throws: GoalInputError.invalidNumber("energyKcal")) {
            try draft.validGoal(id: profileID, effectiveFrom: effectiveFrom, decimalSeparator: ",")
        }
    }

    @Test("Unknown decimal separators are rejected", arguments: ["", "..", ":", "0"])
    func invalidSeparator(separator: String) {
        #expect(throws: GoalInputError.unsupportedDecimalSeparator(separator)) {
            try validDraft().validGoal(id: profileID, effectiveFrom: effectiveFrom, decimalSeparator: separator)
        }
    }

    private func validDraft() -> GoalInputDraft {
        var draft = GoalInputDraft()
        draft.energyKcal = "2000"
        draft.proteinGrams = "125"
        draft.carbohydrateGrams = "200"
        draft.fatGrams = "50"
        draft.isConfirmed = true
        return draft
    }

    private func set(_ text: String, field: String, in draft: inout GoalInputDraft) {
        switch field {
        case "energyKcal": draft.energyKcal = text
        case "proteinGrams": draft.proteinGrams = text
        case "carbohydrateGrams": draft.carbohydrateGrams = text
        case "fatGrams": draft.fatGrams = text
        case "saturatedFatLimitGrams": draft.saturatedFatLimitGrams = text
        case "fibreGrams": draft.fibreGrams = text
        default: Issue.record("Unknown target field in test fixture: \(field)")
        }
    }
}
