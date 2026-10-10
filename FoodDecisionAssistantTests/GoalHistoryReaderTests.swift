import FoodDecisionCore
import Foundation
import SwiftData
import Testing

@testable import FoodDecisionAssistant

@MainActor
struct GoalHistoryReaderTests {
    private let zone = "Europe/London"
    private let clock = Date(timeIntervalSince1970: 1_791_633_600)
    private var today: GoalDay { get throws { try GoalDay(containing: clock, timeZoneIdentifier: zone) } }

    @Test("Legacy targets are opt-in current references and never the default historical result")
    func defaultReadsDoNotInventLegacyHistory() throws {
        let container = try makeContainer()
        let legacy = try seedLegacy(in: container)
        let yesterday = try today.addingDays(-1, timeZoneIdentifier: zone)
        for day in [yesterday, try today] {
            let history = try GoalHistoryReader.read(container: container, day: day)
            #expect(history.hasLegacy)
            #expect(history.selected == nil)
            #expect(history.legacyCurrent == nil)
            #expect(history.currentProfile == nil)
            #expect(history.baseline.legacyRecords.count == 1)
        }
        let current = try GoalHistoryReader.read(container: container, day: today, allowLegacyCurrent: true)
        #expect(current.currentProfile == legacy)
        #expect(current.selected == nil)
    }

    @Test("Today's legacy reference remains until the first scheduled version actually takes effect")
    func legacyReferenceUntilFutureEffectiveDay() throws {
        let container = try makeContainer()
        let legacy = try seedLegacy(in: container)
        let tomorrow = try today.addingDays(1, timeZoneIdentifier: zone)
        let scheduled = try save(request(in: container, day: tomorrow), in: container)
        let current = try GoalHistoryReader.read(container: container, day: today, allowLegacyCurrent: true)
        #expect(current.selected == nil)
        #expect(current.legacyCurrent == legacy)
        #expect(current.currentProfile == legacy)
        #expect(current.versions == [scheduled])
        #expect(try GoalHistoryReader.read(container: container, day: today).currentProfile == nil)
        let nextDay = try GoalHistoryReader.read(container: container, day: tomorrow, allowLegacyCurrent: true)
        #expect(nextDay.selected == scheduled)
        #expect(nextDay.legacyCurrent == nil)
        #expect(nextDay.currentProfile == scheduled.profile)
    }

    @Test("Ambiguous legacy values allow a new explicit confirmation while retaining all original rows")
    func ambiguousLegacyCanBeConfirmedWithoutRewriting() throws {
        let container = try makeContainer()
        _ = try seedLegacy(in: container, energy: 2_000)
        _ = try seedLegacy(in: container, energy: 2_300)
        let before = try GoalHistoryReader.read(container: container, day: today, allowLegacyCurrent: true)
        #expect(before.legacyNeedsConfirmation)
        #expect(before.currentProfile == nil)
        #expect(before.baseline.legacyRecords.count == 2)
        let confirmed = try save(request(in: container, baseline: before.baseline), in: container)
        let after = try GoalHistoryReader.read(container: container, day: today, allowLegacyCurrent: true)
        #expect(after.selected == confirmed)
        #expect(after.legacyNeedsConfirmation == false)
        #expect(after.baseline.legacyRecords == before.baseline.legacyRecords)
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<PersistentGoalProfile>()) == 2)
    }

    @Test("Invalid raw legacy values are retained when a corrected first version is confirmed", arguments: ["energy", "optionalLimit"])
    func invalidLegacyCanBeConfirmedWithoutRepairingOriginal(field: String) throws {
        let container = try makeContainer()
        _ = try seedLegacy(in: container, invalidField: field)
        let before = try GoalHistoryReader.read(container: container, day: today, allowLegacyCurrent: true)
        #expect(before.legacyNeedsConfirmation)
        #expect(before.currentProfile == nil)
        let confirmed = try save(request(in: container, baseline: before.baseline), in: container)
        let after = try GoalHistoryReader.read(container: container, day: today, allowLegacyCurrent: true)
        #expect(after.selected == confirmed)
        #expect(after.baseline.legacyRecords == before.baseline.legacyRecords)
        let reader = ModelContext(container)
        let row = try #require(reader.fetch(FetchDescriptor<PersistentGoalProfile>()).first)
        #expect(throws: (any Error).self) { _ = try row.domainModel }
        if field == "energy" { #expect(row.energyKcal == -1) }
        else { #expect(row.saturatedFatLimitGrams == -1) }
    }

    @Test("Raw non-finite dates and nutrients have a stable baseline without asking SQLite to store them", arguments: [Double.nan, .infinity, -.infinity])
    func nonFiniteRawBaselineEquality(value: Double) throws {
        let profile = try legacyProfile()
        let first = PersistentGoalProfile(domain: profile)
        let second = PersistentGoalProfile(domain: profile)
        first.effectiveFrom = Date(timeIntervalSinceReferenceDate: value)
        second.effectiveFrom = Date(timeIntervalSinceReferenceDate: value)
        first.energyKcal = .nan
        second.energyKcal = .nan
        let baseline = LegacyGoalBaseline(first)
        #expect(baseline == baseline)
        #expect(baseline == LegacyGoalBaseline(second))
        second.effectiveFrom = Date(timeIntervalSinceReferenceDate: 1)
        #expect(baseline != LegacyGoalBaseline(second))
        second.effectiveFrom = first.effectiveFrom
        second.energyKcal = 2_000
        #expect(baseline != LegacyGoalBaseline(second))
    }

    @Test("A real committed legacy change invalidates a loaded baseline without overwriting it")
    func legacyBaselineChangeRejectsStaleRequest() throws {
        let container = try makeContainer()
        let legacy = try seedLegacy(in: container)
        let stale = try request(in: container)
        let writer = ModelContext(container)
        writer.autosaveEnabled = false
        let id = legacy.id
        let row = try #require(writer.fetch(FetchDescriptor<PersistentGoalProfile>(predicate: #Predicate { $0.id == id })).first)
        row.energyKcal = 2_450
        try writer.save()
        #expect(throws: GoalVersionSaveCommandError.baselineChanged) { try save(stale, in: container) }
        let snapshot = try GoalHistoryReader.read(container: container, day: today, allowLegacyCurrent: true)
        #expect(snapshot.versions.isEmpty)
        #expect(snapshot.currentProfile?.energyKcal == 2_450)
        #expect(snapshot.currentProfile?.id == legacy.id)
    }

    @Test("The maximum committed sequence cannot overflow or append another target")
    func sequenceOverflowHasNoWrite() throws {
        let container = try makeContainer()
        let day = try today
        let profile = try GoalProfile(effectiveFrom: day.start(in: zone), energyKcal: 2_000, proteinGrams: 140, carbohydrateGrams: 200, fatGrams: 60)
        let maximum = try GoalVersion(profile: profile, effectiveDay: day, source: .selfSelected, confirmedAt: clock, timeZoneIdentifier: zone, commitSequence: Int.max)
        let context = ModelContext(container)
        context.autosaveEnabled = false
        context.insert(PersistentGoalVersion(domain: maximum))
        try context.save()
        let next = try request(in: container)
        #expect(throws: GoalVersionSaveCommandError.sequenceOverflow) { try save(next, in: container) }
        #expect(try GoalHistoryReader.read(container: container, day: day).versions == [maximum])
    }

    @Test("Uncommitted requests reject midnight or time-zone changes without calling the saver", arguments: ["midnight", "timeZone"])
    func changedClockDoesNotWrite(kind: String) throws {
        let container = try makeContainer()
        _ = try seedLegacy(in: container)
        let request = try request(in: container)
        let original = request.expectedBaseline
        let tomorrow = try today.addingDays(1, timeZoneIdentifier: zone)
        let updatedClock = kind == "midnight" ? try tomorrow.start(in: zone) : clock
        let updatedZone = kind == "timeZone" ? "Asia/Tokyo" : zone
        let expected: GoalVersionSaveCommandError = kind == "midnight" ? .dateInPast : .timeZoneChanged
        var saverCalled = false
        #expect(throws: expected) {
            try GoalVersionSaveCommand.save(request: request, container: container, now: updatedClock, currentTimeZoneIdentifier: updatedZone) { context in
                saverCalled = true
                try context.save()
            }
        }
        #expect(saverCalled == false)
        #expect(try GoalHistoryReader.read(container: container, day: today).baseline == original)
    }

    @Test("A failed request retry uses one stable operation ID and one sequence")
    func failureThenRetryHasOneVersion() throws {
        let container = try makeContainer()
        let request = try request(in: container)
        #expect(throws: GoalVersionSaveCommandError.saveFailed) {
            try GoalVersionSaveCommand.save(request: request, container: container, now: clock, currentTimeZoneIdentifier: zone) { _ in
                throw BeforeCommit.injected
            }
        }
        #expect(try GoalHistoryReader.read(container: container, day: today).versions.isEmpty)
        let committed = try save(request, in: container)
        #expect(committed.id == request.operationID)
        #expect(committed.commitSequence == 1)
        #expect(try save(request, in: container) == committed)
        #expect(try GoalHistoryReader.read(container: container, day: today).versions == [committed])
    }

    @Test("A committed request remains idempotent after file-store close and reopen, even after travel")
    func reopenedFileStoreRetryDoesNotAppend() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("goal-history-reader-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("synthetic.store")
        let saved = try autoreleasepool { () throws -> (GoalVersionSaveRequest, GoalVersion) in
            let container = try makeContainer(at: url)
            let request = try request(in: container)
            return (request, try save(request, in: container))
        }
        try autoreleasepool {
            let reopened = try makeContainer(at: url)
            let retry = try GoalVersionSaveCommand.save(request: saved.0, container: reopened, now: clock.addingTimeInterval(172_800), currentTimeZoneIdentifier: "Asia/Tokyo")
            #expect(retry == saved.1)
            #expect(try ModelContext(reopened).fetchCount(FetchDescriptor<PersistentGoalVersion>()) == 1)
        }
        try autoreleasepool {
            let reopened = try makeContainer(at: url)
            let read = try GoalHistoryReader.read(container: reopened, day: today)
            #expect(read.versions == [saved.1])
            #expect(read.selected == saved.1)
        }
    }

    @Test("Reference provenance is required and preserved by the save transaction", arguments: [nil, "", " \n "] as [String?])
    func invalidReferenceCannotReachSaver(note: String?) throws {
        let container = try makeContainer()
        let request = try request(in: container, source: .userProvidedReference, sourceNote: note)
        var saverCalled = false
        #expect(throws: DomainValidationError.emptyText(field: "sourceNote")) {
            try GoalVersionSaveCommand.save(request: request, container: container, now: clock, currentTimeZoneIdentifier: zone) { context in
                saverCalled = true
                try context.save()
            }
        }
        #expect(saverCalled == false)
        #expect(try GoalHistoryReader.read(container: container, day: today).versions.isEmpty)
        let valid = try save(self.request(in: container, source: .userProvidedReference, sourceNote: "  用户提供的参考数值 \n"), in: container)
        let stored = try #require(try GoalHistoryReader.read(container: container, day: today).selected)
        #expect(stored == valid)
        #expect(stored.source == .userProvidedReference)
        #expect(stored.sourceNote == "用户提供的参考数值")
    }

    private func makeContainer(at url: URL? = nil) throws -> ModelContainer {
        let schema = Schema(versionedSchema: VersionedSchemaV2.self)
        let configuration: ModelConfiguration
        if let url { configuration = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none) }
        else { configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none) }
        return try ModelContainer(for: schema, migrationPlan: ShiHengMigrationPlan.self, configurations: configuration)
    }

    private func legacyProfile(energy: Double = 2_000) throws -> GoalProfile {
        try GoalProfile(effectiveFrom: Date(timeIntervalSince1970: 1), energyKcal: energy, proteinGrams: 140, carbohydrateGrams: 200, fatGrams: 60, saturatedFatLimitGrams: 0, fibreGrams: nil)
    }

    @discardableResult
    private func seedLegacy(in container: ModelContainer, energy: Double = 2_000, invalidField: String? = nil) throws -> GoalProfile {
        let profile = try legacyProfile(energy: energy)
        let row = PersistentGoalProfile(domain: profile)
        if invalidField == "energy" { row.energyKcal = -1 }
        if invalidField == "optionalLimit" { row.saturatedFatLimitGrams = -1 }
        let context = ModelContext(container)
        context.autosaveEnabled = false
        context.insert(row)
        try context.save()
        return profile
    }

    private func request(
        in container: ModelContainer, day: GoalDay? = nil, baseline: GoalHistoryBaseline? = nil,
        source: GoalSource = .selfSelected, sourceNote: String? = nil
    ) throws -> GoalVersionSaveRequest {
        var draft = GoalInputDraft()
        draft.energyKcal = "2100"
        draft.proteinGrams = "140"
        draft.carbohydrateGrams = "200"
        draft.fatGrams = "60"
        draft.saturatedFatLimitGrams = "0"
        draft.fibreGrams = ""
        draft.isConfirmed = true
        let currentDay = try today
        return GoalVersionSaveRequest(draft: draft, effectiveDay: day ?? currentDay,
            source: source, sourceNote: sourceNote, timeZoneIdentifier: zone, confirmedAt: clock,
            operationID: UUID(), expectedBaseline: try baseline ?? GoalHistoryReader.read(container: container, day: currentDay).baseline)
    }

    private func save(_ request: GoalVersionSaveRequest, in container: ModelContainer) throws -> GoalVersion {
        try GoalVersionSaveCommand.save(request: request, container: container, now: clock, currentTimeZoneIdentifier: zone)
    }

    private enum BeforeCommit: Error { case injected }
}
