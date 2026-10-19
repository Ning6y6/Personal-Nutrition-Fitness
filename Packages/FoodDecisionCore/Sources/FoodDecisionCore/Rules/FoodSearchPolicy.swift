import Foundation

public enum FoodSearchPolicy {
    public static let version = "food-search-v1"

    /// Fixed locale and compatibility normalization make ranking independent of phone region.
    public static func normalized(_ text: String) -> String {
        let locale = Locale(identifier: "en_US_POSIX")
        return text.precomposedStringWithCompatibilityMapping
            .folding(options: [.caseInsensitive, .widthInsensitive], locale: locale)
            .lowercased(with: locale)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    public static func search(_ query: String, in documents: [FoodSearchDocument]) -> [FoodSearchDocument] {
        let query = normalized(query)
        let tokens = query.split(separator: " ").map(String.init)
        return documents.compactMap { document -> (FoodSearchDocument, Int)? in
            if query.isEmpty { return (document, 0) }
            let textKeys = ([document.name, document.englishName] + document.aliases)
                .map(normalized).filter { !$0.isEmpty }
            if textKeys.contains(query) { return (document, 0) }
            if textKeys.contains(where: { $0.hasPrefix(query) }) { return (document, 1) }
            if tokens.allSatisfy({ token in textKeys.contains(where: { $0.contains(token) }) }) {
                return (document, 2)
            }
            let initials = document.pinyinInitials.map(normalized)
            if tokens.allSatisfy({ token in
                textKeys.contains(where: { $0.contains(token) }) || initials.contains(where: { $0.contains(token) })
            }) { return (document, 3) }
            return nil
        }.sorted { lhs, rhs in
            if lhs.1 != rhs.1 { return lhs.1 < rhs.1 }
            if lhs.0.catalogOrder != rhs.0.catalogOrder { return lhs.0.catalogOrder < rhs.0.catalogOrder }
            return lhs.0.id.uuidString < rhs.0.id.uuidString
        }.map(\.0)
    }
}
