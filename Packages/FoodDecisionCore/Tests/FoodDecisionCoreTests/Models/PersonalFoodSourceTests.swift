import Foundation
import Testing
@testable import FoodDecisionCore

struct PersonalFoodSourceTests {
    private let foodID = UUID(uuidString: "60000000-0000-4000-8000-000000000013")!

    @Test("The versioned identity is deterministic and retains arbitrary human notes", arguments: ["", "包装每 100 g", "CoFID 2021", "引号\"、反斜线\\、换行\n与 emoji 🍯", "https://example.invalid/a/b?x=1"])
    func canonicalRoundTrip(note: String) throws {
        let source = try PersonalFoodSource.encode(foodID: foodID, note: note)
        #expect(source.hasPrefix("evenfare.personal-food:"))
        #expect(source == (try PersonalFoodSource.encode(foodID: foodID, note: note)))
        let decoded = try #require(PersonalFoodSource.decode(source: source, foodID: foodID))
        #expect(decoded.version == 1)
        #expect(decoded.foodID == foodID)
        #expect(decoded.note == note)
        let data = try #require(Data(base64Encoded: String(source.dropFirst(PersonalFoodSource.prefix.count))))
        let payload = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(Set(payload.keys) == Set(["version", "foodID", "note"]))
    }

    @Test("Markers are bound to the exact food identity")
    func anotherFoodCannotReuseSource() throws {
        let source = try PersonalFoodSource.encode(foodID: foodID, note: "")
        #expect(PersonalFoodSource.decode(source: source, foodID: UUID()) == nil)
    }

    @Test("Unmarked, corrupt, wrongly cased or truncated envelopes remain unrecognized", arguments: ["CoFID 2021", "用户手动录入", "", "evenfare.personal-food:", "evenfare.personal-food:%%%%", "evenfare.personal-food:e30=", "Evenfare.personal-food:e30=", "evenfare.personal-food:e30"])
    func rejectsInvalidSources(source: String) {
        #expect(PersonalFoodSource.decode(source: source, foodID: foodID) == nil)
    }

    @Test("Unknown or noncanonical payloads never become editable personal cards")
    func rejectsMalformedPayloads() throws {
        let id = foodID.uuidString
        let payloads = [
            #"{"foodID":"\#(id)","note":"","version":2}"#,
            #"{"foodID":"\#(id)","note":"","version":"1"}"#,
            #"{"foodID":"\#(id)","version":1}"#,
            #"{"foodID":"\#(id)","note":null,"version":1}"#,
            #"{"foodID":"\#(id)","note":"","unknown":true,"version":1}"#,
            #"{"foodID":"\#(id)","note":"","note":"","version":1}"#,
            #"{"version":1,"foodID":"\#(id)","note":""}"#,
            #"{ "foodID":"\#(id)","note":"","version":1}"#,
            #"{"foodID":"not-a-uuid","note":"","version":1}"#
        ]
        for json in payloads {
            let source = PersonalFoodSource.prefix + Data(json.utf8).base64EncodedString()
            #expect(PersonalFoodSource.decode(source: source, foodID: foodID) == nil, "Rejected payload: \(json)")
        }
        let source = try PersonalFoodSource.encode(foodID: foodID, note: "")
        #expect(PersonalFoodSource.decode(source: source + "\n", foodID: foodID) == nil)
    }

    @Test("The encoded source survives FoodItem JSON backup-style serialization")
    func sourceSurvivesSerialization() throws {
        let source = try PersonalFoodSource.encode(foodID: foodID, note: "包装录入\n盐 0.5 g")
        let nutrients = try NutrientValues(energyKcal: 400, fatGrams: 6, saturatedFatGrams: 2, carbohydrateGrams: 10, sugarGrams: 3, proteinGrams: 80, saltGrams: 0.5)
        let food = try FoodItem(id: foodID, name: "验收测试蛋白粉", category: .proteinMain, nutrientsPer100Units: nutrients, source: source)
        let restored = try JSONDecoder().decode(FoodItem.self, from: JSONEncoder().encode(food))
        #expect(restored == food)
        #expect(restored.nutrientsPer100Units.fibreGrams == nil)
        #expect(PersonalFoodSource.decode(source: restored.source, foodID: restored.id)?.note == "包装录入\n盐 0.5 g")
    }
}
