import FoodDecisionCore
import Foundation
import Testing

@testable import FoodDecisionAssistant

/// Pure form-state regressions. These do not verify sheet gestures, keyboard interaction,
/// VoiceOver, or whether a confirmation dialog is actually presented by SwiftUI.
@MainActor
struct FormDismissalGuardTests {
    @Test("An unchanged form can cancel without asking to discard", arguments: ["meal", "goal", "template"])
    func unchangedFormsCanCancel(kind: String) {
        let snapshot = makeSnapshot(kind: kind)
        var guardState = FormDismissalGuard(baseline: snapshot)

        #expect(guardState.hasUnsavedChanges(comparedTo: snapshot) == false)
        let canDismiss = guardState.requestCancellation(comparedTo: snapshot)
        #expect(canDismiss)
        #expect(guardState.isConfirmingDiscard == false)
        #expect(guardState.baseline == snapshot)
    }

    @Test("Changed forms request confirmation without replacing their baseline", arguments: ["meal", "goal", "template"])
    func changedFormsRequireConfirmation(kind: String) {
        let snapshot = makeSnapshot(kind: kind)
        let changed = changePrimaryField(in: snapshot)
        let originalChanged = changed
        var guardState = FormDismissalGuard(baseline: snapshot)

        #expect(guardState.hasUnsavedChanges(comparedTo: changed))
        let canDismiss = guardState.requestCancellation(comparedTo: changed)
        #expect(canDismiss == false)
        #expect(guardState.isConfirmingDiscard)
        #expect(guardState.baseline == snapshot)
        #expect(changed == originalChanged)
    }

    @Test("Returning to the original values makes every form clean", arguments: ["meal", "goal", "template"])
    func restoredOriginalValuesAreClean(kind: String) {
        let snapshot = makeSnapshot(kind: kind)
        var current = changePrimaryField(in: snapshot)
        var guardState = FormDismissalGuard(baseline: snapshot)
        #expect(guardState.hasUnsavedChanges(comparedTo: current))

        current = snapshot

        #expect(guardState.hasUnsavedChanges(comparedTo: current) == false)
        let canDismiss = guardState.requestCancellation(comparedTo: current)
        #expect(canDismiss)
        #expect(guardState.baseline == snapshot)
    }

    @Test("Every saved meal field and component identity participates in change detection", arguments: [
        "title", "eatenAt", "entryMethod", "coverageStatus", "componentID", "foodItemID",
        "foodName", "weightText", "decimalSeparator", "add", "remove", "reorder",
    ])
    func mealFieldsAreObserved(field: String) {
        let eatenAt = Date(timeIntervalSince1970: 1_800_000_000)
        let components = makeComponents()
        let baseline = FormDraftSnapshot.meal(
            title: "测试午餐", eatenAt: eatenAt, entryMethod: .weighed,
            coverageStatus: .complete, components: components
        )
        var title = "测试午餐"
        var date = eatenAt
        var method = MealEntryMethod.weighed
        var coverage = MealCoverageStatus.complete
        var changedComponents = components
        switch field {
        case "title": title = "测试晚餐"
        case "eatenAt": date = eatenAt.addingTimeInterval(1)
        case "entryMethod": method = .standardPortionEstimate
        case "coverageStatus": coverage = .partial
        default: mutateComponents(&changedComponents, field: field)
        }
        let current = FormDraftSnapshot.meal(
            title: title, eatenAt: date, entryMethod: method,
            coverageStatus: coverage, components: changedComponents
        )
        let guardState = FormDismissalGuard(baseline: baseline)

        #expect(current != baseline)
        #expect(guardState.hasUnsavedChanges(comparedTo: current))
        #expect(guardState.hasUnsavedChanges(comparedTo: baseline) == false)
    }

    @Test("Every template field including component order participates in change detection", arguments: [
        "name", "componentID", "foodItemID", "foodName", "weightText", "decimalSeparator",
        "add", "remove", "reorder",
    ])
    func templateFieldsAreObserved(field: String) {
        let components = makeComponents()
        let baseline = FormDraftSnapshot.template(name: "测试常用餐", components: components)
        var name = "测试常用餐"
        var changedComponents = components
        if field == "name" {
            name = "测试常用餐修改"
        } else {
            mutateComponents(&changedComponents, field: field)
        }
        let current = FormDraftSnapshot.template(name: name, components: changedComponents)
        let guardState = FormDismissalGuard(baseline: baseline)

        #expect(current != baseline)
        #expect(guardState.hasUnsavedChanges(comparedTo: current))
        #expect(guardState.hasUnsavedChanges(comparedTo: baseline) == false)
    }

    @Test("Every goal field including explicit confirmation participates in change detection", arguments: [
        "energyKcal", "proteinGrams", "carbohydrateGrams", "fatGrams",
        "saturatedFatLimitGrams", "fibreGrams", "isConfirmed",
    ])
    func goalFieldsAreObserved(field: String) {
        let original = makeGoalDraft()
        var changed = original
        switch field {
        case "energyKcal": changed.energyKcal = "2100"
        case "proteinGrams": changed.proteinGrams = "141"
        case "carbohydrateGrams": changed.carbohydrateGrams = "211"
        case "fatGrams": changed.fatGrams = "61"
        case "saturatedFatLimitGrams": changed.saturatedFatLimitGrams = "0"
        case "fibreGrams": changed.fibreGrams = "0"
        case "isConfirmed": changed.isConfirmed = true
        default: Issue.record("Unknown synthetic goal mutation: \(field)")
        }
        let baseline = FormDraftSnapshot.goal(original)
        let guardState = FormDismissalGuard(baseline: baseline)

        #expect(guardState.hasUnsavedChanges(comparedTo: .goal(changed)))
        #expect(guardState.hasUnsavedChanges(comparedTo: .goal(original)) == false)
    }

    @Test("Invalid and special raw weight text can be a stable loaded baseline", arguments: [
        "", "abc", "NaN", "Infinity", "0", "-1", "1,000.5",
    ], ["meal", "template"])
    func unchangedRawTextIsNotDirty(text: String, kind: String) {
        var component = MealFormComponentDraft(decimalSeparator: ".")
        component.weightText = text
        let snapshot: FormDraftSnapshot = kind == "meal"
            ? .meal(title: "测试餐", eatenAt: Date(timeIntervalSince1970: 1_800_000_000),
                    entryMethod: .weighed, coverageStatus: .complete, components: [component])
            : .template(name: "测试模板", components: [component])
        var guardState = FormDismissalGuard(baseline: snapshot)

        #expect(snapshot == snapshot)
        #expect(guardState.hasUnsavedChanges(comparedTo: snapshot) == false)
        let canDismiss = guardState.requestCancellation(comparedTo: snapshot)
        #expect(canDismiss)
        #expect(guardState.isConfirmingDiscard == false)
    }

    @Test("Loading a non-finite historical weight does not make an unchanged snapshot unequal to itself", arguments: [
        Double.nan, Double.infinity, -Double.infinity,
    ])
    func historicalNonFiniteWeightHasStableRawSnapshot(weight: Double) {
        let component = MealFormComponentDraft(
            component: MealEntryDraftComponent(foodName: "测试历史食物", weightGrams: weight),
            decimalSeparator: "."
        )
        let snapshot = FormDraftSnapshot.template(name: "测试历史模板", components: [component])
        let reloadedComponent = MealFormComponentDraft(
            component: MealEntryDraftComponent(
                id: component.id, foodItemID: component.foodItemID,
                foodName: component.foodName, weightGrams: weight
            ), decimalSeparator: "."
        )
        let reloaded = FormDraftSnapshot.template(name: "测试历史模板", components: [reloadedComponent])
        var guardState = FormDismissalGuard(baseline: snapshot)

        #expect(component.weightText.isEmpty == false)
        #expect(reloaded == snapshot)
        #expect(guardState.hasUnsavedChanges(comparedTo: reloaded) == false)
        let canDismiss = guardState.requestCancellation(comparedTo: reloaded)
        #expect(canDismiss)
    }

    @Test("Changing dialog state cannot change either the baseline or the edited values", arguments: ["meal", "goal", "template"])
    func confirmationStateDoesNotMutateDraft(kind: String) {
        let baseline = makeSnapshot(kind: kind)
        let current = changePrimaryField(in: baseline)
        let originalCurrent = current
        var guardState = FormDismissalGuard(baseline: baseline)

        let firstCancellation = guardState.requestCancellation(comparedTo: current)
        #expect(firstCancellation == false)
        guardState.isConfirmingDiscard = false

        #expect(guardState.baseline == baseline)
        #expect(current == originalCurrent)
        #expect(guardState.hasUnsavedChanges(comparedTo: current))
        let secondCancellation = guardState.requestCancellation(comparedTo: current)
        #expect(secondCancellation == false)
        #expect(guardState.isConfirmingDiscard)
    }

    @Test("Only an explicit load reset adopts a new baseline", arguments: ["meal", "goal", "template"])
    func resetIsExplicit(kind: String) {
        let original = makeSnapshot(kind: kind)
        let loaded = changePrimaryField(in: original)
        var guardState = FormDismissalGuard(baseline: original)
        #expect(guardState.hasUnsavedChanges(comparedTo: loaded))
        #expect(guardState.hasUnsavedChanges(comparedTo: loaded))
        #expect(guardState.baseline == original)

        guardState.resetBaseline(to: loaded)

        #expect(guardState.baseline == loaded)
        #expect(guardState.hasUnsavedChanges(comparedTo: loaded) == false)
        #expect(guardState.hasUnsavedChanges(comparedTo: original))
        let canDismiss = guardState.requestCancellation(comparedTo: loaded)
        #expect(canDismiss)
    }

    @Test("Numerically equivalent raw edits still count as user changes", arguments: ["meal", "template"])
    func rawTextEditsAreNotNormalizedAway(kind: String) {
        var component = MealFormComponentDraft(decimalSeparator: ".")
        component.weightText = "100"
        var edited = component
        edited.weightText = "100.0"
        let baseline: FormDraftSnapshot = kind == "meal"
            ? .meal(title: "测试餐", eatenAt: Date(timeIntervalSince1970: 1_800_000_000),
                    entryMethod: .weighed, coverageStatus: .complete, components: [component])
            : .template(name: "测试模板", components: [component])
        let current: FormDraftSnapshot = kind == "meal"
            ? .meal(title: "测试餐", eatenAt: Date(timeIntervalSince1970: 1_800_000_000),
                    entryMethod: .weighed, coverageStatus: .complete, components: [edited])
            : .template(name: "测试模板", components: [edited])
        let guardState = FormDismissalGuard(baseline: baseline)

        #expect(component.weightGrams == edited.weightGrams)
        #expect(guardState.hasUnsavedChanges(comparedTo: current))
    }

    @Test("A failed initial goal load cannot retry over typed or invalid inputs", arguments: ["2100", "abc", "0", " "])
    func editedGoalCannotReloadAfterReadFailure(text: String) {
        let initial = GoalInputDraft()
        var current = initial
        current.energyKcal = text
        let guardState = FormDismissalGuard(baseline: .goal(initial))

        #expect(guardState.canLoadInitialValues(comparedTo: .goal(current)) == false)
        #expect(guardState.baseline == .goal(initial))
        #expect(guardState.hasUnsavedChanges(comparedTo: .goal(current)))
    }

    @Test("Retry is allowed only while goal inputs still match the initial baseline")
    func uneditedGoalCanRetryInitialRead() {
        let initial = GoalInputDraft()
        var current = initial
        let guardState = FormDismissalGuard(baseline: .goal(initial))
        #expect(guardState.canLoadInitialValues(comparedTo: .goal(current)))
        current.isConfirmed = true
        #expect(guardState.canLoadInitialValues(comparedTo: .goal(current)) == false)
        current = initial
        #expect(guardState.canLoadInitialValues(comparedTo: .goal(current)))
    }

    private func makeSnapshot(kind: String) -> FormDraftSnapshot {
        switch kind {
        case "meal":
            .meal(title: "测试午餐", eatenAt: Date(timeIntervalSince1970: 1_800_000_000),
                  entryMethod: .weighed, coverageStatus: .complete, components: makeComponents())
        case "goal": .goal(makeGoalDraft())
        default: .template(name: "测试常用餐", components: makeComponents())
        }
    }

    private func changePrimaryField(in snapshot: FormDraftSnapshot) -> FormDraftSnapshot {
        switch snapshot {
        case let .meal(title, date, method, coverage, components):
            return .meal(title: title + "修改", eatenAt: date, entryMethod: method,
                         coverageStatus: coverage, components: components)
        case var .goal(draft):
            draft.energyKcal = "2100"
            return .goal(draft)
        case let .template(name, components):
            return .template(name: name + "修改", components: components)
        }
    }

    private func makeGoalDraft() -> GoalInputDraft {
        var draft = GoalInputDraft()
        draft.energyKcal = "2000"
        draft.proteinGrams = "140"
        draft.carbohydrateGrams = "210"
        draft.fatGrams = "60"
        return draft
    }

    private func makeComponents() -> [MealFormComponentDraft] {
        [
            MealFormComponentDraft(component: .init(foodItemID: UUID(), foodName: "测试鸡肉", weightGrams: 100), decimalSeparator: "."),
            MealFormComponentDraft(component: .init(foodItemID: UUID(), foodName: "测试米饭", weightGrams: 200), decimalSeparator: "."),
        ]
    }

    private func mutateComponents(_ components: inout [MealFormComponentDraft], field: String) {
        switch field {
        case "componentID": components[0].id = UUID()
        case "foodItemID": components[0].foodItemID = nil
        case "foodName": components[0].foodName = "测试牛肉"
        case "weightText": components[0].weightText = "101"
        case "decimalSeparator":
            components[0] = MealFormComponentDraft(component: components[0].domainDraft, decimalSeparator: ",")
        case "add": components.append(MealFormComponentDraft(decimalSeparator: "."))
        case "remove": components.removeLast()
        case "reorder": components.reverse()
        default: Issue.record("Unknown synthetic component mutation: \(field)")
        }
    }
}
