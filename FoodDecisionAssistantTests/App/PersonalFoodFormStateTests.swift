import FoodDecisionCore
import Foundation
import Testing
@testable import FoodDecisionAssistant

@MainActor
struct PersonalFoodFormStateTests {
    @Test("Search-prefilled names are the cancellation baseline, with no numeric defaults")
    func prefilledSearchIsNotAnEdit() {
        let state = PersonalFoodFormState(initialName: "验收测试蜂蜜", decimalSeparator: ".")
        #expect(state.hasUnsavedChanges == false)
        #expect(state.pendingRequest == nil)
        #expect(state.draft.name == "验收测试蜂蜜")
        #expect(state.draft.energyKcal.isEmpty)
        #expect(state.draft.fatGrams.isEmpty)
        #expect(state.draft.saturatedFatGrams.isEmpty)
        #expect(state.draft.carbohydrateGrams.isEmpty)
        #expect(state.draft.sugarGrams.isEmpty)
        #expect(state.draft.proteinGrams.isEmpty)
        #expect(state.draft.saltGrams.isEmpty)
        #expect(state.draft.fibreGrams.isEmpty)
    }

    @Test("Every raw input change invalidates retry data before an observer runs", arguments: [
        "name", "category", "sourceNote", "energy", "fat", "saturatedFat", "carbohydrate",
        "sugar", "protein", "salt", "fibre", "numericFormatting", "noteWhitespace"
    ])
    func allInputsInvalidatePendingRequest(field: String) throws {
        var state = makeCompleteState()
        let first = try state.request()
        try #require(state.pendingRequest == first)
        let oldDraft = state.draft
        switch field {
        case "name": state.draft.name = "验收测试蛋白粉改名"
        case "category": state.draft.category = .proteinMain
        case "sourceNote": state.draft.sourceNote = "新包装"
        case "energy": state.draft.energyKcal = "450"
        case "fat": state.draft.fatGrams = "7"
        case "saturatedFat": state.draft.saturatedFatGrams = "3"
        case "carbohydrate": state.draft.carbohydrateGrams = "11"
        case "sugar": state.draft.sugarGrams = "4"
        case "protein": state.draft.proteinGrams = "81"
        case "salt": state.draft.saltGrams = "0.6"
        case "fibre": state.draft.fibreGrams = "0"
        case "numericFormatting": state.draft.energyKcal = "400.0"
        case "noteWhitespace": state.draft.sourceNote = " 包装说明 "
        default: Issue.record("Unexpected input mutation: \(field)")
        }
        #expect(state.draft != oldDraft)
        #expect(state.pendingRequest == nil)
        let replacement = try state.request()
        #expect(replacement.food == (try state.validFood()))
        #expect(replacement.food.id == first.food.id)
        #expect(state.pendingRequest == replacement)
    }

    @Test("An unchanged retry keeps the food identity and complete submitted payload")
    func unchangedRetryUsesSameCard() throws {
        var state = makeCompleteState()
        let before = state.draft
        let first = try state.request()
        let second = try state.request()
        #expect(first == second)
        #expect(first.food.id == state.foodID)
        #expect(first.intent == .create)
        #expect(state.draft == before)
        #expect(state.hasUnsavedChanges)
    }

    @Test("Invalid or removed required text remains a protected unsaved edit", arguments: [".", "<0.1", "Tr", ""])
    func invalidRawTextIsNotDiscarded(rawText: String) throws {
        let original = try makeCompleteState().validFood()
        var state = try PersonalFoodFormState(originalFood: original, decimalSeparator: ".")
        let baseline = state.draft
        try #require(state.hasUnsavedChanges == false)
        state.draft.saltGrams = rawText
        #expect(state.hasUnsavedChanges)
        #expect(state.draft.saltGrams == rawText)
        if rawText.isEmpty {
            #expect(throws: PersonalFoodInputError.missingRequiredField("saltGrams")) { try state.request() }
        } else {
            #expect(throws: PersonalFoodInputError.invalidNumber("saltGrams")) { try state.request() }
        }
        #expect(state.pendingRequest == nil)
        #expect(state.draft.saltGrams == rawText)
        #expect(state.draft.name == baseline.name)
        #expect(state.draft.energyKcal == baseline.energyKcal)
        state.draft = baseline
        #expect(state.hasUnsavedChanges == false)
    }

    @Test("A failed request changed to invalid input cannot reuse the previously valid food")
    func invalidInputAfterRequestCannotSaveOldValues() throws {
        var state = makeCompleteState()
        let first = try state.request()
        state.draft.energyKcal = "."
        #expect(state.pendingRequest == nil)
        #expect(throws: PersonalFoodInputError.invalidNumber("energyKcal")) { try state.request() }
        #expect(state.draft.energyKcal == ".")
        state.draft.energyKcal = "450"
        let changed = try state.request()
        #expect(changed.food.id == first.food.id)
        #expect(changed.food.nutrientsPer100Units.energyKcal == 450)
        #expect(first.food.nutrientsPer100Units.energyKcal == 400)
    }

    @Test("Editing preserves the original comparison baseline and explicit unknown fibre")
    func editingKeepsOriginalAndUnknown() throws {
        let original = try makeCompleteState().validFood()
        var state = try PersonalFoodFormState(originalFood: original, decimalSeparator: ",")
        #expect(state.hasUnsavedChanges == false)
        #expect(state.draft.saltGrams == "0,5")
        #expect(state.draft.fibreGrams.isEmpty)
        state.draft.energyKcal = "450"
        let request = try state.request()
        #expect(request.intent == .edit(original: original))
        #expect(request.food.id == original.id)
        #expect(request.food.nutrientsPer100Units.fibreGrams == nil)
        #expect(request.food.nutrientsPer100Units.energyKcal == 450)
        #expect(original.nutrientsPer100Units.energyKcal == 400)
        state.draft.fibreGrams = "0"
        #expect(try state.request().food.nutrientsPer100Units.fibreGrams == 0)
    }

    private func makeCompleteState() -> PersonalFoodFormState {
        var state = PersonalFoodFormState(decimalSeparator: ".")
        state.draft.name = "验收测试蛋白粉"
        state.draft.category = .snackDessert
        state.draft.sourceNote = "包装说明"
        state.draft.energyKcal = "400"
        state.draft.fatGrams = "6"
        state.draft.saturatedFatGrams = "2"
        state.draft.carbohydrateGrams = "10"
        state.draft.sugarGrams = "3"
        state.draft.proteinGrams = "80"
        state.draft.saltGrams = "0.5"
        return state
    }
}
