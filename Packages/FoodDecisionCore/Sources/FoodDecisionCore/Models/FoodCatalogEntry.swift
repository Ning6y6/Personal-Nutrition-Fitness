import Foundation

public struct FoodCatalogEntry: Codable, Sendable, Equatable {
    public let food: FoodItem
    public let code: String
    public let originalName: String
    public let aliases: [String]
    public let pinyinInitials: [String]
    public let foodState: String
    public let basis: String
    public let sourceRow: Int
    /// Exact source text, including Tr, N and blank; never infer zero from absence.
    public let rawNutrients: [String: String]
    public let legacySeed: Bool
}
