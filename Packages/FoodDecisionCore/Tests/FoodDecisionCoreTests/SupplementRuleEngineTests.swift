import Testing
@testable import FoodDecisionCore

@Test func vitaminASupplementIsProhibited() {
    let assessment = SupplementRuleEngine.assess(labelText: "Vitamin A 800 µg from retinyl palmitate")
    #expect(assessment.conclusion == .prohibited)
}

@Test func vitaminAFromBetaCaroteneIsStillProhibitedWhenLabelledVitaminA() {
    let assessment = SupplementRuleEngine.assess(labelText: "Vitamin A 400 µg (from beta-carotene)")
    #expect(assessment.conclusion == .prohibited)
}

@Test func betaCaroteneOnlyRequiresPharmacist() {
    let assessment = SupplementRuleEngine.assess(labelText: "Beta-carotene 6 mg")
    #expect(assessment.conclusion == .consultPharmacist)
}

@Test func unknownSupplementDefaultsToPharmacist() {
    let assessment = SupplementRuleEngine.assess(labelText: "Magnesium citrate 200 mg")
    #expect(assessment.conclusion == .consultPharmacist)
}

