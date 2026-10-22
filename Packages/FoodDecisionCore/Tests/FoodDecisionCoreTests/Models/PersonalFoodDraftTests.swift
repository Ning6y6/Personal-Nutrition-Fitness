import Foundation
import Testing
@testable import FoodDecisionCore

struct PersonalFoodDraftTests {
    private let foodID = UUID(uuidString: "60000000-0000-4000-8000-000000000013")!
    private static let requiredFields = [
        "energyKcal", "fatGrams", "saturatedFatGrams", "carbohydrateGrams", "sugarGrams", "proteinGrams", "saltGrams"
    ]
    private static let numericFields = requiredFields + ["fibreGrams"]

    @Test("New cards contain no implied nutrition values")
    func newCardIsEmpty() {
        let draft = PersonalFoodDraft()
        #expect(draft.name == "")
        #expect(draft.sourceNote == "")
        for field in Self.numericFields {
            #expect(value(field, in: draft) == "")
        }
    }

    @Test("Each required nutrient must be explicitly entered, including zero", arguments: requiredFields)
    func missingRequiredNutrient(field: String) {
        var draft = honey()
        set(" \n", field: field, in: &draft)
        #expect(throws: PersonalFoodInputError.missingRequiredField(field)) {
            try draft.validFood(id: foodID)
        }
        #expect(value(field, in: draft) == " \n")
    }

    @Test("No text, inequality, missing-value token, non-finite value, grouping, or negative becomes nutrition", arguments: numericFields, [".", "<0.1", "Tr", "N", "abc", "1,000", "1 000", "1_000", "12 g", "NaN", "Inf", "-Infinity", "1e309", "-0.5", "1e-999"])
    func invalidNumericText(field: String, text: String) {
        var draft = honey()
        set(text, field: field, in: &draft)
        #expect(throws: PersonalFoodInputError.invalidNumber(field)) {
            try draft.validFood(id: foodID)
        }
        #expect(value(field, in: draft) == text)
    }

    @Test("Whitespace-only names cannot be saved")
    func nameRequired() {
        var draft = honey()
        draft.name = " \n"
        #expect(throws: PersonalFoodInputError.missingRequiredField("name")) {
            try draft.validFood(id: foodID)
        }
        #expect(draft.name == " \n")
    }

    @Test("Explicit zeros stay known while empty optional fibre stays unknown")
    func nilAndZeroAreDifferent() throws {
        var draft = honey()
        let unknown = try draft.validFood(id: foodID)
        #expect(unknown.nutrientsPer100Units.fatGrams == 0)
        #expect(unknown.nutrientsPer100Units.saltGrams == 0)
        #expect(unknown.nutrientsPer100Units.fibreGrams == nil)
        draft.fibreGrams = "0.0"
        let known = try draft.validFood(id: foodID)
        #expect(known.nutrientsPer100Units.fibreGrams == 0)
        draft.energyKcal = "0"
        #expect(try draft.validFood(id: foodID).nutrientsPer100Units.energyKcal == 0)
    }

    @Test("Only the explicit decimal separator is accepted", arguments: [".", ","])
    func decimalLocale(separator: String) throws {
        var draft = proteinPowder()
        draft.saltGrams = "0\(separator)5"
        let food = try draft.validFood(id: foodID, decimalSeparator: separator)
        #expect(food.nutrientsPer100Units.saltGrams == 0.5)
        let restored = try PersonalFoodDraft(food: food, decimalSeparator: separator)
        #expect(restored.saltGrams == "0\(separator)5")
        #expect(try restored.validFood(id: foodID, decimalSeparator: separator) == food)
        draft.saltGrams = separator == "." ? "0,5" : "0.5"
        #expect(throws: PersonalFoodInputError.invalidNumber("saltGrams")) {
            try draft.validFood(id: foodID, decimalSeparator: separator)
        }
    }

    @Test("Unknown decimal separators fail without mutation", arguments: ["", "..", ":"])
    func unsupportedSeparator(separator: String) {
        let draft = honey()
        #expect(throws: PersonalFoodInputError.unsupportedDecimalSeparator(separator)) {
            try draft.validFood(id: foodID, decimalSeparator: separator)
        }
    }

    @Test("A valid saved card uses g and retains its chosen existing category", arguments: FoodCategory.allCases)
    func categoriesAndSource(category: FoodCategory) throws {
        var draft = honey()
        draft.category = category
        draft.name = "  验收测试蜂蜜 \n"
        draft.sourceNote = " 包装每 100 g\nCoFID 只是我写的说明 "
        let food = try draft.validFood(id: foodID)
        #expect(food.id == foodID)
        #expect(food.category == category)
        #expect(food.name == "验收测试蜂蜜")
        #expect(food.unit == "g")
        #expect(draft.name == "  验收测试蜂蜜 \n")
        #expect(try #require(PersonalFoodSource.decode(source: food.source, foodID: food.id)).note == draft.sourceNote)
        #expect(try FoodCatalog.bundled().metadata(for: food) == nil)
    }

    @Test("Unmarked food or another quantity basis cannot be opened as an editable personal card")
    func editRequiresValidIdentityAndGramBasis() throws {
        let marked = try honey().validFood(id: foodID)
        let unmarked = try FoodItem(id: foodID, name: marked.name, category: marked.category, nutrientsPer100Units: marked.nutrientsPer100Units, source: "用户录入")
        #expect(throws: PersonalFoodInputError.notPersonalFood) {
            try PersonalFoodDraft(food: unmarked)
        }
        let per100ml = try FoodItem(id: foodID, name: marked.name, category: marked.category, nutrientsPer100Units: marked.nutrientsPer100Units, unit: "ml", source: marked.source)
        #expect(throws: PersonalFoodInputError.notPersonalFood) {
            try PersonalFoodDraft(food: per100ml)
        }
    }

    @Test("Opening and resaving retains exact stored Double precision and unknown fibre", arguments: [".", ","])
    func roundTripPrecision(separator: String) throws {
        let nutrients = try NutrientValues(
            energyKcal: Double(300).nextUp,
            fatGrams: Double(0.1).nextUp,
            saturatedFatGrams: Double.leastNonzeroMagnitude,
            carbohydrateGrams: Double(75).nextDown,
            sugarGrams: 0,
            proteinGrams: Double(0.3).nextUp,
            saltGrams: Double(0.2).nextDown
        )
        let food = try FoodItem(id: foodID, name: "精度测试", category: .sauce, nutrientsPer100Units: nutrients, source: PersonalFoodSource.encode(foodID: foodID, note: ""))
        let draft = try PersonalFoodDraft(food: food, decimalSeparator: separator)
        #expect(try draft.validFood(id: foodID, decimalSeparator: separator) == food)
        #expect(draft.fibreGrams == "")
    }

    @Test("Card validation preserves raw fractional text without changing the draft")
    func validatingDoesNotRewriteText() throws {
        var draft = proteinPowder()
        draft.energyKcal = " 400.0 "
        draft.saltGrams = ".5"
        draft.fibreGrams = "0.000"
        let original = draft
        let food = try draft.validFood(id: foodID)
        #expect(food.nutrientsPer100Units.energyKcal == 400)
        #expect(food.nutrientsPer100Units.saltGrams == 0.5)
        #expect(draft == original)
    }

    @Test("Acceptance honey and protein powder use existing unrounded gram scaling")
    func acceptanceNutritionMath() throws {
        let honeyFood = try honey().validFood(id: foodID)
        let honeyServing = try MealComponent(foodItem: honeyFood, consumedWeightGrams: 60)
        #expect(honeyServing.nutrients.energyKcal == 180)
        #expect(honeyServing.nutrients.carbohydrateGrams == 45)
        #expect(honeyServing.nutrients.fibreGrams == nil)

        var powder = proteinPowder()
        let oldFood = try powder.validFood(id: foodID)
        let oldServing = try MealComponent(foodItem: oldFood, consumedWeightGrams: 30)
        powder.energyKcal = "450"
        let currentFood = try powder.validFood(id: foodID)
        let newServing = try MealComponent(foodItem: currentFood, consumedWeightGrams: 30)
        #expect(oldServing.nutrients.energyKcal == 120)
        #expect(oldServing.nutrients.proteinGrams == 24)
        #expect(newServing.nutrients.energyKcal == 135)
        #expect(oldFood.nutrientsPer100Units.energyKcal == 400)
    }

    private func honey() -> PersonalFoodDraft {
        var draft = PersonalFoodDraft()
        draft.name = "验收测试蜂蜜"
        draft.energyKcal = "300"
        draft.fatGrams = "0"
        draft.saturatedFatGrams = "0"
        draft.carbohydrateGrams = "75"
        draft.sugarGrams = "75"
        draft.proteinGrams = "0"
        draft.saltGrams = "0"
        return draft
    }

    private func proteinPowder() -> PersonalFoodDraft {
        var draft = honey()
        draft.name = "验收测试蛋白粉"
        draft.energyKcal = "400"
        draft.fatGrams = "6"
        draft.saturatedFatGrams = "2"
        draft.carbohydrateGrams = "10"
        draft.sugarGrams = "3"
        draft.proteinGrams = "80"
        draft.saltGrams = "0.5"
        return draft
    }

    private func keyPath(_ field: String) -> WritableKeyPath<PersonalFoodDraft, String> {
        switch field {
        case "energyKcal": \.energyKcal
        case "fatGrams": \.fatGrams
        case "saturatedFatGrams": \.saturatedFatGrams
        case "carbohydrateGrams": \.carbohydrateGrams
        case "sugarGrams": \.sugarGrams
        case "proteinGrams": \.proteinGrams
        case "saltGrams": \.saltGrams
        default: \.fibreGrams
        }
    }

    private func set(_ text: String, field: String, in draft: inout PersonalFoodDraft) {
        draft[keyPath: keyPath(field)] = text
    }

    private func value(_ field: String, in draft: PersonalFoodDraft) -> String {
        draft[keyPath: keyPath(field)]
    }
}
