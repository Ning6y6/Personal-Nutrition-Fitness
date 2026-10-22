import Foundation

/// Local, versioned identity for manually entered food. This is not an authority claim.
/// App adapters additionally reject IDs reserved for bundled and legacy food catalogs.
public struct PersonalFoodSource: Sendable, Equatable {
    public static let prefix = "evenfare.personal-food:"

    public let version: Int
    public let foodID: UUID
    public let note: String

    private struct Payload: Codable {
        let version: Int
        let foodID: UUID
        let note: String
    }

    /// Keeps user notes separate from the machine-readable identity, including Unicode and newlines.
    public static func encode(foodID: UUID, note: String) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(Payload(version: 1, foodID: foodID, note: note))
        return prefix + data.base64EncodedString()
    }

    /// Fail closed for unknown versions, a different food ID, or noncanonical/altered envelopes.
    /// Re-encoding also rejects extra keys, duplicate keys, whitespace, and alternate Base64 forms.
    public static func decode(source: String, foodID: UUID) -> PersonalFoodSource? {
        guard source.hasPrefix(prefix),
              let data = Data(base64Encoded: String(source.dropFirst(prefix.count))),
              let payload = try? JSONDecoder().decode(Payload.self, from: data),
              payload.version == 1,
              payload.foodID == foodID,
              let canonical = try? encode(foodID: foodID, note: payload.note),
              canonical == source else { return nil }
        return PersonalFoodSource(version: payload.version, foodID: payload.foodID, note: payload.note)
    }
}
