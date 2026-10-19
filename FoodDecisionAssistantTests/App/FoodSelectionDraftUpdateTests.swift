import FoodDecisionCore
import Foundation
import Testing

@testable import FoodDecisionAssistant

/// Pure draft updates; navigation, keyboard focus and parent title/date preservation
/// are exercised separately by real UI interactions.
@MainActor
struct FoodSelectionDraftUpdateTests {
    @Test("Selecting one row preserves both raw weights and the other row", arguments: ["100.0", ".", "25.125", "25,125"])
    func selectionChangesOnlyTargetReference(rawWeight: String) throws {
        let first = makeRow(name: "测试首项", weight: "100.0")
        let second = makeRow(name: "测试次项", weight: rawWeight)
        var rows = [first, second]
        let newFoodID = UUID()

        let applied = FoodSelectionDraftUpdate.apply(foodID: newFoodID, to: second.id, rows: &rows)

        #expect(applied)
        #expect(rows.count == 2)
        #expect(rows[0] == first)
        let target = try #require(rows.first(where: { $0.id == second.id }))
        #expect(target.foodItemID == newFoodID)
        #expect(target.id == second.id)
        #expect(target.foodName == second.foodName)
        #expect(target.weightText == rawWeight)
        #expect(target.decimalSeparator == second.decimalSeparator)
    }

    @Test("A pending selection follows row identity after rows are reordered")
    func reorderingDoesNotRetargetSelection() {
        let first = makeRow(name: "测试首项", weight: "100.0")
        let second = makeRow(name: "测试次项", weight: ".")
        var rows = [second, first]
        let newFoodID = UUID()

        #expect(FoodSelectionDraftUpdate.apply(foodID: newFoodID, to: second.id, rows: &rows))
        #expect(rows[0].foodItemID == newFoodID)
        #expect(rows[0].id == second.id)
        #expect(rows[0].weightText == ".")
        #expect(rows[1] == first)
    }

    @Test("A row removed while searching cannot change another row")
    func removedRowIsRejected() {
        let first = makeRow(name: "测试首项", weight: "100.0")
        let removed = makeRow(name: "已移除测试项", weight: ".")
        var rows = [first]
        let before = rows

        let applied = FoodSelectionDraftUpdate.apply(foodID: UUID(), to: removed.id, rows: &rows)

        #expect(applied == false)
        #expect(rows == before)
    }

    @Test("An explicit clear preserves the target's raw text and other fields")
    func clearRemovesOnlyFoodReference() {
        let first = makeRow(name: "测试首项", weight: "100.0")
        let second = makeRow(name: "测试次项", weight: ".")
        var rows = [first, second]

        #expect(FoodSelectionDraftUpdate.apply(foodID: nil, to: second.id, rows: &rows))
        #expect(rows[0] == first)
        #expect(rows[1].id == second.id)
        #expect(rows[1].foodItemID == nil)
        #expect(rows[1].foodName == second.foodName)
        #expect(rows[1].weightText == ".")
        #expect(rows[1].decimalSeparator == second.decimalSeparator)
    }

    @Test("Repeated selection is idempotent and cannot invent a draft row")
    func repeatedSelectionDoesNotDuplicateRows() {
        let first = makeRow(name: "测试首项", weight: "100.0")
        let second = makeRow(name: "测试次项", weight: ".")
        var rows = [first, second]
        let newFoodID = UUID()
        #expect(FoodSelectionDraftUpdate.apply(foodID: newFoodID, to: second.id, rows: &rows))
        let selected = rows

        #expect(FoodSelectionDraftUpdate.apply(foodID: newFoodID, to: second.id, rows: &rows))
        #expect(rows == selected)
        #expect(rows.map(\.id) == [first.id, second.id])
    }

    @Test("Draft protection still detects selection and becomes clean after restoring the original")
    func selectionParticipatesInExistingDraftGuard() {
        let first = makeRow(name: "测试首项", weight: "100.0")
        let second = makeRow(name: "测试次项", weight: ".")
        var rows = [first, second]
        let baseline = FormDraftSnapshot.template(name: "测试模板名称", components: rows)
        let guardState = FormDismissalGuard(baseline: baseline)
        FoodSelectionDraftUpdate.apply(foodID: UUID(), to: second.id, rows: &rows)
        #expect(guardState.hasUnsavedChanges(comparedTo: .template(name: "测试模板名称", components: rows)))

        FoodSelectionDraftUpdate.apply(foodID: second.foodItemID, to: second.id, rows: &rows)

        #expect(rows == [first, second])
        #expect(guardState.hasUnsavedChanges(comparedTo: .template(name: "测试模板名称", components: rows)) == false)
    }

    private func makeRow(name: String, weight: String) -> MealFormComponentDraft {
        var row = MealFormComponentDraft(
            component: .init(foodItemID: UUID(), foodName: name),
            decimalSeparator: weight.contains(",") ? "," : "."
        )
        row.weightText = weight
        return row
    }
}
