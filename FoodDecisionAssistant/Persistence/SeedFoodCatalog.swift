import FoodDecisionCore
import Foundation
import SwiftData

enum SeedFoodCatalog {
    enum LoadError: Error { case invalidIdentifier }

    /// Validate every bundled record before mutating the store; missing fibre remains nil.
    static func loadFoods() throws -> [FoodItem] {
        try [
        food(
            id: "20000000-0000-4000-8000-000000011862",
            name: "熟长粒白米饭（无盐）",
            category: .stapleGrain,
            code: "11-862",
            energy: 131,
            fat: 0.4,
            saturatedFat: 0.09,
            carbohydrate: 31.1,
            sugar: 0,
            protein: 2.8,
            salt: 0.0275,
            fibre: 0.5
        ),
        food(
            id: "20000000-0000-4000-8000-000000013517",
            name: "西红柿（生）",
            category: .mixedMeal,
            code: "13-517",
            energy: 14,
            fat: 0.1,
            saturatedFat: 0.03,
            carbohydrate: 3,
            sugar: 3,
            protein: 0.5,
            salt: 0.005,
            fibre: 1
        ),
        food(
            id: "20000000-0000-4000-8000-000000012937",
            name: "鸡蛋（全蛋，生）",
            category: .proteinMain,
            code: "12-937",
            energy: 131,
            fat: 9,
            saturatedFat: 2.52,
            carbohydrate: 0,
            sugar: 0,
            protein: 12.6,
            salt: 0.385,
            fibre: 0
        ),
        food(
            id: "20000000-0000-4000-8000-000000013318",
            name: "青椒（生）",
            category: .mixedMeal,
            code: "13-318",
            energy: 15,
            fat: 0.3,
            saturatedFat: 0.1,
            carbohydrate: 2.6,
            sugar: 2.4,
            protein: 0.8,
            salt: 0.01,
            fibre: nil
        ),
        food(
            id: "20000000-0000-4000-8000-000000013161",
            name: "茄子（生）",
            category: .mixedMeal,
            code: "13-161",
            energy: 15,
            fat: 0.4,
            saturatedFat: 0.1,
            carbohydrate: 2.2,
            sugar: 2,
            protein: 0.9,
            salt: 0.005,
            fibre: nil
        ),
        food(
            id: "20000000-0000-4000-8000-000000013570",
            name: "豆腐（原味/蒸）",
            category: .proteinMain,
            code: "13-570",
            energy: 73,
            fat: 4.2,
            saturatedFat: 0.5,
            carbohydrate: 0.7,
            sugar: 0.3,
            protein: 8.1,
            salt: 0.01,
            fibre: nil
        ),
        food(
            id: "20000000-0000-4000-8000-000000018006",
            name: "炖煮牛肉（生瘦肉）",
            category: .proteinMain,
            code: "18-006",
            energy: 139,
            fat: 5.7,
            saturatedFat: 2.4,
            carbohydrate: 0,
            sugar: 0,
            protein: 21.8,
            salt: 0.16,
            fibre: nil
        ),
        food(
            id: "20000000-0000-4000-8000-000000018020",
            name: "牛排（烤熟瘦肉）",
            category: .proteinMain,
            code: "18-020",
            energy: 188,
            fat: 8,
            saturatedFat: 3.6,
            carbohydrate: 0,
            sugar: 0,
            protein: 29.1,
            salt: 0.175,
            fibre: nil
        ),
        food(
            id: "20000000-0000-4000-8000-000000018323",
            name: "鸡胸肉（去皮烤熟）",
            category: .proteinMain,
            code: "18-323",
            energy: 148,
            fat: 2.2,
            saturatedFat: 0.6,
            carbohydrate: 0,
            sugar: 0,
            protein: 32,
            salt: 0.1375,
            fibre: 0
        ),
        food(
            id: "20000000-0000-4000-8000-000000018319",
            name: "鸡腿肉（去皮炖熟）",
            category: .proteinMain,
            code: "18-319",
            energy: 180,
            fat: 8.6,
            saturatedFat: 2.4,
            carbohydrate: 0,
            sugar: 0,
            protein: 25.6,
            salt: 0.1,
            fibre: nil
        ),
        food(
            id: "20000000-0000-4000-8000-000000017041",
            name: "菜籽油",
            category: .oil,
            code: "17-041",
            energy: 899,
            fat: 99.9,
            saturatedFat: 6.6,
            carbohydrate: 0,
            sugar: 0,
            protein: 0,
            salt: 0,
            fibre: 0
        ),
        food(
            id: "20000000-0000-4000-8000-000000017721",
            name: "酱油（生抽/老抽平均）",
            category: .sauce,
            code: "17-721",
            energy: 79,
            fat: 0,
            saturatedFat: 0,
            carbohydrate: 17.9,
            sugar: 16.4,
            protein: 3,
            salt: 13.75,
            fibre: 0
        ),
        ]
    }

    private static let deprecatedSeedFoodIDs: Set<String> = [
        "20000000-0000-4000-8000-000000018521",
    ]

    @discardableResult
    static func importIfNeeded(into modelContext: ModelContext) throws -> Int {
        let foods = try loadFoods()
        let existingFoods = try modelContext.fetch(FetchDescriptor<PersistentFoodItem>())
        let deprecatedFoods = existingFoods.filter { deprecatedSeedFoodIDs.contains($0.id.uuidString) }
        for foodItem in deprecatedFoods {
            modelContext.delete(foodItem)
        }

        let existingIDs = Set(
            existingFoods
                .filter { !deprecatedSeedFoodIDs.contains($0.id.uuidString) }
                .map(\.id)
        )
        let missingFoods = foods.filter { !existingIDs.contains($0.id) }

        for foodItem in missingFoods {
            modelContext.insert(PersistentFoodItem(domain: foodItem))
        }

        if !missingFoods.isEmpty || !deprecatedFoods.isEmpty {
            try modelContext.save()
        }

        return missingFoods.count
    }

    private static func food(
        id: String,
        name: String,
        category: FoodCategory,
        code: String,
        energy: Double,
        fat: Double,
        saturatedFat: Double,
        carbohydrate: Double,
        sugar: Double,
        protein: Double,
        salt: Double,
        fibre: Double?
    ) throws -> FoodItem {
        guard let foodID = UUID(uuidString: id) else { throw LoadError.invalidIdentifier }
        return try FoodItem(
            id: foodID,
            name: name,
            category: category,
            nutrientsPer100Units: NutrientValues(
                energyKcal: energy,
                fatGrams: fat,
                saturatedFatGrams: saturatedFat,
                carbohydrateGrams: carbohydrate,
                sugarGrams: sugar,
                proteinGrams: protein,
                saltGrams: salt,
                fibreGrams: fibre
            ),
            source: "CoFID 2021 · \(code) · 每 100 g；Tr 按 0 计，盐=钠×2.5"
        )
    }
}
