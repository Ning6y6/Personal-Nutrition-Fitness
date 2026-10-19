import Foundation

/// Public dataset provenance; this is bundled catalog metadata, not a private-store schema.
public struct FoodCatalogSource: Codable, Sendable, Equatable {
    public let id: String
    public let title: String
    public let datasetVersion: String
    public let url: String
    public let guideURL: String
    public let licenseName: String
    public let licenseURL: String
    public let attribution: String
    public let sourceFileName: String
    public let sha256: String
    public let retrievedOn: String
}
