import FoodDecisionCore
import Foundation
import SwiftData
import Testing
@testable import FoodDecisionAssistant

@MainActor
struct MealEditFormStateTests {
    private let store: ModelContainer

    init() throws {
        let schema = Schema(versionedSchema: VersionedSchemaV2.self)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        store = try ModelContainer(for: schema, migrationPlan: ShiHengMigrationPlan.self, configurations: configuration)
        store.mainContext.autosaveEnabled = false
    }

    @Test("Metadata changes do not require a current food or rebuild components")
    func metadataDoesNotResolveFood() throws {
        let (state, rows) = try fixture()
        let changes = try state.changes(
            title: "改名", eatenAt: state.initialDate.addingTimeInterval(60),
            entryMethod: state.initialMethod, coverageStatus: state.initialCoverage,
            rows: rows, foods: []
        )
        #expect(changes.title == "改名")
        #expect(changes.components == nil)
        #expect(changes.entryMethod == nil)
        #expect(changes.coverageStatus == nil)
        #expect(try state.resolve(rows[0], foods: []).nutrients.energyKcal == 131)
    }

    @Test("Equivalent numeric text is unchanged, but invalid raw input cannot pass as metadata")
    func equivalentTextAndInvalidInput() throws {
        let (state, initialRows) = try fixture()
        var rows = initialRows
        rows[0].weightText = "100.0"
        #expect(state.componentsAreUnchanged(rows))
        #expect(try changes(state, rows: rows).components == nil)
        rows[0].weightText = "."
        #expect(!state.componentsAreUnchanged(rows))
        #expect(throws: MealLoggingError.invalidWeight) { try changes(state, rows: rows) }
    }

    @Test("All previews use the session baseline despite a changed or invalid current food")
    func previewAlwaysUsesOriginal() throws {
        let (state, initialRows) = try fixture()
        let foodID = try #require(initialRows[0].foodItemID)
        let source = PersistentFoodItem(domain: try food(id: foodID, energy: 900))
        source.energyKcalPer100Units = .nan
        var rows = initialRows
        for (text, expected) in [("200", 262.0), ("300", 393.0), ("100", 131.0)] {
            rows[0].weightText = text
            let resolved = try state.resolve(rows[0], foods: [source])
            #expect(resolved.nutrients.energyKcal == expected)
            #expect(resolved.foodName == "原名")
            #expect(resolved.id == rows[0].id)
            #expect(resolved.nutrients.fibreGrams == nil)
        }
        #expect(try changes(state, rows: rows).components == nil)
    }

    @Test("Replacing a food uses its current values without changing the row identity")
    func replacingFoodUsesNewSource() throws {
        let (state, initialRows) = try fixture()
        let replacement = PersistentFoodItem(domain: try food(energy: 500))
        var rows = initialRows
        rows[0].foodItemID = replacement.id
        #expect(!state.isOriginalFood(rows[0]))
        let component = try state.resolve(rows[0], foods: [replacement])
        #expect(component.id == rows[0].id)
        #expect(component.foodName == "新名")
        #expect(component.nutrients.energyKcal == 500)
        #expect(throws: MealComponentEditError.unavailableFood) { try state.resolve(rows[0], foods: []) }
    }

    @Test("Invalid historical quantities can remain untouched but cannot be recalculated")
    func invalidHistoryIsNotRepairedFromCurrentFood() throws {
        let meal = try persistentMeal()
        meal.components[0].consumedWeightGrams = .nan
        let (state, initialRows) = fixture(meal)
        #expect(try changes(state, rows: initialRows).components == nil)
        var rows = initialRows
        rows[0].weightText = "200"
        #expect(throws: MealLoggingError.nonFiniteWeight) { try changes(state, rows: rows) }
    }

    @Test("Explicitly replacing a damaged old food uses the new source")
    func damagedRowCanBeExplicitlyReplaced() throws {
        let meal = try persistentMeal()
        meal.components[0].consumedWeightGrams = .nan
        let (state, initialRows) = fixture(meal)
        let replacement = PersistentFoodItem(domain: try food(energy: 500))
        var rows = initialRows
        rows[0].foodItemID = replacement.id
        rows[0].weightText = "100"
        #expect(try state.resolve(rows[0], foods: [replacement]).nutrients.energyKcal == 500)
    }

    @Test("An existing zero-component record stays zero-component for metadata edits")
    func emptyHistoryDoesNotGainPlaceholder() throws {
        let meal = try persistentMeal()
        meal.components = []
        let (state, rows) = fixture(meal)
        #expect(rows.isEmpty)
        #expect(try changes(state, rows: rows).components == nil)
    }

    private func changes(_ state: MealEditFormState, rows: [MealFormComponentDraft]) throws -> MealEditChanges {
        try state.changes(title: state.initialTitle, eatenAt: state.initialDate,
                          entryMethod: state.initialMethod, coverageStatus: state.initialCoverage,
                          rows: rows, foods: [])
    }

    private func fixture() throws -> (MealEditFormState, [MealFormComponentDraft]) {
        fixture(try persistentMeal())
    }

    private func fixture(_ meal: PersistentMealLog) -> (MealEditFormState, [MealFormComponentDraft]) {
        let rows = meal.components.map {
            MealFormComponentDraft(component: .init(id: $0.id, foodItemID: $0.foodItemID,
                foodName: $0.foodName, weightGrams: $0.consumedWeightGrams), decimalSeparator: ".")
        }
        let state = MealEditFormState(baseline: .capture(meal), initialRows: rows,
            initialTitle: meal.title, initialDate: meal.eatenAt,
            initialMethod: .weighed, initialCoverage: .complete)
        return (state, rows)
    }

    private func persistentMeal() throws -> PersistentMealLog {
        let source = try food(energy: 131)
        let meal = PersistentMealLog(domain: try MealLog(title: "测试餐", entryMethod: .weighed,
            coverageStatus: .complete, components: [try MealComponent(foodItem: source, consumedWeightGrams: 100)]))
        store.mainContext.insert(meal)
        try store.mainContext.save()
        try #require(meal.components.count == 1)
        return meal
    }

    private func food(id: UUID = UUID(), energy: Double) throws -> FoodItem {
        try FoodItem(id: id, name: energy == 131 ? "原名" : "新名", category: .stapleGrain,
            nutrientsPer100Units: NutrientValues(energyKcal: energy, fatGrams: 0,
                saturatedFatGrams: 0, carbohydrateGrams: 0, sugarGrams: 0,
                proteinGrams: 0, saltGrams: 0), source: "虚构验收数据")
    }
}
