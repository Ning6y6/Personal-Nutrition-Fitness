import Foundation

/// A value projection: SwiftData models never cross the search boundary.
public struct FoodSearchDocument: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let name: String
    public let aliases: [String]
    public let englishName: String
    public let pinyinInitials: [String]
    public let catalogOrder: Int

    public init(
        id: UUID, name: String, aliases: [String] = [], englishName: String = "",
        pinyinInitials: [String] = [], catalogOrder: Int = .max
    ) {
        self.id = id
        self.name = name
        self.aliases = aliases
        self.englishName = englishName
        self.pinyinInitials = pinyinInitials
        self.catalogOrder = catalogOrder
    }
}
