import Foundation
import Testing
@testable import FoodDecisionCore

struct DomainInvariantTests {
    @Test("Every nutrient rejects negative and non-finite input during construction and decoding", arguments: ["energyKcal", "fatGrams", "saturatedFatGrams", "carbohydrateGrams", "sugarGrams", "proteinGrams", "saltGrams", "fibreGrams"], [-1.0, Double.nan, .infinity, -.infinity])
    func nutrientBoundaries(field: String, value: Double) throws {
        let expected = value.isFinite ? DomainValidationError.invalidValue(field: field) : .nonFiniteValue(field: field)
        #expect(throws: expected) {
            try nutrients(overriding: [field: value])
        }
        let data = try replacingFields(in: NutrientValues.zero, with: [field: jsonNumber(value)])
        #expect(throws: expected) {
            try decoder().decode(NutrientValues.self, from: data)
        }
    }

    @Test("Energy targets must be finite and positive", arguments: [0.0, -1, Double.nan, .infinity, -.infinity])
    func energyGoalBoundaries(value: Double) throws {
        let expected = value.isFinite ? DomainValidationError.invalidValue(field: "energyKcal") : .nonFiniteValue(field: "energyKcal")
        #expect(throws: expected) {
            try GoalProfile(energyKcal: value, proteinGrams: 0, carbohydrateGrams: 0, fatGrams: 0)
        }
        let valid = try GoalProfile(energyKcal: 2_000, proteinGrams: 0, carbohydrateGrams: 0, fatGrams: 0)
        let data = try replacingFields(in: valid, with: ["energyKcal": jsonNumber(value)])
        #expect(throws: expected) {
            try decoder().decode(GoalProfile.self, from: data)
        }
    }

    @Test("Macro and optional goals share the constructor and decoding boundary", arguments: ["proteinGrams", "carbohydrateGrams", "fatGrams", "saturatedFatLimitGrams", "fibreGrams"], [-1.0, Double.nan, .infinity, -.infinity])
    func remainingGoalBoundaries(field: String, value: Double) throws {
        let expected = value.isFinite ? DomainValidationError.invalidValue(field: field) : .nonFiniteValue(field: field)
        #expect(throws: expected) {
            try goal(overriding: [field: value])
        }
        let data = try replacingFields(in: goal(), with: [field: jsonNumber(value)])
        #expect(throws: expected) {
            try decoder().decode(GoalProfile.self, from: data)
        }
    }

    @Test("Food identity text also passes through validation on decode", arguments: ["name", "source", "unit"])
    func foodDecodeTextBoundaries(field: String) throws {
        let data = try replacingFields(in: food(), with: [field: "  "])
        #expect(throws: DomainValidationError.emptyText(field: field)) {
            try JSONDecoder().decode(FoodItem.self, from: data)
        }
        let valid = try food()
        #expect(try JSONDecoder().decode(FoodItem.self, from: JSONEncoder().encode(valid)) == valid)
    }

    @Test("Optional targets preserve nil rather than manufacturing zero")
    func goalAndFoodContainerValidation() throws {
        let goal = try GoalProfile(energyKcal: 2_000, proteinGrams: 0, carbohydrateGrams: 0, fatGrams: 0)
        #expect(goal.fibreGrams == nil)
        #expect(goal.saturatedFatLimitGrams == nil)
        #expect(throws: DomainValidationError.nonFiniteValue(field: "fibreGrams")) {
            try GoalProfile(energyKcal: 2_000, proteinGrams: 0, carbohydrateGrams: 0, fatGrams: 0, fibreGrams: .infinity)
        }
        #expect(throws: DomainValidationError.emptyText(field: "name")) {
            try FoodItem(name: " ", category: .oil, nutrientsPer100Units: .zero, source: "test")
        }
        #expect(throws: DomainValidationError.emptyText(field: "source")) {
            try FoodItem(name: "Oil", category: .oil, nutrientsPer100Units: .zero, source: " ")
        }
        #expect(throws: DomainValidationError.nonFiniteValue(field: "tareWeightGrams")) {
            try ContainerProfile(name: "Bowl", tareWeightGrams: .infinity)
        }
        let bowl = try ContainerProfile(name: "Bowl", tareWeightGrams: 0)
        #expect(try JSONDecoder().decode(ContainerProfile.self, from: JSONEncoder().encode(bowl)) == bowl)
        let invalidBowl = try replacingFields(in: bowl, with: ["tareWeightGrams": "NaN"])
        #expect(throws: DomainValidationError.nonFiniteValue(field: "tareWeightGrams")) {
            try decoder().decode(ContainerProfile.self, from: invalidBowl)
        }
    }

    @Test("Scaling and addition report overflow; an empty sum is a verified zero")
    func nutrientArithmetic() throws {
        #expect(try NutrientValues.sum([]) == .zero)
        let huge = try nutrients(overriding: ["energyKcal": .greatestFiniteMagnitude])
        #expect(throws: DomainValidationError.calculationOverflow(field: "energyKcal")) {
            try huge.scaled(by: 2)
        }
        #expect(throws: DomainValidationError.calculationOverflow(field: "energyKcal")) {
            try NutrientValues.sum([huge, huge])
        }
        #expect(throws: DomainValidationError.nonFiniteValue(field: "multiplier")) {
            try huge.scaled(by: .infinity)
        }
        #expect(throws: DomainValidationError.invalidValue(field: "multiplier")) {
            try huge.scaled(by: -1)
        }
        let unknownFibre = try nutrients()
        #expect(try NutrientValues.sum([.zero, unknownFibre]).fibreGrams == nil)
        #expect(try unknownFibre.scaled(by: 0).fibreGrams == nil)
    }

    @Test("Formal component weights are finite and positive", arguments: [0.0, -1, Double.nan, .infinity, -.infinity])
    func componentWeightBoundaries(value: Double) throws {
        let expected: MealLoggingError = value.isFinite ? .invalidWeight : .nonFiniteWeight
        #expect(throws: expected) {
            try MealComponent(foodItem: food(), consumedWeightGrams: value)
        }
        let component = try MealComponent(foodItem: food(), consumedWeightGrams: 100)
        let data = try replacingFields(in: component, with: ["consumedWeightGrams": jsonNumber(value)])
        #expect(throws: expected) {
            try decoder().decode(MealComponent.self, from: data)
        }
    }

    @Test("The explicit meal constructor cannot bypass formal entry invariants")
    func formalMealBoundaries() throws {
        let component = try MealComponent(foodItem: food(), consumedWeightGrams: 100)
        #expect(throws: MealLoggingError.emptyComponents) {
            try meal(components: [])
        }
        #expect(throws: MealLoggingError.duplicateComponentID(component.id)) {
            try MealLog(title: "Meal", entryMethod: .weighed, coverageStatus: .complete, components: [component, component])
        }
        #expect(throws: MealLoggingError.unconfirmedEstimate) {
            try meal(components: [component], grade: .d)
        }
        #expect(throws: MealLoggingError.invalidSyncVersion) {
            try meal(components: [component], version: 0)
        }
        #expect(throws: MealLoggingError.inconsistentTotals) {
            try MealLog(title: "Meal", consumedWeightGrams: 101, nutrients: component.nutrients, coverageStatus: .complete, estimateEvidenceGrade: .a, components: [component])
        }
        #expect(throws: MealLoggingError.inconsistentTotals) {
            try MealLog(title: "Meal", consumedWeightGrams: 100, nutrients: .zero, coverageStatus: .complete, estimateEvidenceGrade: .a, components: [component])
        }
        let confirmedPhoto = try meal(components: [component], grade: .c)
        #expect(confirmedPhoto.isCompleteForDailyCoverage == true)
        #expect(try JSONDecoder().decode(MealLog.self, from: JSONEncoder().encode(confirmedPhoto)) == confirmedPhoto)
    }

    @Test("Decoding cannot restore invalid formal meals through a weaker path", arguments: ["empty", "duplicate", "draft", "weight", "nutrients", "version"])
    func mealDecodeBoundaries(kind: String) throws {
        let component = try MealComponent(foodItem: food(), consumedWeightGrams: 100)
        let valid = try meal(components: [component])
        let replacement: [String: Any]
        let expected: MealLoggingError
        switch kind {
        case "empty": replacement = ["components": []]; expected = .emptyComponents
        case "duplicate":
            let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(component))
            replacement = ["components": [object, object]]; expected = .duplicateComponentID(component.id)
        case "draft": replacement = ["estimateEvidenceGrade": "d"]; expected = .unconfirmedEstimate
        case "weight": replacement = ["consumedWeightGrams": 101]; expected = .inconsistentTotals
        case "version": replacement = ["healthKitSyncVersion": 0]; expected = .invalidSyncVersion
        default:
            let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(NutrientValues.zero))
            replacement = ["nutrients": object]; expected = .inconsistentTotals
        }
        let data = try replacingFields(in: valid, with: replacement)
        #expect(throws: expected) { try decoder().decode(MealLog.self, from: data) }
    }

    @Test("Meal aggregation rejects weight and nutrient arithmetic overflow")
    func mealOverflow() throws {
        let hugeWeight = try MealComponent(foodItemID: UUID(), foodName: "Food", consumedWeightGrams: .greatestFiniteMagnitude, unit: "g", nutrients: .zero)
        let otherHugeWeight = try MealComponent(foodItemID: UUID(), foodName: "Food", consumedWeightGrams: .greatestFiniteMagnitude, unit: "g", nutrients: .zero)
        #expect(throws: DomainValidationError.calculationOverflow(field: "consumedWeightGrams")) {
            try MealLog(title: "Meal", entryMethod: .weighed, coverageStatus: .complete, components: [hugeWeight, otherHugeWeight])
        }
        let hugeNutrients = try nutrients(overriding: ["energyKcal": .greatestFiniteMagnitude])
        let first = try MealComponent(foodItemID: UUID(), foodName: "Food", consumedWeightGrams: 100, unit: "g", nutrients: hugeNutrients)
        let second = try MealComponent(foodItemID: UUID(), foodName: "Food", consumedWeightGrams: 100, unit: "g", nutrients: hugeNutrients)
        #expect(throws: DomainValidationError.calculationOverflow(field: "energyKcal")) {
            try MealLog(title: "Meal", entryMethod: .weighed, coverageStatus: .complete, components: [first, second])
        }
    }

    @Test("Photo ranges, corrections, and calibrations reject infinite values", arguments: [Double.nan, .infinity, -.infinity])
    func photoFiniteBoundaries(value: Double) throws {
        #expect(throws: PortionEstimateRangeError.nonFiniteWeight) {
            try PortionEstimateRange(lowGrams: 0, midpointGrams: 1, highGrams: value)
        }
        let range = try PortionEstimateRange(lowGrams: 0, midpointGrams: 1, highGrams: 2)
        #expect(throws: PortionEstimateRangeError.nonFiniteWeight) {
            try MealPhotoComponent(freeTextName: "Oil", cookingMethod: .unknown, portionRange: range, confidence: 0.5, userCorrectedWeightGrams: value)
        }
        #expect(throws: PortionEstimateRangeError.nonFiniteWeight) {
            try PortionCalibration(photoEstimateID: UUID(), estimatedWeightGrams: 1, actualWeightGrams: value)
        }
        let data = try replacingFields(in: range, with: ["highGrams": jsonNumber(value)])
        #expect(throws: PortionEstimateRangeError.nonFiniteWeight) {
            try decoder().decode(PortionEstimateRange.self, from: data)
        }
        let component = try MealPhotoComponent(freeTextName: "Oil", cookingMethod: .unknown, portionRange: range, confidence: 0.5)
        let invalidCorrection = try replacingFields(in: component, with: ["userCorrectedWeightGrams": jsonNumber(value)])
        #expect(throws: PortionEstimateRangeError.nonFiniteWeight) {
            try decoder().decode(MealPhotoComponent.self, from: invalidCorrection)
        }
        let calibration = try PortionCalibration(photoEstimateID: UUID(), estimatedWeightGrams: 1, actualWeightGrams: 1)
        let invalidCalibration = try replacingFields(in: calibration, with: ["estimatedWeightGrams": jsonNumber(value)])
        #expect(throws: PortionEstimateRangeError.nonFiniteWeight) {
            try decoder().decode(PortionCalibration.self, from: invalidCalibration)
        }
    }

    @Test("Photo confidence rejects non-finite and out-of-bounds values", arguments: [-0.01, 1.01, Double.nan, .infinity, -.infinity])
    func photoConfidenceBoundaries(value: Double) throws {
        let range = try PortionEstimateRange(lowGrams: 0, midpointGrams: 1, highGrams: 2)
        #expect(throws: PortionEstimateRangeError.invalidConfidence) {
            try MealPhotoComponent(freeTextName: "Oil", cookingMethod: .unknown, portionRange: range, confidence: value)
        }
        let valid = try MealPhotoComponent(freeTextName: "Oil", cookingMethod: .unknown, portionRange: range, confidence: 0.5)
        let data = try replacingFields(in: valid, with: ["confidence": jsonNumber(value)])
        #expect(throws: PortionEstimateRangeError.invalidConfidence) {
            try decoder().decode(MealPhotoComponent.self, from: data)
        }
    }

    @Test("Photo estimates and vision drafts reject invalid sharing ratios on both entry paths", arguments: [0.0, -1, 1.01, Double.nan, .infinity, -.infinity])
    func photoSharingRatioBoundaries(value: Double) throws {
        #expect(throws: PortionEstimateRangeError.invalidSharingRatio) {
            try photoEstimate(ratio: value)
        }
        let estimateData = try replacingFields(in: photoEstimate(), with: ["consumedShareRatio": jsonNumber(value)])
        #expect(throws: PortionEstimateRangeError.invalidSharingRatio) {
            try decoder().decode(MealPhotoEstimate.self, from: estimateData)
        }
        #expect(throws: PortionEstimateRangeError.invalidSharingRatio) {
            try visionDraft(ratio: value)
        }
        let draftData = try replacingFields(in: visionDraft(), with: ["consumedShareRatio": jsonNumber(value)])
        #expect(throws: PortionEstimateRangeError.invalidSharingRatio) {
            try decoder().decode(MealVisionDraft.self, from: draftData)
        }
    }

    @Test("Empty unconfirmed photo drafts remain drafts but confirmed estimates need unique components")
    func photoStructureBoundary() throws {
        let draft = try photoEstimate()
        #expect(draft.components.isEmpty == true)
        #expect(draft.confirmationStatus == .draft)
        #expect(throws: PortionEstimateRangeError.emptyComponents) {
            try photoEstimate(status: .confirmed)
        }
        let component = try MealPhotoComponent(freeTextName: "Oil", cookingMethod: .stirFried, portionRange: PortionEstimateRange(lowGrams: 2, midpointGrams: 5, highGrams: 10), confidence: 0.5, isHiddenOilOrSauce: true, userCorrectedWeightGrams: 8)
        #expect(throws: PortionEstimateRangeError.duplicateComponentID(component.id)) {
            try photoEstimate(components: [component, component])
        }
        let estimate = try photoEstimate(status: .confirmed, ratio: 0.5, components: [component])
        let consumed = try #require(estimate.consumedComponents().first)
        let expectedRange = try PortionEstimateRange(lowGrams: 4, midpointGrams: 4, highGrams: 4)
        #expect(consumed.userCorrectedWeightGrams == 4)
        #expect(consumed.portionRange == expectedRange)
        #expect(consumed.isHiddenOilOrSauce == true)
        #expect(consumed.cookingMethod == .stirFried)
        #expect(estimate.components.first?.userCorrectedWeightGrams == 8)
    }

    @Test("Validated timestamps cannot be non-finite", arguments: [Double.nan, .infinity, -.infinity])
    func dateBoundaries(value: Double) throws {
        let date = Date(timeIntervalSinceReferenceDate: value)
        #expect(throws: DomainValidationError.nonFiniteValue(field: "effectiveFrom")) {
            try GoalProfile(effectiveFrom: date, energyKcal: 1, proteinGrams: 0, carbohydrateGrams: 0, fatGrams: 0)
        }
        #expect(throws: DomainValidationError.nonFiniteValue(field: "createdAt")) {
            try PortionCalibration(createdAt: date, photoEstimateID: UUID(), estimatedWeightGrams: 0, actualWeightGrams: 0)
        }
        #expect(throws: DomainValidationError.nonFiniteValue(field: "createdAt")) {
            try MealPhotoEstimate(createdAt: date, mealTitle: "Meal", imageReference: "", providerName: "fixture", modelVersion: "1", outputSchemaVersion: "1", confirmationStatus: .draft, consumedShareRatio: 1, components: [])
        }
        let row = try MealTemplateComponent(foodItemID: UUID(), foodName: "Rice", defaultWeightGrams: 1)
        var template = try MealTemplate(name: "Meal", components: [row])
        let before = template
        #expect(throws: DomainValidationError.nonFiniteValue(field: "lastUsedAt")) {
            try template.recordUse(at: date)
        }
        #expect(template == before)
    }

    @Test("Template use count validation and overflow are atomic")
    func templateCounterBoundaries() throws {
        let row = try MealTemplateComponent(foodItemID: UUID(), foodName: "Rice", defaultWeightGrams: 100)
        #expect(throws: MealTemplateError.invalidUseCount) {
            try MealTemplate(name: "Meal", useCount: -1, components: [row])
        }
        var template = try MealTemplate(name: "Meal", lastUsedAt: Date(timeIntervalSince1970: 1), useCount: .max, components: [row])
        let before = template
        #expect(throws: MealTemplateError.useCountOverflow) {
            try template.recordUse(at: Date(timeIntervalSince1970: 2))
        }
        #expect(template == before)
        let data = try replacingFields(in: template, with: ["useCount": -1])
        #expect(throws: MealTemplateError.invalidUseCount) {
            try JSONDecoder().decode(MealTemplate.self, from: data)
        }
        #expect(throws: MealTemplateError.nonFiniteWeight) {
            try MealTemplateComponent(foodItemID: UUID(), foodName: "Rice", defaultWeightGrams: .infinity)
        }
    }

    private func nutrients(overriding values: [String: Double] = [:]) throws -> NutrientValues {
        try NutrientValues(energyKcal: values["energyKcal"] ?? 10, fatGrams: values["fatGrams"] ?? 0, saturatedFatGrams: values["saturatedFatGrams"] ?? 0, carbohydrateGrams: values["carbohydrateGrams"] ?? 0, sugarGrams: values["sugarGrams"] ?? 0, proteinGrams: values["proteinGrams"] ?? 0, saltGrams: values["saltGrams"] ?? 0, fibreGrams: values["fibreGrams"])
    }

    private func food() throws -> FoodItem {
        try FoodItem(name: "Rice", category: .stapleGrain, nutrientsPer100Units: nutrients(), source: "test")
    }

    private func goal(overriding values: [String: Double] = [:]) throws -> GoalProfile {
        try GoalProfile(energyKcal: values["energyKcal"] ?? 2_000, proteinGrams: values["proteinGrams"] ?? 0, carbohydrateGrams: values["carbohydrateGrams"] ?? 0, fatGrams: values["fatGrams"] ?? 0, saturatedFatLimitGrams: values["saturatedFatLimitGrams"], fibreGrams: values["fibreGrams"])
    }

    private func photoEstimate(status: EstimateConfirmationStatus = .draft, ratio: Double = 1, components: [MealPhotoComponent] = []) throws -> MealPhotoEstimate {
        try MealPhotoEstimate(mealTitle: "Meal", imageReference: "", providerName: "fixture", modelVersion: "1", outputSchemaVersion: "1", confirmationStatus: status, consumedShareRatio: ratio, components: components)
    }

    private func visionDraft(ratio: Double = 1) throws -> MealVisionDraft {
        try MealVisionDraft(requestID: UUID(), mealTitle: "Meal", providerName: "fixture", modelVersion: "1", outputSchemaVersion: "1", consumedShareRatio: ratio, components: [])
    }

    private func meal(components: [MealComponent], grade: EstimateEvidenceGrade = .a, version: Int = 1) throws -> MealLog {
        try MealLog(title: "Meal", consumedWeightGrams: components.reduce(0) { $0 + $1.consumedWeightGrams }, nutrients: NutrientValues.sum(components.map(\.nutrients)), coverageStatus: .complete, estimateEvidenceGrade: grade, healthKitSyncVersion: version, components: components)
    }

    private func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.nonConformingFloatDecodingStrategy = .convertFromString(positiveInfinity: "Infinity", negativeInfinity: "-Infinity", nan: "NaN")
        return decoder
    }

    private func jsonNumber(_ value: Double) -> Any {
        if value.isNaN { return "NaN" }
        if value == .infinity { return "Infinity" }
        if value == -.infinity { return "-Infinity" }
        return value
    }

    private func replacingFields<T: Encodable>(in value: T, with replacement: [String: Any]) throws -> Data {
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any])
        object.merge(replacement) { _, new in new }
        return try JSONSerialization.data(withJSONObject: object)
    }
}
