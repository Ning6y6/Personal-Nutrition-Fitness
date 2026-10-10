import Foundation
import Testing
@testable import FoodDecisionCore

struct GoalVersionTests {
    @Test("An explicit afternoon confirmation may apply to the whole current day")
    func sameDayConfirmation() throws {
        let version = try version()
        #expect(version.profile.effectiveFrom < version.confirmedAt)
        #expect(version.id == version.profile.id)
        #expect(version.effectiveDay.key == 20261010)
        #expect(version.policyVersion == 1)
        #expect(version.profile.saturatedFatLimitGrams == 0)
        #expect(version.profile.fibreGrams == nil)
    }

    @Test("Reference sources require an explicit nonblank note", arguments: [nil, "", " \n\t "] as [String?])
    func referenceRequiresNote(note: String?) {
        #expect(throws: DomainValidationError.emptyText(field: "sourceNote")) {
            try version(source: .userProvidedReference, sourceNote: note)
        }
    }

    @Test("Source notes are normalized without inventing a reference")
    func sourceNotes() throws {
        #expect(try version(sourceNote: "  \n ").sourceNote == nil)
        #expect(try version(source: .userProvidedReference, sourceNote: "  用户提供的参考数值 \n").sourceNote == "用户提供的参考数值")
    }

    @Test("Stored audit boundary must agree with the effective day and captured time zone")
    func inconsistentAuditBoundary() throws {
        let day = try GoalDay(key: 20261010)
        let profile = try GoalProfile(effectiveFrom: day.start(in: "UTC"), energyKcal: 2_000, proteinGrams: 140, carbohydrateGrams: 210, fatGrams: 60)
        #expect(throws: DomainValidationError.invalidValue(field: "effectiveFrom")) {
            try GoalVersion(profile: profile, effectiveDay: day, source: .selfSelected, confirmedAt: Date(timeIntervalSince1970: 1_000), timeZoneIdentifier: "Europe/London", commitSequence: 1)
        }
    }

    @Test("Commit sequences must be positive", arguments: [0, -1, Int.min])
    func invalidSequence(sequence: Int) {
        #expect(throws: DomainValidationError.invalidValue(field: "commitSequence")) {
            try version(sequence: sequence)
        }
    }

    @Test("Unsupported selection policy versions are rejected", arguments: [0, 2, -1])
    func unsupportedPolicy(policy: Int) {
        #expect(throws: GoalHistoryError.unsupportedPolicyVersion(policy)) { try version(policy: policy) }
    }

    @Test("Confirmation time must be finite", arguments: [Double.nan, .infinity, -.infinity])
    func invalidConfirmation(value: Double) {
        #expect(throws: DomainValidationError.nonFiniteValue(field: "confirmedAt")) {
            try version(confirmedAt: Date(timeIntervalSinceReferenceDate: value))
        }
    }

    @Test("Version Codable preserves exact values and validates tampered metadata")
    func codableValidation() throws {
        let original = try version(source: .userProvidedReference, sourceNote: "用户提供的参考")
        let data = try JSONEncoder().encode(original)
        #expect(try JSONDecoder().decode(GoalVersion.self, from: data) == original)
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        for field in ["commitSequence", "policyVersion", "timeZoneIdentifier", "effectiveDay", "sourceNote", "source"] {
            var changed = object
            switch field {
            case "commitSequence": changed[field] = 0
            case "policyVersion": changed[field] = 2
            case "timeZoneIdentifier": changed[field] = "Unknown/Zone"
            case "effectiveDay": changed[field] = ["key": 20261011]
            case "sourceNote": changed[field] = NSNull()
            default: changed[field] = "inventedClinicalValidation"
            }
            let invalid = try JSONSerialization.data(withJSONObject: changed)
            #expect(throws: (any Error).self) { try JSONDecoder().decode(GoalVersion.self, from: invalid) }
        }
        var profile = try #require(object["profile"] as? [String: Any])
        profile["energyKcal"] = -1
        object["profile"] = profile
        #expect(throws: DomainValidationError.invalidValue(field: "energyKcal")) {
            try JSONDecoder().decode(GoalVersion.self, from: JSONSerialization.data(withJSONObject: object))
        }
    }

    private func version(
        source: GoalSource = .selfSelected, sourceNote: String? = nil, sequence: Int = 1,
        policy: Int = 1, confirmedAt: Date? = nil
    ) throws -> GoalVersion {
        let day = try GoalDay(key: 20261010)
        let start = try day.start(in: "Europe/London")
        let profile = try GoalProfile(effectiveFrom: start, energyKcal: Double(2_000).nextUp, proteinGrams: 140, carbohydrateGrams: 210, fatGrams: 60, saturatedFatLimitGrams: 0, fibreGrams: nil)
        return try GoalVersion(profile: profile, effectiveDay: day, source: source, sourceNote: sourceNote, confirmedAt: confirmedAt ?? start.addingTimeInterval(15 * 3_600), timeZoneIdentifier: "Europe/London", commitSequence: sequence, policyVersion: policy)
    }
}
