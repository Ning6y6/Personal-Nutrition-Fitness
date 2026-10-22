import FoodDecisionCore
import Foundation

/// Render the local source protocol as user text, without granting edit rights.
/// PersonalFoodIdentity remains the authority for editable personal cards.
enum FoodSourcePresentation {
    static func text(source: String, foodID: UUID) -> String {
        guard source.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix(PersonalFoodSource.prefix) else { return source }
        guard let personal = PersonalFoodSource.decode(source: source, foodID: foodID) else {
            return "本地来源资料暂无法识别"
        }
        let note = personal.note.trimmingCharacters(in: .whitespacesAndNewlines)
        return note.isEmpty ? "用户手动录入" : "用户手动录入 · \(note)"
    }

    static func shortText(source: String, foodID: UUID) -> String {
        text(source: source, foodID: foodID).components(separatedBy: " · ").first ?? "本地记录"
    }
}
