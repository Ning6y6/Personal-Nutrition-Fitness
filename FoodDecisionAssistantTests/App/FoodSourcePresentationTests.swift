import FoodDecisionCore
import Foundation
import Testing

@testable import FoodDecisionAssistant

struct FoodSourcePresentationTests {
    @Test("Personal source notes are readable without exposing the stored protocol")
    func readablePersonalNote() throws {
        let id = UUID()
        let source = try PersonalFoodSource.encode(foodID: id, note: "包装每 100 g\nCoFID 字样仅为用户备注")
        #expect(FoodSourcePresentation.text(source: source, foodID: id) == "用户手动录入 · 包装每 100 g\nCoFID 字样仅为用户备注")
        #expect(FoodSourcePresentation.shortText(source: source, foodID: id) == "用户手动录入")
    }

    @Test("An empty optional note still has an explicit manual source", arguments: ["", " \n "])
    func emptyNote(note: String) throws {
        let id = UUID()
        let source = try PersonalFoodSource.encode(foodID: id, note: note)
        #expect(FoodSourcePresentation.text(source: source, foodID: id) == "用户手动录入")
    }

    @Test("Damaged or ID-mismatched source protocols never leak into the interface")
    func unreadableProtocol() throws {
        let id = UUID()
        let mismatch = try PersonalFoodSource.encode(foodID: UUID(), note: "测试")
        for source in [PersonalFoodSource.prefix + "broken", mismatch, " \n" + mismatch] {
            #expect(FoodSourcePresentation.text(source: source, foodID: id) == "本地来源资料暂无法识别")
        }
    }

    @Test("Existing source descriptions keep their text and short caption")
    func existingSource() {
        let id = UUID()
        #expect(FoodSourcePresentation.text(source: "CoFID 2021 · 原始来源", foodID: id) == "CoFID 2021 · 原始来源")
        #expect(FoodSourcePresentation.shortText(source: "CoFID 2021 · 原始来源", foodID: id) == "CoFID 2021")
    }
}
