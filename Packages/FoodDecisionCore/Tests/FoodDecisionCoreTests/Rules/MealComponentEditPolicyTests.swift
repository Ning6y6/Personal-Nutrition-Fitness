import Foundation
import Testing
@testable import FoodDecisionCore

struct MealComponentEditPolicyTests {
    @Test("Unchanged rows preserve their complete snapshot despite missing or changed sources", arguments: [
        "missing", "updated", "unrelated",
    ])
    func unchangedSnapshotDoesNotReadCurrentFood(source: String) throws {
        let original = try component()
        let current: FoodItem? = switch source {
        case "missing": nil
        case "updated": try food(id: original.foodItemID, name: "新名称", nutrients: .zero, unit: "ml")
        default: try food(name: "无关食物", nutrients: .zero)
        }

        let result = try resolve(original, weight: original.consumedWeightGrams, current: current)

        #expect(result == original)
        #expect(result.foodName == "原餐食物")
    }

    @Test("Changing only quantity scales all original nutrients and keeps the old name", arguments: [false, true])
    func quantityEditScalesTheSavedSnapshot(increase: Bool) throws {
        let original = try component()
        let updatedSource = try food(id: original.foodItemID, name: "已修订食物", nutrients: .zero)
        let result = try resolve(original, weight: increase ? 160 : 40, current: updatedSource)

        #expect(result.id == original.id)
        #expect(result.foodItemID == original.foodItemID)
        #expect(result.foodName == "原餐食物")
        #expect(result.unit == "g")
        #expect(result.consumedWeightGrams == (increase ? 160 : 40))
        #expect(result.nutrients == (try nutrients(
            energy: increase ? 240 : 60,
            fat: increase ? 8 : 2,
            saturated: increase ? 2 : 0.5,
            carbohydrate: increase ? 24 : 6,
            sugar: increase ? 12 : 3,
            protein: increase ? 16 : 4,
            salt: increase ? 0.8 : 0.2,
            fibre: increase ? 6 : 1.5
        )))
    }

    @Test("Quantity editing still works when the source food no longer exists")
    func missingSourceDoesNotBlockQuantityEdit() throws {
        let original = try component()
        let result = try resolve(original, weight: 120)
        #expect(result.nutrients.energyKcal == 180)
        #expect(result.nutrients.proteinGrams == 12)
        #expect(result.foodName == original.foodName)
    }

    @Test("Repeated previews and save retries always use the session's original snapshot")
    func sessionBaselineDoesNotAccumulateEdits() throws {
        let original = try component()
        let first = try resolve(original, weight: 120)
        let smaller = try resolve(original, weight: 40)
        let larger = try resolve(original, weight: 160)
        let retry = try resolve(original, weight: 160)
        let restored = try resolve(original, weight: 80)

        #expect(first.nutrients.energyKcal == 180)
        #expect(smaller.nutrients.energyKcal == 60)
        #expect(larger.nutrients.energyKcal == 240)
        #expect(retry == larger)
        #expect(restored == original)
        #expect(original.consumedWeightGrams == 80)
        #expect(original.nutrients.energyKcal == 120)
    }

    @Test("Unknown fibre remains unknown and verified zero nutrients remain zero", arguments: [false, true])
    func unknownAndZeroArePreserved(knownZeroFibre: Bool) throws {
        let values = try nutrients(energy: 0, fat: 0, saturated: 0, carbohydrate: 0,
                                  sugar: 0, protein: 0, salt: 0, fibre: knownZeroFibre ? 0 : nil)
        let original = try component(nutrients: values)
        let result = try resolve(original, weight: 160)

        #expect(result.nutrients == values)
        #expect(result.nutrients.fibreGrams == (knownZeroFibre ? 0 : nil))
    }

    @Test("Selecting a different food recomputes this row from the matching selected source")
    func replacingFoodUsesSelectedSource() throws {
        let original = try component()
        let replacement = try food(name: "替换食物", nutrients: nutrients(energy: 300))
        let result = try MealComponentEditPolicy.resolve(
            original: original, id: original.id, foodItemID: replacement.id,
            weightGrams: 50, currentFood: replacement
        )

        #expect(result.id == original.id)
        #expect(result.foodItemID == replacement.id)
        #expect(result.foodName == "替换食物")
        #expect(result.nutrients.energyKcal == 150)
        #expect(original.nutrients.energyKcal == 120)
    }

    @Test("New rows calculate their own selected food without inheriting an old snapshot")
    func newRowUsesSelectedSource() throws {
        let selected = try food(nutrients: nutrients(energy: 200))
        let rowID = UUID()
        let result = try MealComponentEditPolicy.resolve(
            original: nil, id: rowID, foodItemID: selected.id,
            weightGrams: 40, currentFood: selected
        )

        #expect(result.id == rowID)
        #expect(result.foodItemID == selected.id)
        #expect(result.nutrients.energyKcal == 80)
        let fibre = try #require(result.nutrients.fibreGrams)
        #expect(abs(fibre - 1.2) < 1e-12)
    }

    @Test("New and replaced food selections require the exact source identity", arguments: [false, true], [
        "missingSelection", "missingSource", "wrongSource",
    ])
    func unavailableSelectionCannotBorrowAnotherFood(replacement: Bool, missing: String) throws {
        let original = try component()
        let requestedID = UUID()
        let selectedID: UUID? = missing == "missingSelection" ? nil : requestedID
        let current = missing == "missingSource" ? nil : try food()

        #expect(throws: MealComponentEditError.unavailableFood) {
            try MealComponentEditPolicy.resolve(
                original: replacement ? original : nil, id: original.id, foodItemID: selectedID,
                weightGrams: 100, currentFood: current
            )
        }
    }

    @Test("A snapshot from another row can never be retargeted", arguments: [false, true])
    func mismatchedOriginalIdentityIsRejected(replacement: Bool) throws {
        let original = try component()
        let selected = try food()
        #expect(throws: MealComponentEditError.mismatchedOriginalID) {
            try MealComponentEditPolicy.resolve(
                original: original, id: UUID(),
                foodItemID: replacement ? selected.id : original.foodItemID,
                weightGrams: 100, currentFood: selected
            )
        }
    }

    @Test("Both old and new rows reject invalid quantities", arguments: [false, true], [
        0.0, -1, Double.nan, Double.infinity, -Double.infinity,
    ])
    func invalidQuantityIsRejected(existing: Bool, weight: Double) throws {
        let original = try component()
        let selected = try food(id: original.foodItemID)
        let expected: MealLoggingError = weight.isFinite ? .invalidWeight : .nonFiniteWeight
        #expect(throws: expected) {
            try MealComponentEditPolicy.resolve(
                original: existing ? original : nil, id: original.id, foodItemID: selected.id,
                weightGrams: weight, currentFood: selected
            )
        }
    }

    @Test("A missing quantity never reuses the old quantity", arguments: [false, true])
    func absentQuantityIsRejected(existing: Bool) throws {
        let original = try component()
        let selected = try food(id: original.foodItemID)
        #expect(throws: MealLoggingError.invalidWeight) {
            try MealComponentEditPolicy.resolve(
                original: existing ? original : nil, id: original.id, foodItemID: selected.id,
                weightGrams: nil, currentFood: selected
            )
        }
    }

    @Test("New source units retain the existing g-only contract", arguments: [false, true], ["ml", "kg"])
    func unsupportedSourceUnitIsRejected(replacement: Bool, unit: String) throws {
        let original = try component()
        let selected = try food(unit: unit)
        #expect(throws: MealLoggingError.unsupportedUnit(unit)) {
            try MealComponentEditPolicy.resolve(
                original: replacement ? original : nil, id: original.id, foodItemID: selected.id,
                weightGrams: 100, currentFood: selected
            )
        }
    }

    @Test("A non-finite quantity ratio is rejected even when all nutrients are zero")
    func ratioOverflowIsRejected() throws {
        let original = try component(weight: .leastNonzeroMagnitude, nutrients: .zero)
        #expect(throws: DomainValidationError.calculationOverflow(field: "weightRatio")) {
            try resolve(original, weight: .greatestFiniteMagnitude)
        }
    }

    @Test("A positive quantity ratio cannot silently underflow to zero")
    func ratioUnderflowIsRejected() throws {
        let original = try component(weight: .greatestFiniteMagnitude, nutrients: .zero)
        #expect(throws: MealComponentEditError.calculationUnderflow(field: "weightRatio")) {
            try resolve(original, weight: .leastNonzeroMagnitude)
        }
    }

    @Test("Every nutrient reports product overflow for old snapshots and new sources", arguments: [false, true], [
        "energyKcal", "fatGrams", "saturatedFatGrams", "carbohydrateGrams",
        "sugarGrams", "proteinGrams", "saltGrams", "fibreGrams",
    ])
    func nutrientOverflowIsRejected(existing: Bool, field: String) throws {
        let values = try nutrients(overriding: [field: .greatestFiniteMagnitude])
        let original = try component(weight: 100, nutrients: values)
        let selected = try food(id: original.foodItemID, nutrients: values)
        #expect(throws: DomainValidationError.calculationOverflow(field: field)) {
            try MealComponentEditPolicy.resolve(
                original: existing ? original : nil, id: original.id, foodItemID: selected.id,
                weightGrams: 200, currentFood: selected
            )
        }
    }

    @Test("Every positive nutrient is protected against underflow into a false known zero", arguments: [false, true], [
        "energyKcal", "fatGrams", "saturatedFatGrams", "carbohydrateGrams",
        "sugarGrams", "proteinGrams", "saltGrams", "fibreGrams",
    ])
    func nutrientUnderflowIsRejected(existing: Bool, field: String) throws {
        let values = try nutrients(overriding: [field: .leastNonzeroMagnitude])
        let original = try component(weight: 100, nutrients: values)
        let selected = try food(id: original.foodItemID, nutrients: values)
        #expect(throws: MealComponentEditError.calculationUnderflow(field: field)) {
            try MealComponentEditPolicy.resolve(
                original: existing ? original : nil, id: original.id, foodItemID: selected.id,
                weightGrams: 50, currentFood: selected
            )
        }
    }

    @Test("Representable positive subnormal nutrients are preserved", arguments: [false, true])
    func subnormalValueIsNotRoundedAway(existing: Bool) throws {
        let values = try nutrients(overriding: ["energyKcal": Double.leastNonzeroMagnitude * 2])
        let original = try component(weight: 100, nutrients: values)
        let selected = try food(id: original.foodItemID, nutrients: values)
        let result = try MealComponentEditPolicy.resolve(
            original: existing ? original : nil, id: original.id, foodItemID: selected.id,
            weightGrams: 50, currentFood: selected
        )
        #expect(result.nutrients.energyKcal == Double.leastNonzeroMagnitude)
    }

    @Test("The per100 multiplier of a new food cannot silently become zero")
    func newFoodRatioUnderflowIsRejected() throws {
        let selected = try food(nutrients: .zero)
        #expect(throws: MealComponentEditError.calculationUnderflow(field: "weightRatio")) {
            try MealComponentEditPolicy.resolve(
                original: nil, id: UUID(), foodItemID: selected.id,
                weightGrams: .leastNonzeroMagnitude, currentFood: selected
            )
        }
    }

    @Test("Editing one of two rows for the same food does not replace the other row's snapshot")
    func anotherRowForTheSameFoodIsPreserved() throws {
        let original = try component()
        let other = try component(foodID: original.foodItemID, weight: 200,
                                  nutrients: nutrients(energy: 230, fibre: nil))
        let changed = try resolve(original, weight: 160)
        let meal = try MealLog(title: "虚构测试餐", entryMethod: .weighed,
                               coverageStatus: .complete, components: [changed, other])

        #expect(meal.components[1] == other)
        #expect(meal.components.map(\.id) == [original.id, other.id])
        #expect(meal.consumedWeightGrams == 360)
        #expect(meal.nutrients.energyKcal == 470)
        #expect(meal.nutrients.fibreGrams == nil)
        let fibre = try FibreIntakeSummary(snapshots: meal.components.map(\.nutrients))
        #expect(fibre.knownSubtotalGrams == 6)
        #expect(fibre.unknownComponentCount == 1)
    }

    private func resolve(_ original: MealComponent, weight: Double, current: FoodItem? = nil) throws -> MealComponent {
        try MealComponentEditPolicy.resolve(original: original, id: original.id,
                                            foodItemID: original.foodItemID,
                                            weightGrams: weight, currentFood: current)
    }

    private func component(
        foodID: UUID = UUID(), weight: Double = 80, nutrients values: NutrientValues? = nil
    ) throws -> MealComponent {
        try MealComponent(foodItemID: foodID, foodName: "原餐食物", consumedWeightGrams: weight,
                          unit: "g", nutrients: values ?? nutrients())
    }

    private func food(
        id: UUID = UUID(), name: String = "虚构来源食物", nutrients values: NutrientValues? = nil,
        unit: String = "g"
    ) throws -> FoodItem {
        try FoodItem(id: id, name: name, category: .mixedMeal,
                     nutrientsPer100Units: values ?? nutrients(), unit: unit, source: "test")
    }

    private func nutrients(
        energy: Double = 120, fat: Double = 4, saturated: Double = 1, carbohydrate: Double = 12,
        sugar: Double = 6, protein: Double = 8, salt: Double = 0.4, fibre: Double? = 3,
        overriding overrides: [String: Double] = [:]
    ) throws -> NutrientValues {
        try NutrientValues(
            energyKcal: overrides["energyKcal"] ?? energy,
            fatGrams: overrides["fatGrams"] ?? fat,
            saturatedFatGrams: overrides["saturatedFatGrams"] ?? saturated,
            carbohydrateGrams: overrides["carbohydrateGrams"] ?? carbohydrate,
            sugarGrams: overrides["sugarGrams"] ?? sugar,
            proteinGrams: overrides["proteinGrams"] ?? protein,
            saltGrams: overrides["saltGrams"] ?? salt,
            fibreGrams: overrides["fibreGrams"] ?? fibre
        )
    }
}
