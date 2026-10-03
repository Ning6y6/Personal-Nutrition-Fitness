import Foundation

public enum MealCoverageStatus: String, Codable, Sendable, Equatable {
    case complete
    case partial
    case incomplete
}

public enum EstimateEvidenceGrade: String, Codable, Sendable, Equatable {
    case a
    case b
    case c
    case d
}

public enum CookingMethod: String, Codable, Sendable, Equatable {
    case unknown
    case steamed
    case boiled
    case grilled
    case roasted
    case stirFried
    case deepFried
    case baked
    case raw
}

public enum EstimateConfirmationStatus: String, Codable, Sendable, Equatable {
    case draft
    case confirmed
    case failed
}

public enum PortionEstimateRangeError: Error, Codable, Sendable, Equatable {
    case negativeWeight
    case invalidOrder
    case invalidSharingRatio
    case invalidConfidence
}

public struct PortionEstimateRange: Codable, Sendable, Equatable {
    public var lowGrams: Double
    public var midpointGrams: Double
    public var highGrams: Double

    public init(lowGrams: Double, midpointGrams: Double, highGrams: Double) throws {
        guard lowGrams >= 0, midpointGrams >= 0, highGrams >= 0 else {
            throw PortionEstimateRangeError.negativeWeight
        }
        guard lowGrams <= midpointGrams, midpointGrams <= highGrams else {
            throw PortionEstimateRangeError.invalidOrder
        }
        self.lowGrams = lowGrams
        self.midpointGrams = midpointGrams
        self.highGrams = highGrams
    }

    public func scaled(by sharingRatio: Double) throws -> PortionEstimateRange {
        guard (0...1).contains(sharingRatio), sharingRatio > 0 else {
            throw PortionEstimateRangeError.invalidSharingRatio
        }
        return try PortionEstimateRange(
            lowGrams: lowGrams * sharingRatio,
            midpointGrams: midpointGrams * sharingRatio,
            highGrams: highGrams * sharingRatio
        )
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            lowGrams: container.decode(Double.self, forKey: .lowGrams),
            midpointGrams: container.decode(Double.self, forKey: .midpointGrams),
            highGrams: container.decode(Double.self, forKey: .highGrams)
        )
    }
}

public struct MealPhotoComponent: Codable, Identifiable, Sendable, Equatable {
    public var id: UUID
    public var foodItemID: UUID?
    public var templateID: String?
    public var freeTextName: String
    public var cookingMethod: CookingMethod
    public var portionRange: PortionEstimateRange
    public var confidence: Double
    public var isHiddenOilOrSauce: Bool
    public var userCorrectedWeightGrams: Double?

    public init(id: UUID = UUID(), foodItemID: UUID? = nil, templateID: String? = nil, freeTextName: String, cookingMethod: CookingMethod, portionRange: PortionEstimateRange, confidence: Double, isHiddenOilOrSauce: Bool = false, userCorrectedWeightGrams: Double? = nil) throws {
        guard (0...1).contains(confidence) else { throw PortionEstimateRangeError.invalidConfidence }
        guard userCorrectedWeightGrams.map({ $0 >= 0 }) ?? true else { throw PortionEstimateRangeError.negativeWeight }
        self.id = id
        self.foodItemID = foodItemID
        self.templateID = templateID
        self.freeTextName = freeTextName
        self.cookingMethod = cookingMethod
        self.portionRange = portionRange
        self.confidence = confidence
        self.isHiddenOilOrSauce = isHiddenOilOrSauce
        self.userCorrectedWeightGrams = userCorrectedWeightGrams
    }

    public func correctedOrEstimatedRange() throws -> PortionEstimateRange {
        guard let userCorrectedWeightGrams else { return portionRange }
        return try PortionEstimateRange(lowGrams: userCorrectedWeightGrams, midpointGrams: userCorrectedWeightGrams, highGrams: userCorrectedWeightGrams)
    }

    public func consumedPortionRange(sharingRatio: Double) throws -> PortionEstimateRange {
        try correctedOrEstimatedRange().scaled(by: sharingRatio)
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            id: container.decode(UUID.self, forKey: .id),
            foodItemID: container.decodeIfPresent(UUID.self, forKey: .foodItemID),
            templateID: container.decodeIfPresent(String.self, forKey: .templateID),
            freeTextName: container.decode(String.self, forKey: .freeTextName),
            cookingMethod: container.decode(CookingMethod.self, forKey: .cookingMethod),
            portionRange: container.decode(PortionEstimateRange.self, forKey: .portionRange),
            confidence: container.decode(Double.self, forKey: .confidence),
            isHiddenOilOrSauce: container.decode(Bool.self, forKey: .isHiddenOilOrSauce),
            userCorrectedWeightGrams: container.decodeIfPresent(Double.self, forKey: .userCorrectedWeightGrams)
        )
    }
}

public struct PortionCalibration: Codable, Identifiable, Sendable, Equatable {
    public var id: UUID
    public var createdAt: Date
    public var photoEstimateID: UUID
    public var componentID: UUID?
    public var estimatedWeightGrams: Double
    public var actualWeightGrams: Double

    public init(id: UUID = UUID(), createdAt: Date = .now, photoEstimateID: UUID, componentID: UUID? = nil, estimatedWeightGrams: Double, actualWeightGrams: Double) throws {
        guard estimatedWeightGrams >= 0, actualWeightGrams >= 0 else { throw PortionEstimateRangeError.negativeWeight }
        self.id = id
        self.createdAt = createdAt
        self.photoEstimateID = photoEstimateID
        self.componentID = componentID
        self.estimatedWeightGrams = estimatedWeightGrams
        self.actualWeightGrams = actualWeightGrams
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(id: container.decode(UUID.self, forKey: .id), createdAt: container.decode(Date.self, forKey: .createdAt), photoEstimateID: container.decode(UUID.self, forKey: .photoEstimateID), componentID: container.decodeIfPresent(UUID.self, forKey: .componentID), estimatedWeightGrams: container.decode(Double.self, forKey: .estimatedWeightGrams), actualWeightGrams: container.decode(Double.self, forKey: .actualWeightGrams))
    }
}

public struct MealPhotoEstimate: Codable, Identifiable, Sendable, Equatable {
    public var id: UUID
    public var createdAt: Date
    public var mealTitle: String
    public var imageReference: String
    public var providerName: String
    public var modelVersion: String
    public var outputSchemaVersion: String
    public var confirmationStatus: EstimateConfirmationStatus
    public var consumedShareRatio: Double
    public var components: [MealPhotoComponent]
    public var calibrations: [PortionCalibration]

    public init(id: UUID = UUID(), createdAt: Date = .now, mealTitle: String, imageReference: String, providerName: String, modelVersion: String, outputSchemaVersion: String, confirmationStatus: EstimateConfirmationStatus, consumedShareRatio: Double, components: [MealPhotoComponent], calibrations: [PortionCalibration] = []) throws {
        guard (0...1).contains(consumedShareRatio), consumedShareRatio > 0 else { throw PortionEstimateRangeError.invalidSharingRatio }
        self.id = id
        self.createdAt = createdAt
        self.mealTitle = mealTitle
        self.imageReference = imageReference
        self.providerName = providerName
        self.modelVersion = modelVersion
        self.outputSchemaVersion = outputSchemaVersion
        self.confirmationStatus = confirmationStatus
        self.consumedShareRatio = consumedShareRatio
        self.components = components
        self.calibrations = calibrations
    }

    public func consumedComponents() throws -> [MealPhotoComponent] {
        try components.map { component in
            var consumedComponent = component
            consumedComponent.portionRange = try component.consumedPortionRange(sharingRatio: consumedShareRatio)
            if let correctedWeight = component.userCorrectedWeightGrams {
                consumedComponent.userCorrectedWeightGrams = correctedWeight * consumedShareRatio
            }
            return consumedComponent
        }
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(id: container.decode(UUID.self, forKey: .id), createdAt: container.decode(Date.self, forKey: .createdAt), mealTitle: container.decode(String.self, forKey: .mealTitle), imageReference: container.decode(String.self, forKey: .imageReference), providerName: container.decode(String.self, forKey: .providerName), modelVersion: container.decode(String.self, forKey: .modelVersion), outputSchemaVersion: container.decode(String.self, forKey: .outputSchemaVersion), confirmationStatus: container.decode(EstimateConfirmationStatus.self, forKey: .confirmationStatus), consumedShareRatio: container.decode(Double.self, forKey: .consumedShareRatio), components: container.decode([MealPhotoComponent].self, forKey: .components), calibrations: container.decode([PortionCalibration].self, forKey: .calibrations))
    }
}

public struct MealVisionRequest: Codable, Identifiable, Sendable, Equatable {
    public var id: UUID
    public var createdAt: Date
    public var mealTitle: String
    public var imageReference: String
    public var outputSchemaVersion: String

    public init(id: UUID = UUID(), createdAt: Date = .now, mealTitle: String, imageReference: String, outputSchemaVersion: String = "meal-vision-v1") {
        self.id = id
        self.createdAt = createdAt
        self.mealTitle = mealTitle
        self.imageReference = imageReference
        self.outputSchemaVersion = outputSchemaVersion
    }
}

public struct MealVisionDraft: Codable, Identifiable, Sendable, Equatable {
    public var id: UUID
    public var requestID: UUID
    public var createdAt: Date
    public var mealTitle: String
    public var providerName: String
    public var modelVersion: String
    public var outputSchemaVersion: String
    public var confirmationStatus: EstimateConfirmationStatus
    public var consumedShareRatio: Double
    public var components: [MealPhotoComponent]

    public init(id: UUID = UUID(), requestID: UUID, createdAt: Date = .now, mealTitle: String, providerName: String, modelVersion: String, outputSchemaVersion: String, confirmationStatus: EstimateConfirmationStatus = .draft, consumedShareRatio: Double, components: [MealPhotoComponent]) throws {
        guard (0...1).contains(consumedShareRatio), consumedShareRatio > 0 else { throw PortionEstimateRangeError.invalidSharingRatio }
        self.id = id
        self.requestID = requestID
        self.createdAt = createdAt
        self.mealTitle = mealTitle
        self.providerName = providerName
        self.modelVersion = modelVersion
        self.outputSchemaVersion = outputSchemaVersion
        self.confirmationStatus = confirmationStatus
        self.consumedShareRatio = consumedShareRatio
        self.components = components
    }

    public func makePhotoEstimate(imageReference: String, calibrations: [PortionCalibration] = []) throws -> MealPhotoEstimate {
        try MealPhotoEstimate(id: id, createdAt: createdAt, mealTitle: mealTitle, imageReference: imageReference, providerName: providerName, modelVersion: modelVersion, outputSchemaVersion: outputSchemaVersion, confirmationStatus: confirmationStatus, consumedShareRatio: consumedShareRatio, components: components, calibrations: calibrations)
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(id: container.decode(UUID.self, forKey: .id), requestID: container.decode(UUID.self, forKey: .requestID), createdAt: container.decode(Date.self, forKey: .createdAt), mealTitle: container.decode(String.self, forKey: .mealTitle), providerName: container.decode(String.self, forKey: .providerName), modelVersion: container.decode(String.self, forKey: .modelVersion), outputSchemaVersion: container.decode(String.self, forKey: .outputSchemaVersion), confirmationStatus: container.decode(EstimateConfirmationStatus.self, forKey: .confirmationStatus), consumedShareRatio: container.decode(Double.self, forKey: .consumedShareRatio), components: container.decode([MealPhotoComponent].self, forKey: .components))
    }
}

public enum MealVisionError: Error, Codable, Sendable, Equatable {
    case timedOut
    case invalidResult(reason: String)
    case lowConfidence(maximum: Double)
}

public protocol MealVisionProvider: Sendable {
    func makeDraft(for request: MealVisionRequest) async throws -> MealVisionDraft
}

public enum FixtureMealVisionProviderMode: Sendable {
    case success
    case timeout
    case invalidResult
    case lowConfidence
}

public struct FixtureMealVisionProvider: MealVisionProvider {
    public let mode: FixtureMealVisionProviderMode

    public init(mode: FixtureMealVisionProviderMode = .success) {
        self.mode = mode
    }

    public func makeDraft(for request: MealVisionRequest) async throws -> MealVisionDraft {
        switch mode {
        case .timeout:
            throw MealVisionError.timedOut
        case .invalidResult:
            throw MealVisionError.invalidResult(reason: "Fixture returned an invalid component range.")
        case .lowConfidence:
            throw MealVisionError.lowConfidence(maximum: 0.2)
        case .success:
            return try MealVisionDraft(
                requestID: request.id,
                mealTitle: request.mealTitle,
                providerName: "fixture",
                modelVersion: "fixture-1.0",
                outputSchemaVersion: request.outputSchemaVersion,
                consumedShareRatio: 0.5,
                components: [
                    try MealPhotoComponent(templateID: "chicken-breast", freeTextName: "Grilled chicken", cookingMethod: .grilled, portionRange: try PortionEstimateRange(lowGrams: 160, midpointGrams: 200, highGrams: 240), confidence: 0.92),
                    try MealPhotoComponent(templateID: "cooked-rice", freeTextName: "Cooked rice", cookingMethod: .boiled, portionRange: try PortionEstimateRange(lowGrams: 180, midpointGrams: 240, highGrams: 300), confidence: 0.88),
                    try MealPhotoComponent(templateID: "mixed-vegetables", freeTextName: "Mixed vegetables", cookingMethod: .stirFried, portionRange: try PortionEstimateRange(lowGrams: 100, midpointGrams: 140, highGrams: 180), confidence: 0.78),
                    try MealPhotoComponent(templateID: "cooking-oil", freeTextName: "Cooking oil", cookingMethod: .stirFried, portionRange: try PortionEstimateRange(lowGrams: 8, midpointGrams: 12, highGrams: 18), confidence: 0.62, isHiddenOilOrSauce: true),
                ]
            )
        }
    }
}
