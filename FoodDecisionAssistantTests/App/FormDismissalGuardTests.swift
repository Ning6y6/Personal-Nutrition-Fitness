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

    @Test("Placeholder removal is disabled by default for loaded or saved forms", arguments: ["meal", "template"])
    func placeholderRemovalRequiresExplicitOptIn(kind: String) {
        let row = MealFormComponentDraft(decimalSeparator: ".")
        let baseline = componentSnapshot(kind: kind, components: [row])
        let empty = componentSnapshot(kind: kind, components: [])
        var defaultGuard = FormDismissalGuard(baseline: baseline)
        var optedOutGuard = FormDismissalGuard(baseline: baseline, allowsInitialPlaceholderRemoval: false)

        defaultGuard.recordComponentRemoval(from: baseline, to: empty)
        optedOutGuard.recordComponentRemoval(from: baseline, to: empty)

        #expect(defaultGuard.hasChangesRequiringDiscard(comparedTo: empty))
        #expect(optedOutGuard.hasChangesRequiringDiscard(comparedTo: empty))
        let canDismiss = defaultGuard.requestCancellation(comparedTo: empty)
        #expect(canDismiss == false)
        #expect(defaultGuard.isConfirmingDiscard)
        #expect(defaultGuard.baseline == baseline)
    }

    @Test("Deleting the untouched initial placeholder only relaxes cancellation", arguments: ["meal", "template"])
    func initialPlaceholderRemovalKeepsStrictBaseline(kind: String) {
        let row = MealFormComponentDraft(decimalSeparator: ".")
        let baseline = componentSnapshot(kind: kind, components: [row])
        let empty = componentSnapshot(kind: kind, components: [])
        var guardState = FormDismissalGuard(baseline: baseline, allowsInitialPlaceholderRemoval: true)

        guardState.recordComponentRemoval(from: baseline, to: empty)

        #expect(guardState.baseline == baseline)
        #expect(guardState.hasUnsavedChanges(comparedTo: empty))
        #expect(guardState.canLoadInitialValues(comparedTo: empty) == false)
        #expect(guardState.hasChangesRequiringDiscard(comparedTo: empty) == false)
        let firstCancellation = guardState.requestCancellation(comparedTo: empty)
        let secondCancellation = guardState.requestCancellation(comparedTo: empty)
        #expect(firstCancellation)
        #expect(secondCancellation)
        #expect(guardState.isConfirmingDiscard == false)
        #expect(guardState.hasUnsavedChanges(comparedTo: baseline) == false)
        #expect(guardState.canLoadInitialValues(comparedTo: baseline))
        #expect(guardState.baseline == baseline)
    }

    @Test("An empty current array without the actual removal event remains dirty", arguments: ["meal", "template"])
    func emptyStateAloneDoesNotGrantAnException(kind: String) {
        let baseline = componentSnapshot(kind: kind, components: [MealFormComponentDraft(decimalSeparator: ".")])
        let empty = componentSnapshot(kind: kind, components: [])
        var guardState = FormDismissalGuard(baseline: baseline, allowsInitialPlaceholderRemoval: true)

        #expect(guardState.hasChangesRequiringDiscard(comparedTo: empty))
        let canDismiss = guardState.requestCancellation(comparedTo: empty)
        #expect(canDismiss == false)
    }

    @Test("Food references, names and raw weight inputs cannot be empty placeholders", arguments: ["meal", "template"], [
        "foodReference", "emptyFoodName", "foodName", ".", " ", "0", "100.0", "NaN",
    ])
    func initialRowsWithInputCannotBeExempted(kind: String, input: String) {
        var row = MealFormComponentDraft(decimalSeparator: ".")
        switch input {
        case "foodReference": row.foodItemID = UUID()
        case "emptyFoodName": row.foodName = ""
        case "foodName": row.foodName = "测试历史食物"
        default: row.weightText = input
        }
        let baseline = componentSnapshot(kind: kind, components: [row])
        let empty = componentSnapshot(kind: kind, components: [])
        var guardState = FormDismissalGuard(baseline: baseline, allowsInitialPlaceholderRemoval: true)

        guardState.recordComponentRemoval(from: baseline, to: empty)

        #expect(guardState.hasChangesRequiringDiscard(comparedTo: empty))
        #expect(guardState.hasUnsavedChanges(comparedTo: empty))
        #expect(guardState.baseline == baseline)
        let canDismiss = guardState.requestCancellation(comparedTo: empty)
        #expect(canDismiss == false)
    }

    @Test("Removal must begin at the exact original row state", arguments: ["meal", "template"], [
        "componentID", "decimalSeparator", "foodReference", "foodName", "weightText", "add",
    ])
    func removalFromAnEditedRowRemainsProtected(kind: String, field: String) {
        let row = MealFormComponentDraft(decimalSeparator: ".")
        let baseline = componentSnapshot(kind: kind, components: [row])
        var changedRows = [row]
        switch field {
        case "componentID": changedRows[0].id = UUID()
        case "decimalSeparator":
            changedRows[0] = MealFormComponentDraft(component: row.domainDraft, decimalSeparator: ",")
        case "foodReference": changedRows[0].foodItemID = UUID()
        case "foodName": changedRows[0].foodName = "测试食物"
        case "weightText": changedRows[0].weightText = "."
        default: changedRows.append(MealFormComponentDraft(decimalSeparator: "."))
        }
        let previous = componentSnapshot(kind: kind, components: changedRows)
        let empty = componentSnapshot(kind: kind, components: [])
        var guardState = FormDismissalGuard(baseline: baseline, allowsInitialPlaceholderRemoval: true)

        guardState.recordComponentRemoval(from: previous, to: empty)

        #expect(guardState.hasChangesRequiringDiscard(comparedTo: empty))
        #expect(guardState.baseline == baseline)
    }

    @Test("Meal metadata changes before or after removal still require discard", arguments: [
        "title", "eatenAt", "entryMethod", "coverageStatus",
    ], ["before", "after"])
    func mealMetadataRemainsProtected(field: String, phase: String) {
        let row = MealFormComponentDraft(decimalSeparator: ".")
        let baseline = componentSnapshot(kind: "meal", components: [row])
        let empty = componentSnapshot(kind: "meal", components: [])
        let changedEmpty = changingMealMetadata(in: empty, field: field)
        var guardState = FormDismissalGuard(baseline: baseline, allowsInitialPlaceholderRemoval: true)
        if phase == "before" {
            guardState.recordComponentRemoval(from: changingMealMetadata(in: baseline, field: field), to: changedEmpty)
            #expect(guardState.hasChangesRequiringDiscard(comparedTo: empty))
        } else {
            guardState.recordComponentRemoval(from: baseline, to: empty)
        }

        #expect(guardState.hasChangesRequiringDiscard(comparedTo: changedEmpty))
        #expect(guardState.canLoadInitialValues(comparedTo: changedEmpty) == false)
        let canDismiss = guardState.requestCancellation(comparedTo: changedEmpty)
        #expect(canDismiss == false)
        #expect(guardState.baseline == baseline)
    }

    @Test("Template name changes before or after removal still require discard", arguments: ["before", "after"])
    func templateNameRemainsProtected(phase: String) {
        let row = MealFormComponentDraft(decimalSeparator: ".")
        let baseline = componentSnapshot(kind: "template", components: [row])
        let empty = componentSnapshot(kind: "template", components: [])
        let changedEmpty = changePrimaryField(in: empty)
        var guardState = FormDismissalGuard(baseline: baseline, allowsInitialPlaceholderRemoval: true)
        if phase == "before" {
            guardState.recordComponentRemoval(from: changePrimaryField(in: baseline), to: changedEmpty)
            #expect(guardState.hasChangesRequiringDiscard(comparedTo: empty))
        } else {
            guardState.recordComponentRemoval(from: baseline, to: empty)
        }

        #expect(guardState.hasChangesRequiringDiscard(comparedTo: changedEmpty))
        let canDismiss = guardState.requestCancellation(comparedTo: changedEmpty)
        #expect(canDismiss == false)
        #expect(guardState.baseline == baseline)
    }

    @Test("Removal must leave exactly zero rows in the same kind of form", arguments: ["meal", "template"], [
        "keptRow", "replacementRow", "twoRows", "otherForm",
    ])
    func onlyTheExactRemovalResultCanBeExempted(kind: String, result: String) {
        let row = MealFormComponentDraft(decimalSeparator: ".")
        let baseline = componentSnapshot(kind: kind, components: [row])
        let empty = componentSnapshot(kind: kind, components: [])
        let current: FormDraftSnapshot
        switch result {
        case "keptRow": current = baseline
        case "replacementRow": current = componentSnapshot(kind: kind, components: [MealFormComponentDraft(decimalSeparator: ".")])
        case "twoRows": current = componentSnapshot(kind: kind, components: [row, MealFormComponentDraft(decimalSeparator: ".")])
        default: current = componentSnapshot(kind: kind == "meal" ? "template" : "meal", components: [])
        }
        var guardState = FormDismissalGuard(baseline: baseline, allowsInitialPlaceholderRemoval: true)

        guardState.recordComponentRemoval(from: baseline, to: current)

        #expect(guardState.hasChangesRequiringDiscard(comparedTo: empty))
        #expect(guardState.baseline == baseline)
    }

    @Test("A later deletion revokes the initial-placeholder exception", arguments: ["meal", "template"], [
        "foodReference", "foodName", ".", " ", "0", "100.0", "empty",
    ])
    func laterRemovalCannotReuseTheOldException(kind: String, input: String) {
        let baseline = componentSnapshot(kind: kind, components: [MealFormComponentDraft(decimalSeparator: ".")])
        let empty = componentSnapshot(kind: kind, components: [])
        var guardState = FormDismissalGuard(baseline: baseline, allowsInitialPlaceholderRemoval: true)
        guardState.recordComponentRemoval(from: baseline, to: empty)
        #expect(guardState.hasChangesRequiringDiscard(comparedTo: empty) == false)
        var laterRow = MealFormComponentDraft(decimalSeparator: ".")
        switch input {
        case "foodReference": laterRow.foodItemID = UUID()
        case "foodName": laterRow.foodName = "测试食物"
        case "empty": break
        default: laterRow.weightText = input
        }
        let laterDraft = componentSnapshot(kind: kind, components: [laterRow])
        #expect(guardState.hasChangesRequiringDiscard(comparedTo: laterDraft))

        guardState.recordComponentRemoval(from: laterDraft, to: empty)

        #expect(guardState.hasChangesRequiringDiscard(comparedTo: empty))
        #expect(guardState.hasUnsavedChanges(comparedTo: empty))
        #expect(guardState.canLoadInitialValues(comparedTo: empty) == false)
        let canDismiss = guardState.requestCancellation(comparedTo: empty)
        #expect(canDismiss == false)
        #expect(guardState.baseline == baseline)
    }

    @Test("An explicit baseline reset revokes the cancellation exception", arguments: ["meal", "template"])
    func resetClearsThePlaceholderException(kind: String) {
        let baseline = componentSnapshot(kind: kind, components: [MealFormComponentDraft(decimalSeparator: ".")])
        let empty = componentSnapshot(kind: kind, components: [])
        var guardState = FormDismissalGuard(baseline: baseline, allowsInitialPlaceholderRemoval: true)
        guardState.recordComponentRemoval(from: baseline, to: empty)
        #expect(guardState.hasChangesRequiringDiscard(comparedTo: empty) == false)

        guardState.resetBaseline(to: baseline)

        #expect(guardState.hasChangesRequiringDiscard(comparedTo: empty))
        #expect(guardState.hasUnsavedChanges(comparedTo: empty))
        #expect(guardState.baseline == baseline)
    }

    @Test("Goal forms cannot acquire a component-removal exception", arguments: ["goal", "goalHistory"])
    func goalsKeepStrictCancellation(kind: String) {
        let baseline: FormDraftSnapshot = kind == "goal"
            ? makeSnapshot(kind: "goal")
            : .goalHistory(draft: makeGoalDraft(), effectiveDate: Date(timeIntervalSince1970: 1_800_000_000),
                           source: .selfSelected, sourceNote: "", timeZoneIdentifier: "Europe/London")
        let changed = changePrimaryField(in: baseline)
        var guardState = FormDismissalGuard(baseline: baseline, allowsInitialPlaceholderRemoval: true)

        guardState.recordComponentRemoval(from: baseline, to: changed)

        #expect(guardState.hasChangesRequiringDiscard(comparedTo: changed))
        let canDismiss = guardState.requestCancellation(comparedTo: changed)
        #expect(canDismiss == false)
    }

    @Test("Only one initial placeholder can qualify", arguments: ["meal", "template"], [0, 2])
    func zeroOrMultipleInitialRowsDoNotQualify(kind: String, count: Int) {
        let rows = (0..<count).map { _ in MealFormComponentDraft(decimalSeparator: ".") }
        let baseline = componentSnapshot(kind: kind, components: rows)
        let empty = componentSnapshot(kind: kind, components: [])
        var guardState = FormDismissalGuard(baseline: baseline, allowsInitialPlaceholderRemoval: true)

        guardState.recordComponentRemoval(from: baseline, to: empty)
        let added = componentSnapshot(kind: kind, components: [MealFormComponentDraft(decimalSeparator: ".")])
        guardState.recordComponentRemoval(from: added, to: empty)

        #expect(guardState.hasChangesRequiringDiscard(comparedTo: empty) == (count != 0))
        #expect(guardState.baseline == baseline)
    }

    private func componentSnapshot(kind: String, components: [MealFormComponentDraft]) -> FormDraftSnapshot {
        kind == "meal"
            ? .meal(title: "测试午餐", eatenAt: Date(timeIntervalSince1970: 1_800_000_000),
                    entryMethod: .weighed, coverageStatus: .complete, components: components)
            : .template(name: "", components: components)
    }

    private func changingMealMetadata(in snapshot: FormDraftSnapshot, field: String) -> FormDraftSnapshot {
        guard case let .meal(title, date, method, coverage, components) = snapshot else {
            Issue.record("Expected a synthetic meal snapshot")
            return snapshot
        }
        switch field {
        case "title":
            return .meal(title: title + "修改", eatenAt: date, entryMethod: method,
                         coverageStatus: coverage, components: components)
        case "eatenAt":
            return .meal(title: title, eatenAt: date.addingTimeInterval(1), entryMethod: method,
                         coverageStatus: coverage, components: components)
        case "entryMethod":
            return .meal(title: title, eatenAt: date, entryMethod: .standardPortionEstimate,
                         coverageStatus: coverage, components: components)
        default:
            return .meal(title: title, eatenAt: date, entryMethod: method,
                         coverageStatus: .partial, components: components)
        }
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
        case let .goalHistory(draft, date, source, note, zone):
            var changed = draft
            changed.energyKcal = "2100"
            return .goalHistory(draft: changed, effectiveDate: date, source: source, sourceNote: note, timeZoneIdentifier: zone)
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
