import Foundation

/// A reviewed public catalog. It projects onto existing FoodItem fields without changing storage.
public struct FoodCatalog: Codable, Sendable, Equatable {
    public let version: String
    public let ruleVersion: String
    public let source: FoodCatalogSource
    public let entries: [FoodCatalogEntry]

    private enum CodingKeys: String, CodingKey { case version, ruleVersion, source, entries }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        version = try values.decode(String.self, forKey: .version)
        ruleVersion = try values.decode(String.self, forKey: .ruleVersion)
        source = try values.decode(FoodCatalogSource.self, forKey: .source)
        entries = try values.decode([FoodCatalogEntry].self, forKey: .entries)
        try validate()
    }

    private static let bundledResult: Result<FoodCatalog, any Error> = Result {
        guard let url = Bundle.module.url(forResource: "food-catalog-v1", withExtension: "json") else {
            throw FoodCatalogError.missingResource
        }
        return try JSONDecoder().decode(FoodCatalog.self, from: Data(contentsOf: url))
    }

    public static func bundled() throws -> FoodCatalog {
        try bundledResult.get()
    }

    /// Match the complete value, not merely its UUID: restored or modified local foods stay local.
    public func metadata(for food: FoodItem) -> FoodCatalogEntry? {
        entries.first { $0.food == food }
    }

    public func searchDocuments(for foods: [FoodItem]) -> [FoodSearchDocument] {
        let indexed = Dictionary(uniqueKeysWithValues: entries.enumerated().map { ($0.element.food.id, $0) })
        return foods.map { food in
            if let match = indexed[food.id], match.element.food == food {
                let entry = match.element
                return FoodSearchDocument(
                    id: food.id, name: food.name, aliases: entry.aliases, englishName: entry.originalName,
                    pinyinInitials: entry.pinyinInitials, catalogOrder: match.offset
                )
            }
            return FoodSearchDocument(id: food.id, name: food.name, catalogOrder: .max)
        }
    }

    private func validate() throws {
        guard version == "cofid-2021-zh-v1", ruleVersion == "food-import-cofid-2021-v1" else {
            throw FoodCatalogError.unsupportedVersion
        }
        guard source.id == "cofid", source.datasetVersion == "2021",
              source.sha256.count == 64, source.sha256.allSatisfy(\.isHexDigit),
              !source.attribution.isEmpty, !source.sourceFileName.isEmpty,
              [source.url, source.guideURL, source.licenseURL].allSatisfy({ URL(string: $0)?.scheme == "https" }) else {
            throw FoodCatalogError.invalidSource
        }
        guard entries.count >= 300 else { throw FoodCatalogError.insufficientFoods }
        guard Set(entries.map(\.food.id)).count == entries.count else { throw FoodCatalogError.duplicateIdentifier }
        guard Set(entries.map(\.code)).count == entries.count else { throw FoodCatalogError.duplicateSourceCode }
        let legacyCodes: Set<String> = [
            "11-862", "13-517", "12-937", "13-318", "13-161", "13-570",
            "18-006", "18-020", "18-323", "18-319", "17-041", "17-721"
        ]
        guard Set(entries.filter(\.legacySeed).map(\.code)) == legacyCodes else {
            throw FoodCatalogError.invalidRecord(code: "legacy")
        }
        for entry in entries {
            // CoFID includes both three- and four-digit item suffixes (e.g. 11-1045).
            let codeParts = entry.code.split(separator: "-", omittingEmptySubsequences: false)
            let validCode = codeParts.count == 2 && codeParts[0].count == 2
                && (3...4).contains(codeParts[1].count)
                && codeParts.allSatisfy { $0.allSatisfy { $0.isASCII && $0.isNumber } }
            guard entry.basis == "per100gFood", entry.food.unit == "g", entry.sourceRow > 2,
                  !entry.originalName.isEmpty, !entry.foodState.isEmpty,
                  validCode, entry.food.source.contains("CoFID 2021"),
                  entry.food.source.contains(entry.code),
                  entry.pinyinInitials.allSatisfy({ !$0.isEmpty && $0.allSatisfy { $0.isASCII && $0.isLetter } }) else {
                throw FoodCatalogError.invalidRecord(code: entry.code)
            }
            if entry.legacySeed {
                let digits = entry.code.replacingOccurrences(of: "-", with: "")
                guard entry.food.id.uuidString.lowercased() == "20000000-0000-4000-8000-0000000" + digits else {
                    throw FoodCatalogError.invalidRecord(code: entry.code)
                }
                // Exact legacy fields are separately checked against SeedFoodCatalog in app tests.
                // Their original unknown fibre is not filled using a newer interpretation.
                continue
            }
            let n = entry.food.nutrientsPer100Units
            let expected: [(String, Double)] = [
                ("KCALS", n.energyKcal), ("PROT", n.proteinGrams), ("FAT", n.fatGrams),
                ("SATFOD", n.saturatedFatGrams), ("CHO", n.carbohydrateGrams), ("TOTSUG", n.sugarGrams)
            ]
            for (field, value) in expected {
                guard let reported = Self.reported(entry.rawNutrients[field]), abs(reported - value) < 0.00000001 else {
                    throw FoodCatalogError.inconsistentNutrient(code: entry.code, field: field)
                }
            }
            guard let sodium = Self.reported(entry.rawNutrients["NA"]), abs(sodium / 1000 * 2.5 - n.saltGrams) < 0.00000001 else {
                throw FoodCatalogError.inconsistentNutrient(code: entry.code, field: "NA")
            }
            guard let rawFibre = entry.rawNutrients["AOACFIB"] else {
                throw FoodCatalogError.inconsistentNutrient(code: entry.code, field: "AOACFIB")
            }
            let fibre = Self.reported(rawFibre)
            guard fibre != nil || ["", "N"].contains(rawFibre.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                throw FoodCatalogError.inconsistentNutrient(code: entry.code, field: "AOACFIB")
            }
            guard fibre == n.fibreGrams else {
                throw FoodCatalogError.inconsistentNutrient(code: entry.code, field: "AOACFIB")
            }
        }
    }

    private static func reported(_ raw: String?) -> Double? {
        guard let raw else { return nil }
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value == "Tr" { return 0 }
        guard let number = Double(value), number.isFinite, number >= 0 else { return nil }
        return number
    }
}
