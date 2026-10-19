import Foundation
import Testing
@testable import FoodDecisionCore

struct FoodCatalogTests {
    @Test func publicCatalogHasRealUniqueSourcesAndFrozenLegacyIDs() throws {
        let catalog = try FoodCatalog.bundled()
        #expect(catalog.entries.count >= 300)
        #expect(Set(catalog.entries.map(\.food.id)).count == catalog.entries.count)
        #expect(Set(catalog.entries.map(\.code)).count == catalog.entries.count)
        #expect(catalog.entries.filter(\.legacySeed).count == 12)
        #expect(catalog.entries.allSatisfy { $0.basis == "per100gFood" && $0.food.unit == "g" })
        #expect(catalog.entries.allSatisfy { !$0.originalName.isEmpty && !$0.foodState.isEmpty })
        #expect(catalog.source.sha256 == "436e9445ef2adb2a75f3d7edd51302de3adad25385f9795fc94ba58bd030e97d")
        #expect(!catalog.entries.contains { $0.code == "13-669" })
        let documents = catalog.searchDocuments(for: catalog.entries.map(\.food))
        for (query, code) in [("ablayshfm", "11-878"), ("jlytg", "14-159")] {
            let entry = try #require(catalog.entries.first { $0.code == code })
            #expect(FoodSearchPolicy.search(query, in: documents).map(\.id) == [entry.food.id])
        }
    }

    @Test func modifiedLocalFoodNeverInheritsSourceEvidenceOrAliases() throws {
        let catalog = try FoodCatalog.bundled()
        let entry = try #require(catalog.entries.first { !$0.aliases.isEmpty })
        let changed = try FoodItem(id: entry.food.id, name: "本地自改食品", category: entry.food.category,
                                   nutrientsPer100Units: entry.food.nutrientsPer100Units, source: entry.food.source)
        #expect(catalog.metadata(for: entry.food) == entry)
        #expect(catalog.metadata(for: changed) == nil)
        let docs = catalog.searchDocuments(for: [changed])
        #expect(docs.count == 1)
        #expect(docs.first?.aliases.isEmpty == true)
        #expect(docs.first?.englishName.isEmpty == true)
        #expect(FoodSearchPolicy.search("本地自改", in: docs).map(\.id) == [changed.id])
    }

    @Test func localSameNameOrderingSurvivesFetchAndRestoreOrderChanges() throws {
        let catalog = try FoodCatalog.bundled()
        let values = try #require(catalog.entries.first?.food.nutrientsPer100Units)
        let lowID = try #require(UUID(uuidString: "10000000-0000-4000-8000-000000000001"))
        let highID = try #require(UUID(uuidString: "10000000-0000-4000-8000-000000000002"))
        let one = try FoodItem(id: lowID, name: "同名本地食物", category: .mixedMeal,
                               nutrientsPer100Units: values, source: "本地资料")
        let two = try FoodItem(id: highID, name: one.name, category: one.category,
                               nutrientsPer100Units: values, source: one.source)
        for query in ["", "同名本地食物"] {
            let forward = FoodSearchPolicy.search(query, in: catalog.searchDocuments(for: [one, two]))
            let reversed = FoodSearchPolicy.search(query, in: catalog.searchDocuments(for: [two, one]))
            #expect(forward.map(\.id) == [lowID, highID])
            #expect(reversed.map(\.id) == forward.map(\.id))
        }
    }

    @Test func catalogRoundTripRetainsRawTraceAndUnknownEvidence() throws {
        let catalog = try FoodCatalog.bundled()
        let decoded = try JSONDecoder().decode(FoodCatalog.self, from: JSONEncoder().encode(catalog))
        #expect(decoded == catalog)
        #expect(catalog.entries.contains { $0.rawNutrients.values.contains("Tr") })
        #expect(catalog.entries.contains { $0.rawNutrients.values.contains("") || $0.rawNutrients.values.contains("N") })
    }

    @Test(arguments: ["N", "", "NaN", "-1", "unknown"])
    func invalidRequiredSourceValueCannotBecomeZero(raw: String) throws {
        let catalog = try FoodCatalog.bundled()
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(catalog)) as? [String: Any])
        var entries = try #require(json["entries"] as? [[String: Any]])
        let index = try #require(entries.firstIndex { ($0["legacySeed"] as? Bool) == false })
        var evidence = try #require(entries[index]["rawNutrients"] as? [String: String])
        evidence["KCALS"] = raw
        entries[index]["rawNutrients"] = evidence
        json["entries"] = entries
        let data = try JSONSerialization.data(withJSONObject: json)
        let code = try #require(entries[index]["code"] as? String)
        #expect(throws: FoodCatalogError.inconsistentNutrient(code: code, field: "KCALS")) {
            try JSONDecoder().decode(FoodCatalog.self, from: data)
        }
    }

    @Test func duplicatesAndVolumeBasisAreRejectedBeforeAnyImport() throws {
        let catalog = try FoodCatalog.bundled()
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(catalog)) as? [String: Any])
        var entries = try #require(json["entries"] as? [[String: Any]])
        entries.append(try #require(entries.first))
        json["entries"] = entries
        let duplicate = try JSONSerialization.data(withJSONObject: json)
        #expect(throws: FoodCatalogError.duplicateIdentifier) {
            try JSONDecoder().decode(FoodCatalog.self, from: duplicate)
        }
        entries.removeLast()
        let index = try #require(entries.firstIndex { ($0["legacySeed"] as? Bool) == false })
        entries[index]["basis"] = "per100ml"
        json["entries"] = entries
        let volume = try JSONSerialization.data(withJSONObject: json)
        let code = try #require(entries[index]["code"] as? String)
        #expect(throws: FoodCatalogError.invalidRecord(code: code)) {
            try JSONDecoder().decode(FoodCatalog.self, from: volume)
        }
    }
}
