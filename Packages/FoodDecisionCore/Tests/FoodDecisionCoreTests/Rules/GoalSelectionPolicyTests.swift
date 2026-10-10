import Foundation
import Testing
@testable import FoodDecisionCore

struct GoalSelectionPolicyTests {
    @Test("A day before the first reliable version remains unknown, including future-only timelines")
    func unknownBeforeFirstVersion() throws {
        let day = try GoalDay(key: 20261010)
        #expect(try GoalSelectionPolicy.v1.select(for: day, versions: []) == nil)
        #expect(try GoalSelectionPolicy.v1.select(for: day, versions: [version(day: 20261011, sequence: 1)]) == nil)
    }

    @Test("Selection uses the statistic date rather than backfill or confirmation time")
    func statisticDate() throws {
        let old = try version(day: 20261010, sequence: 1)
        let new = try version(day: 20261012, sequence: 2)
        #expect(try GoalSelectionPolicy.v1.select(for: GoalDay(key: 20261011), versions: [new, old]) == old)
        #expect(try GoalSelectionPolicy.v1.select(for: GoalDay(key: 20261012), versions: [old, new]) == new)
    }

    @Test("Same-day A to B to A keeps every snapshot and selects the final confirmation")
    func repeatedSameDayValues() throws {
        let firstA = try version(day: 20261010, sequence: 1, energy: 2_000)
        let b = try version(day: 20261010, sequence: 2, energy: 2_400)
        let lastA = try version(day: 20261010, sequence: 3, energy: 2_000)
        #expect(firstA.profile.energyKcal == lastA.profile.energyKcal)
        #expect(firstA.id != lastA.id)
        #expect(try GoalSelectionPolicy.v1.select(for: GoalDay(key: 20261010), versions: [b, lastA, firstA]) == lastA)
    }

    @Test("A higher sequence on an earlier day cannot cancel a future arrangement")
    func futureScheduleSurvivesEarlierDayEdit() throws {
        let future = try version(day: 20261020, sequence: 1, energy: 2_000)
        let earlier = try version(day: 20261011, sequence: 2, energy: 2_300)
        let timeline = [earlier, future]
        #expect(try GoalSelectionPolicy.v1.select(for: GoalDay(key: 20261019), versions: timeline) == earlier)
        #expect(try GoalSelectionPolicy.v1.select(for: GoalDay(key: 20261020), versions: timeline) == future)
    }

    @Test("Sorting does not depend on array order", arguments: [
        [0, 1, 2], [0, 2, 1], [1, 0, 2], [1, 2, 0], [2, 0, 1], [2, 1, 0],
    ])
    func inputOrderIsIrrelevant(order: [Int]) throws {
        let timeline = try [version(day: 20261010, sequence: 3), version(day: 20261011, sequence: 1), version(day: 20261011, sequence: 2)]
        #expect(try GoalSelectionPolicy.v1.select(for: GoalDay(key: 20261012), versions: order.map { timeline[$0] }) == timeline[2])
    }

    @Test("Wall-clock correction does not reverse same-day confirmation order")
    func sequenceWinsOverClock() throws {
        let a = try version(day: 20261010, sequence: 1)
        let earlierClock = a.confirmedAt.addingTimeInterval(-3_600)
        let b = try version(day: 20261010, sequence: 2, confirmedAt: earlierClock)
        #expect(try GoalSelectionPolicy.v1.select(for: GoalDay(key: 20261010), versions: [a, b]) == b)
    }

    @Test("Ambiguous identities are rejected even in future records")
    func duplicateIdentity() throws {
        let id = UUID()
        let a = try version(day: 20261010, sequence: 1, id: id)
        let b = try version(day: 20261020, sequence: 2, id: id)
        #expect(throws: GoalHistoryError.duplicateVersionID(id)) {
            try GoalSelectionPolicy.v1.select(for: GoalDay(key: 20261010), versions: [a, b])
        }
    }

    @Test("Duplicate commit sequences are rejected across the whole timeline")
    func duplicateSequence() throws {
        let a = try version(day: 20261010, sequence: 1)
        let b = try version(day: 20261020, sequence: 1)
        #expect(throws: GoalHistoryError.duplicateCommitSequence(1)) {
            try GoalSelectionPolicy.v1.select(for: GoalDay(key: 20261010), versions: [a, b])
        }
    }

    @Test("Travelling reselects by local civil day without changing saved audit boundaries")
    func travellingLocalDay() throws {
        let old = try version(day: 20261009, sequence: 1)
        let new = try version(day: 20261010, sequence: 2)
        let timeline = [old, new]
        let instant = try #require(ISO8601DateFormatter().date(from: "2026-10-10T00:30:00Z"))
        let londonDay = try GoalDay(containing: instant, timeZoneIdentifier: "Europe/London")
        let losAngelesDay = try GoalDay(containing: instant, timeZoneIdentifier: "America/Los_Angeles")
        #expect(try GoalSelectionPolicy.v1.select(for: londonDay, versions: timeline) == new)
        #expect(try GoalSelectionPolicy.v1.select(for: losAngelesDay, versions: timeline) == old)
        #expect(new.timeZoneIdentifier == "Europe/London")
        #expect(new.profile.effectiveFrom == (try new.effectiveDay.start(in: "Europe/London")))
    }

    private func version(day key: Int, sequence: Int, energy: Double = 2_000, id: UUID = UUID(), confirmedAt: Date? = nil) throws -> GoalVersion {
        let day = try GoalDay(key: key)
        let start = try day.start(in: "Europe/London")
        let profile = try GoalProfile(id: id, effectiveFrom: start, energyKcal: energy, proteinGrams: 140, carbohydrateGrams: 210, fatGrams: 60)
        return try GoalVersion(profile: profile, effectiveDay: day, source: .selfSelected, confirmedAt: confirmedAt ?? start.addingTimeInterval(15 * 3_600), timeZoneIdentifier: "Europe/London", commitSequence: sequence)
    }
}
