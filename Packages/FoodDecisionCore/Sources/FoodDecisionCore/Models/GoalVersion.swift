import Foundation

/// A complete, immutable target snapshot resulting from one explicit user confirmation.
/// effectiveDay determines selection; effectiveFrom preserves the captured local day boundary.
public struct GoalVersion: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID { profile.id }
    public let profile: GoalProfile
    public let effectiveDay: GoalDay
    public let source: GoalSource
    public let sourceNote: String?
    public let confirmedAt: Date
    public let timeZoneIdentifier: String
    public let commitSequence: Int
    public let policyVersion: Int

    public init(
        profile: GoalProfile, effectiveDay: GoalDay, source: GoalSource, sourceNote: String? = nil,
        confirmedAt: Date, timeZoneIdentifier: String, commitSequence: Int, policyVersion: Int = 1
    ) throws {
        try DomainValidation.date(confirmedAt, field: "confirmedAt")
        guard commitSequence > 0 else { throw DomainValidationError.invalidValue(field: "commitSequence") }
        guard policyVersion == 1 else { throw GoalHistoryError.unsupportedPolicyVersion(policyVersion) }
        let boundary = try effectiveDay.start(in: timeZoneIdentifier)
        guard profile.effectiveFrom == boundary else {
            throw DomainValidationError.invalidValue(field: "effectiveFrom")
        }
        let note = sourceNote?.trimmingCharacters(in: .whitespacesAndNewlines)
        if source == .userProvidedReference { try DomainValidation.text(note ?? "", field: "sourceNote") }
        self.profile = profile
        self.effectiveDay = effectiveDay
        self.source = source
        self.sourceNote = note.flatMap { $0.isEmpty ? nil : $0 }
        self.confirmedAt = confirmedAt
        self.timeZoneIdentifier = timeZoneIdentifier
        self.commitSequence = commitSequence
        self.policyVersion = policyVersion
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            profile: container.decode(GoalProfile.self, forKey: .profile),
            effectiveDay: container.decode(GoalDay.self, forKey: .effectiveDay),
            source: container.decode(GoalSource.self, forKey: .source),
            sourceNote: container.decodeIfPresent(String.self, forKey: .sourceNote),
            confirmedAt: container.decode(Date.self, forKey: .confirmedAt),
            timeZoneIdentifier: container.decode(String.self, forKey: .timeZoneIdentifier),
            commitSequence: container.decode(Int.self, forKey: .commitSequence),
            policyVersion: container.decode(Int.self, forKey: .policyVersion)
        )
    }
}
