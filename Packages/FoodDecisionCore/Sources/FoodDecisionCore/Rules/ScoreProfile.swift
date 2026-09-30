import Foundation

public enum NutrientMetric: String, Codable, CaseIterable, Sendable {
    case proteinDensity = "protein_density"
    case fibre
    case saturatedFat = "saturated_fat"
    case sugar
    case salt
    case energyDensity = "energy_density"
    case saturatedFatRatio = "saturated_fat_ratio"
}

public struct ScoreProfile: Codable, Sendable, Equatable {
    public var id: String
    public var version: Int
    public var mandatoryFields: [String]
    public var optionalFields: [String]
    public var categoryWeights: [String: [String: Double]]

    public init(
        id: String,
        version: Int,
        mandatoryFields: [String],
        optionalFields: [String],
        categoryWeights: [String: [String: Double]]
    ) {
        self.id = id
        self.version = version
        self.mandatoryFields = mandatoryFields
        self.optionalFields = optionalFields
        self.categoryWeights = categoryWeights
    }

    public static func bundled() throws -> ScoreProfile {
        guard let url = Bundle.module.url(forResource: "score-profile-v1", withExtension: "json") else {
            throw ScoreError.missingProfile
        }
        return try JSONDecoder().decode(ScoreProfile.self, from: Data(contentsOf: url))
    }
}

public enum ScoreError: Error, Equatable {
    case missingProfile
    case missingCategory(FoodCategory)
    case noScorableComponents
}

public enum NutritionScoreEngine {
    public static func score(
        componentScores: [NutrientMetric: Double],
        category: FoodCategory,
        profile: ScoreProfile
    ) throws -> Int {
        guard let weights = profile.categoryWeights[category.rawValue] else {
            throw ScoreError.missingCategory(category)
        }

        var weightedTotal = 0.0
        var validWeight = 0.0

        for (metric, value) in componentScores {
            guard let weight = weights[metric.rawValue], weight > 0 else { continue }
            weightedTotal += min(max(value, 0), 100) * weight
            validWeight += weight
        }

        guard validWeight > 0 else { throw ScoreError.noScorableComponents }
        return Int((weightedTotal / validWeight).rounded()).clamped(to: 0 ... 100)
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

