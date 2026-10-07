import FoodDecisionCore
import Foundation
import Testing

@testable import FoodDecisionAssistant

/// Exercises raw form text and its Core handoff, not SwiftUI's keyboard or text fields.
@MainActor
struct MealFormComponentDraftTests {
    @Test("A new row preserves an absent weight instead of inventing zero")
    func emptyRowHasNoWeight() {
        let row = MealFormComponentDraft(decimalSeparator: ".")

        #expect(row.foodItemID == nil)
        #expect(row.foodName == nil)
        #expect(row.weightText == "")
        #expect(row.weightGrams == nil)
        #expect(row.domainDraft.weightGrams == nil)
        #expect(row.domainDraft.id == row.id)
        #expect(row.domainDraft.foodItemID == nil)
        #expect(row.domainDraft.foodName == nil)
    }

    @Test("Loading a Core draft retains identity, optional mapping, and full Double precision", arguments: [
        0.0, -1.0, 123.45678901234567, 1.0000000000000002,
        Double.leastNonzeroMagnitude, Double.greatestFiniteMagnitude,
    ])
    func loadedWeightsRoundTripWithoutRounding(weight: Double) {
        let source = MealEntryDraftComponent(
            foodItemID: UUID(), foodName: "测试鸡肉", weightGrams: weight
        )
        let row = MealFormComponentDraft(component: source, decimalSeparator: ".")

        #expect(row.id == source.id)
        #expect(row.foodItemID == source.foodItemID)
        #expect(row.foodName == source.foodName)
        #expect(row.weightGrams == weight)
        #expect(row.domainDraft == source)
    }

    @Test("An explicit comma separator retains the original Double precision", arguments: [
        123.45678901234567, 1.0000000000000002, 0.000000123456789,
    ])
    func loadedCommaWeightsRoundTrip(weight: Double) {
        let source = MealEntryDraftComponent(weightGrams: weight)
        let row = MealFormComponentDraft(component: source, decimalSeparator: ",")

        #expect(row.decimalSeparator == ",")
        #expect(row.weightText.contains(".") == false)
        #expect(row.weightGrams == weight)
        #expect(row.domainDraft == source)
    }

    @Test("Whole numeric dot input is parsed without truncation", arguments: [
        WeightInput(text: "100", expected: 100),
        WeightInput(text: "100.5", expected: 100.5),
        WeightInput(text: " 100.5 \n", expected: 100.5),
        WeightInput(text: ".5", expected: 0.5),
        WeightInput(text: "1e2", expected: 100),
        WeightInput(text: "1.0000000000000002", expected: 1.0000000000000002),
    ])
    func parsesDotNumbers(input: WeightInput) {
        var row = MealFormComponentDraft(decimalSeparator: ".")
        row.weightText = input.text

        #expect(row.weightGrams == input.expected)
        #expect(row.domainDraft.weightGrams == input.expected)
        #expect(row.weightText == input.text)
    }

    @Test("A comma is a decimal only when explicitly configured", arguments: [
        WeightInput(text: "100,5", expected: 100.5),
        WeightInput(text: " 100,5 \n", expected: 100.5),
        WeightInput(text: "0,5", expected: 0.5),
        WeightInput(text: "1,0000000000000002", expected: 1.0000000000000002),
    ])
    func parsesCommaNumbers(input: WeightInput) {
        var commaRow = MealFormComponentDraft(decimalSeparator: ",")
        commaRow.weightText = input.text
        var dotRow = MealFormComponentDraft(decimalSeparator: ".")
        dotRow.weightText = input.text

        #expect(commaRow.weightGrams == input.expected)
        #expect(commaRow.domainDraft.weightGrams == input.expected)
        #expect(dotRow.weightGrams == nil)
        #expect(dotRow.domainDraft.weightGrams == nil)
        #expect(commaRow.weightText == input.text)
    }

    @Test("The other decimal separator and grouped inputs are not silently reinterpreted", arguments: [
        RejectedWeightInput(text: "100,5", separator: "."),
        RejectedWeightInput(text: "100.5", separator: ","),
        RejectedWeightInput(text: "1,000", separator: "."),
        RejectedWeightInput(text: "1.000", separator: ","),
        RejectedWeightInput(text: "1,000.5", separator: "."),
        RejectedWeightInput(text: "1.000,5", separator: ","),
        RejectedWeightInput(text: "1,000,000", separator: ","),
        RejectedWeightInput(text: "1.000.000", separator: "."),
        RejectedWeightInput(text: "1 000", separator: "."),
        RejectedWeightInput(text: "1_000", separator: "."),
    ])
    func rejectsOtherSeparatorAndGrouping(input: RejectedWeightInput) {
        var row = MealFormComponentDraft(
            component: .init(weightGrams: 75), decimalSeparator: input.separator
        )
        row.weightText = input.text

        #expect(row.weightGrams == nil)
        #expect(row.domainDraft.weightGrams == nil)
        #expect(row.weightText == input.text)
    }

    @Test("Invalid edited text never reuses the last successfully loaded weight", arguments: [
        "abc", "25g", "12.5abc", "12 5", "1.2.3", "--1", "1e", "0x10", "",
    ])
    func invalidTextDoesNotReuseOldWeight(text: String) {
        let source = MealEntryDraftComponent(foodItemID: UUID(), foodName: "测试食物", weightGrams: 75)
        var row = MealFormComponentDraft(component: source, decimalSeparator: ".")
        row.weightText = text

        #expect(row.weightGrams == nil)
        #expect(row.domainDraft.weightGrams == nil)
        #expect(row.domainDraft.id == source.id)
        #expect(row.domainDraft.foodItemID == source.foodItemID)
        #expect(row.domainDraft.foodName == source.foodName)
        #expect(row.weightText == text)
    }

    @Test("Empty input and an explicitly entered zero remain distinct", arguments: [".", ","])
    func absentAndZeroAreDistinct(separator: String) {
        var row = MealFormComponentDraft(decimalSeparator: separator)
        row.weightText = " \n"
        #expect(row.weightGrams == nil)
        #expect(row.domainDraft.weightGrams == nil)

        row.weightText = "0"
        #expect(row.weightGrams == 0)
        #expect(row.domainDraft.weightGrams == 0)

        row.weightText = ""
        #expect(row.weightGrams == nil)
        #expect(row.domainDraft.weightGrams == nil)
    }

    @Test("Weight parsing always reflects the current raw text rather than cached numeric state")
    func editingCanRecoverAfterInvalidText() {
        var row = MealFormComponentDraft(component: .init(weightGrams: 75), decimalSeparator: ".")
        row.weightText = "abc"
        #expect(row.weightGrams == nil)
        row.weightText = "0"
        #expect(row.weightGrams == 0)
        row.weightText = ""
        #expect(row.weightGrams == nil)
        row.weightText = "25.125"
        #expect(row.weightGrams == 25.125)
        #expect(row.domainDraft.weightGrams == 25.125)
    }

    @Test("Reading or handing off a row cannot normalize away the user's raw text")
    func readsDoNotRewriteText() {
        var row = MealFormComponentDraft(decimalSeparator: ".")
        row.weightText = "0001.234500"
        let original = row

        #expect(row.weightGrams == 1.2345)
        #expect(row.domainDraft.weightGrams == 1.2345)
        #expect(row.weightGrams == 1.2345)
        #expect(row == original)
        #expect(row.weightText == "0001.234500")
    }

    @Test("Core handoff includes current component identity and mapping without discarding nil")
    func domainHandoffUsesCurrentFields() {
        var row = MealFormComponentDraft(
            component: .init(foodItemID: UUID(), foodName: "测试原食物", weightGrams: 75),
            decimalSeparator: "."
        )
        let editedID = UUID()
        row.id = editedID
        row.foodItemID = nil
        row.foodName = "测试新食物"
        row.weightText = "25.125"
        let handoff = row.domainDraft

        #expect(handoff.id == editedID)
        #expect(handoff.foodItemID == nil)
        #expect(handoff.foodName == "测试新食物")
        #expect(handoff.weightGrams == 25.125)
    }

    @Test("Historical special weights are represented as stable text instead of NaN equality", arguments: [
        Double.nan, Double.infinity, -Double.infinity,
    ])
    func specialLoadedWeightsHaveStableText(weight: Double) {
        let source = MealEntryDraftComponent(weightGrams: weight)
        let row = MealFormComponentDraft(component: source, decimalSeparator: ".")
        let independentlyLoaded = MealFormComponentDraft(component: source, decimalSeparator: ".")

        #expect(row.weightText == String(weight))
        #expect(row == independentlyLoaded)
        #expect(row == row)
        #expect(row.id == source.id)
    }

    @Test("Non-finite edited weights retain their raw text but cannot become a numeric handoff", arguments: [
        "NaN", "nan", "inf", "Infinity", "-Infinity", "1e309",
    ])
    func specialWeightTextIsNotNumeric(text: String) {
        var row = MealFormComponentDraft(component: .init(weightGrams: 75), decimalSeparator: ".")
        row.weightText = text

        #expect(row.weightGrams == nil)
        #expect(row.domainDraft.weightGrams == nil)
        #expect(row.weightText == text)
    }

    struct WeightInput: Sendable {
        let text: String
        let expected: Double
    }

    struct RejectedWeightInput: Sendable {
        let text: String
        let separator: String
    }
}
