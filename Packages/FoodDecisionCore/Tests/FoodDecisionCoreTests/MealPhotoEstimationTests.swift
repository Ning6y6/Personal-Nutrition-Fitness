import Foundation
import Testing
@testable import FoodDecisionCore

@Test func portionRangeRejectsNegativeAndOutOfOrderWeights() {
    #expect(throws: PortionEstimateRangeError.negativeWeight) {
        try PortionEstimateRange(lowGrams: -1, midpointGrams: 0, highGrams: 1)
    }
    #expect(throws: PortionEstimateRangeError.invalidOrder) {
        try PortionEstimateRange(lowGrams: 20, midpointGrams: 10, highGrams: 30)
    }
}

@Test func sharingRatioAndConfidenceStayWithinTheirValidRanges() throws {
    let range = try PortionEstimateRange(lowGrams: 100, midpointGrams: 120, highGrams: 140)

    #expect(throws: PortionEstimateRangeError.invalidSharingRatio) {
        try range.scaled(by: 0)
    }
    #expect(throws: PortionEstimateRangeError.invalidSharingRatio) {
        try range.scaled(by: 1.01)
    }
    #expect(throws: PortionEstimateRangeError.invalidConfidence) {
        try MealPhotoComponent(
            freeTextName: "Rice",
            cookingMethod: .boiled,
            portionRange: range,
            confidence: -0.01
        )
    }
}

@Test func sharedMealScalesEveryComponentByConsumedRatio() async throws {
    let request = MealVisionRequest(mealTitle: "Dinner", imageReference: "sha256:fixture")
    let draft = try await FixtureMealVisionProvider().makeDraft(for: request)
    let estimate = try draft.makePhotoEstimate(imageReference: request.imageReference)

    let consumed = try estimate.consumedComponents()
    let expectedRanges = [
        try PortionEstimateRange(lowGrams: 80, midpointGrams: 100, highGrams: 120),
        try PortionEstimateRange(lowGrams: 90, midpointGrams: 120, highGrams: 150),
        try PortionEstimateRange(lowGrams: 50, midpointGrams: 70, highGrams: 90),
        try PortionEstimateRange(lowGrams: 4, midpointGrams: 6, highGrams: 9),
    ]

    #expect(consumed.count == 4)
    #expect(consumed.map(\.portionRange) == expectedRanges)
}

@Test func correctingAComponentPreservesTheHiddenOilComponent() async throws {
    let request = MealVisionRequest(mealTitle: "Dinner", imageReference: "sha256:fixture")
    let draft = try await FixtureMealVisionProvider().makeDraft(for: request)
    let hiddenOil = draft.components.first { $0.isHiddenOilOrSauce }
    let oil = try #require(hiddenOil)
    let correctedOil = try MealPhotoComponent(
        id: oil.id,
        templateID: oil.templateID,
        freeTextName: oil.freeTextName,
        cookingMethod: oil.cookingMethod,
        portionRange: oil.portionRange,
        confidence: oil.confidence,
        isHiddenOilOrSauce: true,
        userCorrectedWeightGrams: 20
    )
    var components = draft.components
    components[components.count - 1] = correctedOil
    let estimate = try MealPhotoEstimate(
        mealTitle: draft.mealTitle,
        imageReference: request.imageReference,
        providerName: draft.providerName,
        modelVersion: draft.modelVersion,
        outputSchemaVersion: draft.outputSchemaVersion,
        confirmationStatus: .confirmed,
        consumedShareRatio: 0.5,
        components: components
    )

    let consumedComponents = try estimate.consumedComponents()
    let hiddenConsumedOil = consumedComponents.first { $0.isHiddenOilOrSauce }
    let consumedOil = try #require(hiddenConsumedOil)

    #expect(consumedOil.userCorrectedWeightGrams == 10)
    #expect(consumedOil.portionRange.midpointGrams == 10)
}

@Test func fixtureProviderProducesAStableMixedMealDraft() async throws {
    let request = MealVisionRequest(mealTitle: "Chicken rice bowl", imageReference: "sha256:fixture")
    let draft = try await FixtureMealVisionProvider().makeDraft(for: request)

    #expect(draft.providerName == "fixture")
    #expect(draft.consumedShareRatio == 0.5)
    #expect(draft.components.map(\.templateID) == ["chicken-breast", "cooked-rice", "mixed-vegetables", "cooking-oil"])
    #expect(draft.components.last?.isHiddenOilOrSauce == true)
}

@Test func fixtureProviderFailureModesAreDistinct() async {
    let request = MealVisionRequest(mealTitle: "Dinner", imageReference: "sha256:fixture")

    do {
        _ = try await FixtureMealVisionProvider(mode: .timeout).makeDraft(for: request)
        Issue.record("Expected timeout")
    } catch let error as MealVisionError {
        #expect(error == .timedOut)
    } catch {
        Issue.record("Unexpected error: \(error)")
    }

    do {
        _ = try await FixtureMealVisionProvider(mode: .invalidResult).makeDraft(for: request)
        Issue.record("Expected invalid result")
    } catch let error as MealVisionError {
        #expect(error == .invalidResult(reason: "Fixture returned an invalid component range."))
    } catch {
        Issue.record("Unexpected error: \(error)")
    }

    do {
        _ = try await FixtureMealVisionProvider(mode: .lowConfidence).makeDraft(for: request)
        Issue.record("Expected low confidence")
    } catch let error as MealVisionError {
        #expect(error == .lowConfidence(maximum: 0.2))
    } catch {
        Issue.record("Unexpected error: \(error)")
    }
}

@Test func mealPhotoEstimateRoundTripsThroughCodable() async throws {
    let request = MealVisionRequest(mealTitle: "Dinner", imageReference: "sha256:fixture")
    let draft = try await FixtureMealVisionProvider().makeDraft(for: request)
    let calibration = try PortionCalibration(
        photoEstimateID: draft.id,
        componentID: draft.components[0].id,
        estimatedWeightGrams: 200,
        actualWeightGrams: 185
    )
    let estimate = try draft.makePhotoEstimate(
        imageReference: request.imageReference,
        calibrations: [calibration]
    )

    let restored = try JSONDecoder().decode(
        MealPhotoEstimate.self,
        from: JSONEncoder().encode(estimate)
    )

    #expect(restored == estimate)
}
