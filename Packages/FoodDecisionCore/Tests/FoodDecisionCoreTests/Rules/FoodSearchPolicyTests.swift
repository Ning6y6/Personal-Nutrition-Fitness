import Foundation
import Testing
@testable import FoodDecisionCore

struct FoodSearchPolicyTests {
    private func document(
        _ suffix: Int, _ name: String, aliases: [String] = [], english: String = "",
        initials: [String] = [], order: Int = 0
    ) throws -> FoodSearchDocument {
        let id = try #require(UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", suffix)))
        return FoodSearchDocument(id: id, name: name, aliases: aliases, englishName: english,
                                  pinyinInitials: initials, catalogOrder: order)
    }

    @Test(arguments: ["番茄", "西红柿", "ＴＯＭＡＴＯ", "fq"])
    func reviewedKeysFindSameFood(query: String) throws {
        let tomato = try document(1, "西红柿（生）", aliases: ["番茄", "西红柿"], english: "Tomato", initials: ["fq", "xhs"])
        let rice = try document(2, "米饭（熟）")
        #expect(FoodSearchPolicy.search(query, in: [rice, tomato]).map(\.id) == [tomato.id])
    }

    @Test func orderingPrioritizesTextBeforePinyinAndIsDeterministic() throws {
        let exact = try document(1, "其他名称", aliases: ["鸡"], order: 10)
        let prefix = try document(2, "鸡胸肉（生）", order: 5)
        let contains = try document(3, "去皮鸡腿肉（生）", order: 0)
        let pinyin = try document(4, "玉米（生）", initials: ["ji"], order: -1)
        #expect(FoodSearchPolicy.search("鸡", in: [contains, prefix, exact]).map(\.id) == [exact.id, prefix.id, contains.id])
        let literal = try document(5, "jxr 食品")
        let chicken = try document(6, "鸡胸肉（生）", initials: ["jxr"], order: -2)
        #expect(FoodSearchPolicy.search("jxr", in: [chicken, literal]).map(\.id) == [literal.id, chicken.id])
        #expect(FoodSearchPolicy.search("ji", in: [pinyin]).map(\.id) == [pinyin.id])
    }

    @Test func sameNamesStaySeparateWithStableIDTieBreak() throws {
        let one = try document(1, "米饭")
        let two = try document(2, "米饭")
        #expect(FoodSearchPolicy.search("米饭", in: [two, one]).map(\.id) == [one.id, two.id])
        #expect(FoodSearchPolicy.search("", in: [two, one]).map(\.id) == [one.id, two.id])
    }

    @Test func tokensMustAllMatchAndRawCookedStatesRemainDistinct() throws {
        let raw = try document(1, "长粒大米（生）", english: "Rice raw")
        let cooked = try document(2, "长粒米饭（熟）", english: "Rice cooked")
        #expect(FoodSearchPolicy.search("rice 生", in: [raw, cooked]).map(\.id) == [raw.id])
        #expect(FoodSearchPolicy.search("rice 熟", in: [raw, cooked]).map(\.id) == [cooked.id])
        #expect(FoodSearchPolicy.search("rice 羊肉", in: [raw, cooked]).isEmpty)
        #expect(FoodSearchPolicy.search(".*", in: [raw, cooked]).isEmpty)
    }

    @Test func normalizationHasFixedCaseWidthAndWhitespaceRules() {
        #expect(FoodSearchPolicy.normalized("  ＲＩＣＥ\t锅\n") == "rice 锅")
        #expect(FoodSearchPolicy.normalized("I") == "i")
        #expect(FoodSearchPolicy.normalized("\u{3000} 鸡  胸肉 ") == "鸡 胸肉")
    }
}
