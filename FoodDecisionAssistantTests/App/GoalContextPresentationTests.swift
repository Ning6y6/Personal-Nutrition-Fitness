import FoodDecisionCore
import Foundation
import Testing

@testable import FoodDecisionAssistant

struct GoalContextPresentationTests {
    @Test("Scheduled targets are shown while today's valid current target remains in use", arguments: [false, true])
    func futureWithCurrentGoal(usesLegacy: Bool) throws {
        let day = try GoalDay(key: 20261011)
        let current = try version(dayKey: day.key, sequence: 1)
        let future = try version(dayKey: 20261012, sequence: 2)
        let read = snapshot(versions: usesLegacy ? [future] : [current, future],
            selected: usesLegacy ? nil : current, legacyCurrent: usesLegacy ? current.profile : nil)
        #expect(GoalContextPresentation.text(for: read, day: day)
            == "新目标将于10月12日生效，今天仍使用当前目标。")
    }

    @Test("The earliest future day is shown regardless of commit order or same-day replacements")
    func earliestFutureDay() throws {
        let day = try GoalDay(key: 20261011)
        let current = try version(dayKey: day.key, sequence: 1)
        let read = snapshot(versions: [
            try version(dayKey: 20261020, sequence: 2),
            try version(dayKey: 20261012, sequence: 5),
            try version(dayKey: 20260930, sequence: 3),
            current,
            try version(dayKey: 20261012, sequence: 4),
        ], selected: current)
        #expect(GoalContextPresentation.text(for: read, day: day)
            == "新目标将于10月12日生效，今天仍使用当前目标。")
        #expect(read.selected == current)
    }

    @Test("A future target does not imply that today already has an effective target")
    func futureWithUnknownCurrent() throws {
        let day = try GoalDay(key: 20261011)
        let read = snapshot(versions: [try version(dayKey: 20261012, sequence: 1)], hasLegacy: true)
        #expect(GoalContextPresentation.text(for: read, day: day)
            == "新目标将于10月12日生效，今天还没有生效的目标。")
        #expect(read.currentProfile == nil)
    }

    @Test("A schedule crossing New Year displays its civil year")
    func futureAcrossYears() throws {
        let day = try GoalDay(key: 20261231)
        let current = try version(dayKey: day.key, sequence: 1)
        let read = snapshot(versions: [try version(dayKey: 20270101, sequence: 2)], legacyCurrent: current.profile)
        #expect(GoalContextPresentation.text(for: read, day: day)
            == "新目标将于2027年1月1日生效，今天仍使用当前目标。")
    }

    @Test("Only a currently used legacy goal receives the pre-update explanation")
    func currentLegacyWithoutSchedule() throws {
        let day = try GoalDay(key: 20261011)
        let current = try version(dayKey: day.key, sequence: 1)
        let read = snapshot(legacyCurrent: current.profile)
        #expect(GoalContextPresentation.text(for: read, day: day)
            == "当前目标是在更新前设置的，过去的修改记录无法还原。")
    }

    @Test("Retaining legacy records does not describe a newly confirmed current goal as old")
    func selectedVersionWithRetainedLegacy() throws {
        let day = try GoalDay(key: 20261011)
        let current = try version(dayKey: day.key, sequence: 1)
        let read = snapshot(versions: [current], selected: current, hasLegacy: true)
        #expect(GoalContextPresentation.text(for: read, day: day) == nil)
    }

    @Test("Unknown current targets without a schedule do not manufacture a current-goal explanation", arguments: [false, true])
    func unknownWithoutSchedule(hasLegacy: Bool) throws {
        let day = try GoalDay(key: 20261011)
        let read = snapshot(hasLegacy: hasLegacy)
        #expect(GoalContextPresentation.text(for: read, day: day) == nil)
        #expect(read.currentProfile == nil)
    }

    @Test("Legacy confirmation problems take priority over normal legacy and future-schedule hints", arguments: [false, true])
    func legacyProblemTakesPriority(hasFuture: Bool) throws {
        let day = try GoalDay(key: 20261011)
        let versions = hasFuture ? [try version(dayKey: 20261012, sequence: 1)] : []
        let read = snapshot(versions: versions, hasLegacy: true, legacyNeedsConfirmation: true)
        #expect(GoalContextPresentation.text(for: read, day: day)
            == "之前的目标信息不完整或无法确定，请到预算与目标页重新确认。原记录会保留。")
    }

    private func snapshot(
        versions: [GoalVersion] = [], selected: GoalVersion? = nil,
        legacyCurrent: GoalProfile? = nil, hasLegacy: Bool = false, legacyNeedsConfirmation: Bool = false
    ) -> GoalHistorySnapshot {
        GoalHistorySnapshot(versions: versions, selected: selected, legacyCurrent: legacyCurrent,
            baseline: GoalHistoryBaseline(versions: versions, legacyRecords: []),
            hasLegacy: hasLegacy || legacyCurrent != nil, legacyNeedsConfirmation: legacyNeedsConfirmation)
    }

    private func version(dayKey: Int, sequence: Int) throws -> GoalVersion {
        let day = try GoalDay(key: dayKey)
        let zone = "Europe/London"
        let start = try day.start(in: zone)
        let profile = try GoalProfile(effectiveFrom: start, energyKcal: 2_000,
            proteinGrams: 140, carbohydrateGrams: 200, fatGrams: 60)
        return try GoalVersion(profile: profile, effectiveDay: day, source: .selfSelected,
            confirmedAt: start, timeZoneIdentifier: zone, commitSequence: sequence)
    }
}
