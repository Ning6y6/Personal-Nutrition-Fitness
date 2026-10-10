import FoodDecisionCore
import Foundation
import SwiftData
import Testing
@testable import FoodDecisionAssistant

@MainActor
struct GoalSaveCommandTests {
    private let zone = "Europe/London"
    private var now: Date { Date(timeIntervalSince1970: 1_791_633_600) }
    private var today: GoalDay { get throws { try GoalDay(containing: now, timeZoneIdentifier: zone) } }

    @Test("Confirming legacy values creates a first version without rewriting the legacy row")
    func firstConfirmationPreservesLegacy() throws {
        let c = try container()
        let legacy = try GoalProfile(effectiveFrom: Date(timeIntervalSince1970: 1), energyKcal: 2000, proteinGrams: 140, carbohydrateGrams: 200, fatGrams: 60)
        c.mainContext.insert(PersistentGoalProfile(domain: legacy)); try c.mainContext.save()
        let r = try request(c, energy: "2000")
        let v = try save(r, c)
        #expect(v.commitSequence == 1)
        #expect(try ModelContext(c).fetch(FetchDescriptor<PersistentGoalProfile>()).first?.domainModel == legacy)
        let yesterday = try today.addingDays(-1, timeZoneIdentifier: zone)
        #expect(try GoalHistoryReader.read(container: c, day: yesterday, allowLegacyCurrent: false).currentProfile == nil)
        #expect(try GoalHistoryReader.read(container: c, day: today).selected == v)
    }

    @Test("Same-day changes append; the old version is unchanged and A to B to A is meaningful")
    func changesAppendWithoutValueDeduplication() throws {
        let c = try container()
        let a = try save(request(c, energy: "2000"), c)
        let b = try save(request(c, energy: "2200"), c)
        let final = try save(request(c, energy: "2000"), c)
        let snapshot = try GoalHistoryReader.read(container: c, day: today)
        #expect(snapshot.versions == [a, b, final])
        #expect(snapshot.selected == final)
        #expect(a.profile.energyKcal == 2000)
    }

    @Test("A future first version cannot become today's target")
    func futureIsNotCurrent() throws {
        let c = try container()
        let tomorrow = try today.addingDays(1, timeZoneIdentifier: zone)
        let future = try save(request(c, day: tomorrow), c)
        #expect(try GoalHistoryReader.read(container: c, day: today).currentProfile == nil)
        #expect(try GoalHistoryReader.read(container: c, day: tomorrow).selected == future)
    }

    @Test("An identical operation succeeds once even when retried after midnight")
    func identicalRetryIsIdempotent() throws {
        let c = try container()
        let r = try request(c)
        let first = try save(r, c)
        let retry = try GoalVersionSaveCommand.save(request: r, container: c, now: now.addingTimeInterval(172800), currentTimeZoneIdentifier: "Asia/Tokyo")
        #expect(retry == first)
        #expect(try ModelContext(c).fetchCount(FetchDescriptor<PersistentGoalVersion>()) == 1)
    }

    @Test("Same operation ID with different payload is never a unique-constraint upsert")
    func operationCollisionRefusesOverwrite() throws {
        let c = try container(); let r = try request(c)
        let first = try save(r, c)
        let changed = try request(c, energy: "2800", id: r.operationID)
        #expect(throws: GoalVersionSaveCommandError.operationConflict) { try save(changed, c) }
        #expect(try GoalHistoryReader.read(container: c, day: today).versions == [first])
    }

    @Test("A stale loaded baseline cannot silently replace a later confirmation")
    func staleBaselineIsRejected() throws {
        let c = try container(); let stale = try request(c)
        let saved = try save(request(c, energy: "2400"), c)
        #expect(throws: GoalVersionSaveCommandError.baselineChanged) { try save(stale, c) }
        #expect(try GoalHistoryReader.read(container: c, day: today).versions == [saved])
    }

    @Test("Failure rolls back only the private append; a later unrelated save cannot leak it")
    func rollbackProtectsSharedDraft() throws {
        let c = try container(); let r = try request(c)
        c.mainContext.autosaveEnabled = false
        c.mainContext.insert(try meal())
        var attempted: ModelContext?
        #expect(throws: GoalVersionSaveCommandError.saveFailed) {
            try GoalVersionSaveCommand.save(request: r, container: c, now: now, currentTimeZoneIdentifier: zone) { context in
                attempted = context
                #expect(context !== c.mainContext)
                #expect(context.autosaveEnabled == false)
                throw Injected.beforeCommit
            }
        }
        #expect(c.mainContext.hasChanges)
        #expect(attempted?.hasChanges == false)
        try attempted?.save(); try c.mainContext.save()
        #expect(try ModelContext(c).fetchCount(FetchDescriptor<PersistentGoalVersion>()) == 0)
        #expect(try ModelContext(c).fetchCount(FetchDescriptor<PersistentMealLog>()) == 1)
    }

    @Test("Successful append leaves an unrelated draft uncommitted")
    func successPreservesUnrelatedDraft() throws {
        let c = try container(); let r = try request(c)
        c.mainContext.autosaveEnabled = false; c.mainContext.insert(try meal())
        let v = try save(r, c)
        #expect(try ModelContext(c).fetchCount(FetchDescriptor<PersistentMealLog>()) == 0)
        #expect(c.mainContext.hasChanges)
        try c.mainContext.save()
        #expect(try GoalHistoryReader.read(container: c, day: today).selected == v)
    }

    @Test("An actual read-only file-store failure has no append after reopening")
    func realFailureAndReopen() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("goal-history-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("test.store")
        try autoreleasepool { _ = try container(url: url) }
        try autoreleasepool {
            let c = try container(url: url, allowsSave: false)
            #expect(throws: GoalVersionSaveCommandError.saveFailed) { try save(request(c), c) }
        }
        #expect(try ModelContext(container(url: url)).fetchCount(FetchDescriptor<PersistentGoalVersion>()) == 0)
    }

    @Test("Dirty shared goal state is rejected without dropping it")
    func dirtyGoalPreserved() throws {
        let c = try container(); let r = try request(c)
        c.mainContext.autosaveEnabled = false
        c.mainContext.insert(PersistentGoalProfile(domain: try GoalProfile(energyKcal: 1800, proteinGrams: 100, carbohydrateGrams: 100, fatGrams: 50)))
        #expect(throws: GoalVersionSaveCommandError.sharedGoalHasUnsavedChanges) { try save(r, c) }
        #expect(c.mainContext.hasChanges)
        #expect(try ModelContext(c).fetchCount(FetchDescriptor<PersistentGoalVersion>()) == 0)
    }

    @Test("Optional nil and explicit zero survive a committed snapshot", arguments: [false, true])
    func optionalValues(explicit: Bool) throws {
        let c = try container()
        var d = draft(); d.fibreGrams = explicit ? "0" : ""
        let r = try request(c, draftOverride: d)
        let v = try save(r, c)
        #expect(v.profile.fibreGrams == (explicit ? 0 : nil))
    }

    @Test("Unconfirmed input and expired dates cannot append")
    func invalidRequestHasNoWrite() throws {
        let c = try container(); var d = draft(); d.isConfirmed = false
        #expect(throws: GoalInputError.confirmationRequired) { try save(request(c, draftOverride: d), c) }
        let yesterday = try today.addingDays(-1, timeZoneIdentifier: zone)
        #expect(throws: GoalVersionSaveCommandError.dateInPast) { try save(request(c, day: yesterday), c) }
        #expect(try ModelContext(c).fetchCount(FetchDescriptor<PersistentGoalVersion>()) == 0)
    }

    private func container(url: URL? = nil, allowsSave: Bool = true) throws -> ModelContainer {
        let schema = Schema(versionedSchema: VersionedSchemaV2.self)
        let configuration: ModelConfiguration
        if let url { configuration = ModelConfiguration(schema: schema, url: url, allowsSave: allowsSave, cloudKitDatabase: .none) }
        else { configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none) }
        return try ModelContainer(for: schema, migrationPlan: ShiHengMigrationPlan.self, configurations: configuration)
    }
    private func draft(energy: String = "2100") -> GoalInputDraft {
        var d = GoalInputDraft(); d.energyKcal = energy; d.proteinGrams = "140"; d.carbohydrateGrams = "200"; d.fatGrams = "60"; d.isConfirmed = true
        return d
    }
    private func request(_ c: ModelContainer, energy: String = "2100", day: GoalDay? = nil, id: UUID = UUID(), draftOverride: GoalInputDraft? = nil) throws -> GoalVersionSaveRequest {
        GoalVersionSaveRequest(draft: draftOverride ?? draft(energy: energy), effectiveDay: try day ?? today,
            source: .selfSelected, sourceNote: nil, timeZoneIdentifier: zone, confirmedAt: now, operationID: id,
            expectedBaseline: try GoalHistoryReader.read(container: c, day: today).baseline)
    }
    private func save(_ r: GoalVersionSaveRequest, _ c: ModelContainer) throws -> GoalVersion {
        try GoalVersionSaveCommand.save(request: r, container: c, now: now, currentTimeZoneIdentifier: zone)
    }
    private func meal() throws -> PersistentMealLog {
        PersistentMealLog(domain: try MealLog(title: "synthetic", entryMethod: .weighed, coverageStatus: .complete,
            components: [MealComponent(foodItemID: UUID(), foodName: "synthetic", consumedWeightGrams: 1, unit: "g", nutrients: .zero)]))
    }
    private enum Injected: Error { case beforeCommit }
}
