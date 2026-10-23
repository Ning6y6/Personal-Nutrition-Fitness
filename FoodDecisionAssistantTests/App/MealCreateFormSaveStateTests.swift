import FoodDecisionCore
import Foundation
import SwiftData
import Testing
@testable import FoodDecisionAssistant

@MainActor
struct MealCreateFormSaveStateTests {
    private let clock = Date(timeIntervalSince1970: 1_792_713_600)

    @Test("A presentation owns one stable meal UUID and preserves component UUIDs, ordering and raw input")
    func firstRequestPreservesFormIdentity() throws {
        let (foods, rows) = try fixture()
        let id = UUID(), sourceTemplateID = UUID()
        var state = MealCreateFormSaveState(mealID: id, sourceTemplateID: sourceTemplateID)
        #expect(state.pendingRequest == nil)
        let request = try state.request(title: "  synthetic  ", eatenAt: clock, entryMethod: .weighed,
            coverageStatus: .complete, rows: rows, foods: foods, templateUsedAt: clock)
        #expect(request.meal.id == id)
        #expect(request.sourceTemplateID == sourceTemplateID)
        #expect(request.templateUsedAt == clock)
        #expect(request.meal.title == "synthetic")
        #expect(request.meal.components.map(\.id) == rows.map(\.id))
        #expect(request.meal.components.map(\.foodItemID) == rows.compactMap(\.foodItemID))
        #expect(request.meal.nutrients.energyKcal == 350)
        #expect(request.meal.nutrients.fibreGrams == nil)
        #expect(rows.map(\.weightText) == ["150.0", "50"])
        #expect(state.pendingRequest == request)
    }

    @Test("Unchanged retries retain the same meal, usage timestamp and request even with equivalent numeric text")
    func unchangedPayloadReusesFrozenRequest() throws {
        let (foods, initialRows) = try fixture()
        var state = MealCreateFormSaveState(sourceTemplateID: UUID())
        let first = try request(&state, rows: initialRows, foods: foods)
        var rows = initialRows; rows[0].weightText = "150"
        let retry = try state.request(title: "synthetic", eatenAt: clock, entryMethod: .weighed,
            coverageStatus: .complete, rows: rows, foods: foods, templateUsedAt: clock.addingTimeInterval(60))
        #expect(retry == first)
        #expect(retry.templateUsedAt == clock)
        #expect(state.pendingRequest == first)
        #expect(rows[0].weightText == "150")
    }

    @Test("Every interpreted payload change rebuilds the current request before observers invalidate it", arguments: [
        "title", "eatenAt", "method", "coverage", "weight", "food", "sourceNutrition", "order", "remove", "append"
    ])
    func changedPayloadCannotReuseStaleRequest(field: String) throws {
        let (initialFoods, initialRows) = try fixture()
        var state = MealCreateFormSaveState(sourceTemplateID: UUID())
        let first = try request(&state, rows: initialRows, foods: initialFoods)
        let foods = initialFoods
        var rows = initialRows
        var title = "synthetic", date = clock
        var method = MealEntryMethod.weighed
        var coverage = MealCoverageStatus.complete
        switch field {
        case "title": title = "updated synthetic"
        case "eatenAt": date = clock.addingTimeInterval(60)
        case "method": method = .standardPortionEstimate
        case "coverage": coverage = .partial
        case "weight": rows[0].weightText = "200"
        case "food": rows[0].foodItemID = foods[1].id; rows[0].foodName = foods[1].name
        case "sourceNutrition": foods[0].energyKcalPer100Units = 300
        case "order": rows.reverse()
        case "remove": rows.removeLast()
        default:
            var appended = MealFormComponentDraft(component: .init(foodItemID: foods[1].id, foodName: foods[1].name), decimalSeparator: ".")
            appended.weightText = "25"; rows.append(appended)
        }
        // Deliberately do not call invalidate: a delayed onChange must never
        // allow a formerly valid pending request to save the old numbers.
        let changed = try state.request(title: title, eatenAt: date, entryMethod: method,
            coverageStatus: coverage, rows: rows, foods: foods, templateUsedAt: clock.addingTimeInterval(60))
        #expect(changed != first)
        #expect(changed.meal.id == first.meal.id)
        #expect(changed.sourceTemplateID == first.sourceTemplateID)
        #expect(changed.templateUsedAt == clock.addingTimeInterval(60))
        #expect(changed.meal.title == title)
        #expect(changed.meal.eatenAt == date)
        #expect(changed.meal.entryMethod == method)
        #expect(changed.meal.coverageStatus == coverage)
        #expect(changed.meal.components.map(\.id) == rows.map(\.id))
        #expect(state.pendingRequest == changed)
        if field == "weight" { #expect(changed.meal.nutrients.energyKcal == 450) }
        if field == "sourceNutrition" { #expect(changed.meal.nutrients.energyKcal == 500) }
        if field == "food" { #expect(changed.meal.nutrients.energyKcal == 200) }
    }

    @Test("Invalid current input never falls back to a previously valid pending request", arguments: [
        "emptyName", "emptyRows", "blankRow", "missingFood", "invalidFood", "blankWeight", "invalidRaw",
        "nonFiniteRaw", "zeroWeight", "negativeWeight", "duplicateID", "overflow"
    ])
    func invalidInputNeverUsesPendingPayload(issue: String) throws {
        let (initialFoods, initialRows) = try fixture()
        var state = MealCreateFormSaveState()
        let first = try request(&state, rows: initialRows, foods: initialFoods)
        var foods = initialFoods, rows = initialRows, title = "synthetic"
        switch issue {
        case "emptyName": title = " \n "
        case "emptyRows": rows = []
        case "blankRow": rows.append(MealFormComponentDraft(decimalSeparator: "."))
        case "missingFood": foods = [foods[1]]
        case "invalidFood": foods[0].unit = "ml"
        case "blankWeight": rows[0].weightText = ""
        case "invalidRaw": rows[0].weightText = "."
        case "nonFiniteRaw": rows[0].weightText = "NaN"
        case "zeroWeight": rows[0].weightText = "0"
        case "negativeWeight": rows[0].weightText = "-1"
        case "duplicateID": rows[1].id = rows[0].id
        default: rows[0].weightText = "1e308"; foods[0].energyKcalPer100Units = 1e308
        }
        do {
            _ = try state.request(title: title, eatenAt: clock, entryMethod: .weighed,
                coverageStatus: .complete, rows: rows, foods: foods, templateUsedAt: clock.addingTimeInterval(60))
            Issue.record("Expected the current invalid form to be rejected: \(issue)")
        } catch {
            switch issue {
            case "emptyName": #expect(error as? MealLoggingError == .emptyTitle)
            case "emptyRows": #expect(error as? MealLoggingError == .emptyComponents)
            case "blankRow", "missingFood": #expect(error as? MealDraftValidationError == .unavailableFood)
            case "invalidFood": #expect(error as? MealLoggingError == .unsupportedUnit("ml"))
            case "duplicateID": #expect(error as? MealLoggingError == .duplicateComponentID(rows[0].id))
            case "overflow": #expect(error as? DomainValidationError == .calculationOverflow(field: "energyKcal"))
            default: #expect(error as? MealLoggingError == .invalidWeight)
            }
        }
        #expect(state.pendingRequest == first)
        #expect(state.mealID == first.meal.id)
        #expect(initialRows.map(\.weightText) == ["150.0", "50"])
    }

    @Test("Explicit invalidation clears only the retry request and never replaces the meal identity")
    func invalidationPreservesMealIdentity() throws {
        let (foods, rows) = try fixture()
        var state = MealCreateFormSaveState(sourceTemplateID: UUID())
        let first = try request(&state, rows: rows, foods: foods)
        state.invalidate()
        #expect(state.pendingRequest == nil)
        #expect(state.mealID == first.meal.id)
        let rebuilt = try state.request(title: "synthetic", eatenAt: clock, entryMethod: .weighed,
            coverageStatus: .complete, rows: rows, foods: foods, templateUsedAt: clock.addingTimeInterval(60))
        #expect(rebuilt.meal == first.meal)
        #expect(rebuilt.sourceTemplateID == first.sourceTemplateID)
        #expect(rebuilt.templateUsedAt == clock.addingTimeInterval(60))
    }

    @Test("Failure followed by edited retry persists the latest form payload with the original identity")
    func failureThenEditedRetryUsesCurrentValues() throws {
        let (foods, initialRows) = try fixture()
        let c = try container()
        var state = MealCreateFormSaveState()
        let first = try request(&state, rows: initialRows, foods: foods)
        do {
            try MealCreateCommand.save(request: first, in: c, saveContext: { _ in throw Injected.beforeCommit })
            Issue.record("Expected the injected pre-commit failure")
        } catch {
            #expect(error as? MealCreateCommandError == .saveFailed)
            state.handleSaveError(error)
        }
        #expect(state.hasCommittedResult == false)
        var rows = initialRows; rows[0].weightText = "200"
        let edited = try state.request(title: "latest synthetic", eatenAt: clock, entryMethod: .weighed,
            coverageStatus: .complete, rows: rows, foods: foods, templateUsedAt: clock.addingTimeInterval(60))
        let saved = try MealCreateCommand.save(request: edited, in: c)
        #expect(saved.id == first.meal.id)
        #expect(saved.title == "latest synthetic")
        #expect(saved.nutrients.energyKcal == 450)
        #expect(saved.components[0].consumedWeightGrams == 200)
        #expect(rows[0].weightText == "200")
        let stored = try ModelContext(c).fetch(FetchDescriptor<PersistentMealLog>())
        #expect(stored.count == 1)
        #expect(try #require(stored.first).domainModel() == saved)
    }

    @Test("After a known commit, unchanged raw input retries the frozen request despite changed or missing source foods", arguments: [false, true])
    func committedRefreshRetryDoesNotResolveChangedSources(missingSources: Bool) throws {
        let (foods, rows) = try fixture()
        let c = try container()
        var state = MealCreateFormSaveState()
        let committed = try request(&state, rows: rows, foods: foods)
        let originalInput = FormDraftSnapshot.meal(title: "synthetic", eatenAt: clock,
            entryMethod: .weighed, coverageStatus: .complete, components: rows)
        #expect(state.hasCommittedResult == false)
        #expect(state.canRetryCommittedRequest(comparedTo: originalInput) == false)
        do {
            try MealCreateCommand.save(request: committed, in: c, refreshContext: { _, _ in throw Injected.beforeCommit })
            Issue.record("Expected an injected post-commit refresh failure")
        } catch {
            #expect(error as? MealCreateCommandError == .savedButRefreshFailed)
            state.handleSaveError(error)
        }
        #expect(state.hasCommittedResult)
        #expect(state.canRetryCommittedRequest(comparedTo: originalInput))
        foods[0].energyKcalPer100Units = 999
        let retry = try state.request(title: "synthetic", eatenAt: clock, entryMethod: .weighed,
            coverageStatus: .complete, rows: rows, foods: missingSources ? [] : foods,
            templateUsedAt: clock.addingTimeInterval(60))
        #expect(retry == committed)
        #expect(retry.meal.nutrients.energyKcal == 350)
        #expect(try MealCreateCommand.save(request: retry, in: c) == committed.meal)
        #expect(try ModelContext(c).fetchCount(FetchDescriptor<PersistentMealLog>()) == 1)
    }

    @Test("Known committed inputs cannot be changed into another save; reverting the original raw input can verify that result")
    func knownCommitProtectsEditsAndSurvivesInvalidation() throws {
        let (foods, rows) = try fixture()
        var state = MealCreateFormSaveState()
        let committed = try request(&state, rows: rows, foods: foods)
        let originalInput = FormDraftSnapshot.meal(title: "synthetic", eatenAt: clock,
            entryMethod: .weighed, coverageStatus: .complete, components: rows)
        state.handleSaveError(MealCreateCommandError.savedButRefreshFailed)
        #expect(state.hasCommittedResult)
        #expect(state.canRetryCommittedRequest(comparedTo: originalInput))
        state.invalidate()
        #expect(state.hasCommittedResult)
        #expect(state.canRetryCommittedRequest(comparedTo: originalInput))
        var edited = rows; edited[0].weightText = "200"
        let editedInput = FormDraftSnapshot.meal(title: "synthetic", eatenAt: clock,
            entryMethod: .weighed, coverageStatus: .complete, components: edited)
        #expect(state.canRetryCommittedRequest(comparedTo: editedInput) == false)
        #expect(throws: MealCreateFormSaveStateError.alreadySaved) {
            try state.request(title: "synthetic", eatenAt: clock, entryMethod: .weighed,
                coverageStatus: .complete, rows: edited, foods: foods, templateUsedAt: clock.addingTimeInterval(60))
        }
        #expect(edited[0].weightText == "200")
        #expect(state.mealID == committed.meal.id)
        let verified = try request(&state, rows: rows, foods: [])
        #expect(verified == committed)
    }

    @Test("The formal new-meal entry rejects every invalid row rather than saving the valid subset", arguments: ["blank", "badWeight", "missingFood"])
    func formalEntryRejectsWholeMeal(issue: String) throws {
        let (foods, initialRows) = try fixture()
        let c = try container()
        var rows = initialRows
        switch issue {
        case "blank": rows.append(MealFormComponentDraft(decimalSeparator: "."))
        case "badWeight": rows[1].weightText = "."
        default: rows[1].foodItemID = UUID()
        }
        var state = MealCreateFormSaveState()
        let attempt: () throws -> Void = {
            let request = try state.request(title: "synthetic", eatenAt: clock, entryMethod: .weighed,
                coverageStatus: .complete, rows: rows, foods: foods, templateUsedAt: clock)
            try MealCreateCommand.save(request: request, in: c)
        }
        if issue == "badWeight" {
            #expect(throws: MealLoggingError.invalidWeight) { try attempt() }
        } else {
            #expect(throws: MealDraftValidationError.unavailableFood) { try attempt() }
        }
        #expect(state.pendingRequest == nil)
        #expect(try ModelContext(c).fetchCount(FetchDescriptor<PersistentMealLog>()) == 0)
        #expect(try ModelContext(c).fetchCount(FetchDescriptor<PersistentMealComponent>()) == 0)
        #expect(rows[0].weightText == "150.0")
    }

    private func request(_ state: inout MealCreateFormSaveState, rows: [MealFormComponentDraft],
                         foods: [PersistentFoodItem]) throws -> MealCreateRequest {
        try state.request(title: "synthetic", eatenAt: clock, entryMethod: .weighed,
            coverageStatus: .complete, rows: rows, foods: foods, templateUsedAt: clock)
    }

    private func fixture() throws -> ([PersistentFoodItem], [MealFormComponentDraft]) {
        let foods = try [food(name: "first synthetic", energy: 200, fibre: nil), food(name: "second synthetic", energy: 100, fibre: 0)]
            .map(PersistentFoodItem.init(domain:))
        var first = MealFormComponentDraft(component: .init(foodItemID: foods[0].id, foodName: foods[0].name), decimalSeparator: ".")
        first.weightText = "150.0"
        var second = MealFormComponentDraft(component: .init(foodItemID: foods[1].id, foodName: foods[1].name), decimalSeparator: ".")
        second.weightText = "50"
        return (foods, [first, second])
    }

    private func food(name: String, energy: Double, fibre: Double?) throws -> FoodItem {
        try FoodItem(name: name, category: .stapleGrain,
            nutrientsPer100Units: NutrientValues(energyKcal: energy, fatGrams: 10, saturatedFatGrams: 2,
                carbohydrateGrams: 20, sugarGrams: 4, proteinGrams: 5, saltGrams: 0.2, fibreGrams: fibre),
            source: "synthetic acceptance fixture")
    }

    private func container() throws -> ModelContainer {
        let schema = Schema(versionedSchema: VersionedSchemaV2.self)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let c = try ModelContainer(for: schema, migrationPlan: ShiHengMigrationPlan.self, configurations: config)
        c.mainContext.autosaveEnabled = false
        return c
    }

    private enum Injected: Error { case beforeCommit }
}
