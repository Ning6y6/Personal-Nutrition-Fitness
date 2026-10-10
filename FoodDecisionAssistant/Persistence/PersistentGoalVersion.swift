import FoodDecisionCore
import Foundation
import SwiftData

/// A complete committed snapshot. Business commands only append; raw restoration preserves
/// unsupported historical values so an archive never silently repairs its source records.
@Model
final class PersistentGoalVersion {
    @Attribute(.unique) var id: UUID
    var effectiveDayKey: Int
    var effectiveFrom: Date
    var energyKcal: Double
    var proteinGrams: Double
    var carbohydrateGrams: Double
    var fatGrams: Double
    var saturatedFatLimitGrams: Double?
    var fibreGrams: Double?
    var sourceRawValue: String
    var sourceNote: String?
    var confirmedAt: Date
    var timeZoneIdentifier: String
    var commitSequence: Int
    var policyVersion: Int

    init(domain: GoalVersion) {
        id = domain.id
        effectiveDayKey = domain.effectiveDay.key
        effectiveFrom = domain.profile.effectiveFrom
        energyKcal = domain.profile.energyKcal
        proteinGrams = domain.profile.proteinGrams
        carbohydrateGrams = domain.profile.carbohydrateGrams
        fatGrams = domain.profile.fatGrams
        saturatedFatLimitGrams = domain.profile.saturatedFatLimitGrams
        fibreGrams = domain.profile.fibreGrams
        sourceRawValue = domain.source.rawValue
        sourceNote = domain.sourceNote
        confirmedAt = domain.confirmedAt
        timeZoneIdentifier = domain.timeZoneIdentifier
        commitSequence = domain.commitSequence
        policyVersion = domain.policyVersion
    }

    init(archivedID: UUID, effectiveDayKey: Int, effectiveFrom: Date,
         energyKcal: Double, proteinGrams: Double, carbohydrateGrams: Double, fatGrams: Double,
         saturatedFatLimitGrams: Double?, fibreGrams: Double?, sourceRawValue: String,
         sourceNote: String?, confirmedAt: Date, timeZoneIdentifier: String,
         commitSequence: Int, policyVersion: Int) {
        id = archivedID
        self.effectiveDayKey = effectiveDayKey
        self.effectiveFrom = effectiveFrom
        self.energyKcal = energyKcal
        self.proteinGrams = proteinGrams
        self.carbohydrateGrams = carbohydrateGrams
        self.fatGrams = fatGrams
        self.saturatedFatLimitGrams = saturatedFatLimitGrams
        self.fibreGrams = fibreGrams
        self.sourceRawValue = sourceRawValue
        self.sourceNote = sourceNote
        self.confirmedAt = confirmedAt
        self.timeZoneIdentifier = timeZoneIdentifier
        self.commitSequence = commitSequence
        self.policyVersion = policyVersion
    }

    var domainModel: GoalVersion {
        get throws {
            try PersistentDomainConversion.validated(entity: .goalVersion, id: id) {
                let source = try PersistentDomainConversion.rawEnum(GoalSource.self,
                    raw: sourceRawValue, entity: .goalVersion, id: id, field: "sourceRawValue")
                let profile = try GoalProfile(id: id, effectiveFrom: effectiveFrom,
                    energyKcal: energyKcal, proteinGrams: proteinGrams,
                    carbohydrateGrams: carbohydrateGrams, fatGrams: fatGrams,
                    saturatedFatLimitGrams: saturatedFatLimitGrams, fibreGrams: fibreGrams)
                return try GoalVersion(profile: profile, effectiveDay: GoalDay(key: effectiveDayKey),
                    source: source, sourceNote: sourceNote, confirmedAt: confirmedAt,
                    timeZoneIdentifier: timeZoneIdentifier, commitSequence: commitSequence,
                    policyVersion: policyVersion)
            }
        }
    }
}
