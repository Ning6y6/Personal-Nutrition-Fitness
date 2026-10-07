import FoodDecisionCore
import Foundation

/// Editable UI text stays separate from the numeric Core draft. Incomplete or invalid
/// text must be detectable as an unsaved change, never silently reuse an old weight.
struct MealFormComponentDraft: Identifiable, Equatable {
    var id: UUID
    var foodItemID: UUID?
    var foodName: String?
    var weightText: String
    let decimalSeparator: String

    init(
        component: MealEntryDraftComponent = .init(),
        decimalSeparator: String = Locale.current.decimalSeparator ?? "."
    ) {
        id = component.id
        foodItemID = component.foodItemID
        foodName = component.foodName
        self.decimalSeparator = decimalSeparator
        // Preserve the original Double, including more than one fractional digit.
        // Text equality also makes an unchanged legacy NaN stable for dirty detection.
        var text = component.weightGrams.map { String($0) } ?? ""
        if text.hasSuffix(".0") { text.removeLast(2) }
        weightText = text.replacingOccurrences(of: ".", with: decimalSeparator)
    }

    var weightGrams: Double? {
        guard decimalSeparator == "." || decimalSeparator == "," else { return nil }
        let input = weightText.trimmingCharacters(in: .whitespacesAndNewlines)
        let otherSeparator = decimalSeparator == "." ? "," : "."
        let normalized = input.replacingOccurrences(of: decimalSeparator, with: ".")
        let grammar = #"^[+-]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][+-]?[0-9]+)?$"#
        guard !input.contains(otherSeparator),
              normalized.range(of: grammar, options: .regularExpression) != nil,
              let value = Double(normalized),
              value.isFinite else { return nil }
        return value
    }

    var domainDraft: MealEntryDraftComponent {
        MealEntryDraftComponent(
            id: id, foodItemID: foodItemID, foodName: foodName, weightGrams: weightGrams
        )
    }
}
