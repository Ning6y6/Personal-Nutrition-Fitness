import FoodDecisionCore
import Foundation
import SwiftData
import Testing
@testable import FoodDecisionAssistant

@MainActor
struct GoalFormSaveStateTests {
    private let zone = "Europe/London"
    private let clock = Date(timeIntervalSince1970: 1_791_633_600)
    private var day: GoalDay {
        get throws { try GoalDay(containing: clock, timeZoneIdentifier: zone) }
    }
    private var emptyBaseline: GoalHistoryBaseline {
        GoalHistoryBaseline(versions: [], legacyRecords: [])
    }

    @Test("Save confirms only the request copy and leaves the editable draft unconfirmed")
    func explicitSaveConfirmsOnlyCopy() throws {
        let draft = makeDraft()
        let original = draft
        var state = GoalFormSaveState()
        #expect(state.pendingRequest == nil)
        let request = state.request(
            draft: draft, effectiveDay: try day, source: .selfSelected, sourceNote: "synthetic source",
            timeZoneIdentifier: zone, expectedBaseline: emptyBaseline, decimalSeparator: ".",
            confirmedAt: clock, operationID: UUID()
        )
        #expect(draft == original)
        #expect(draft.isConfirmed == false)
        #expect(request.draft.isConfirmed)
        #expect(state.pendingRequest == request)
        let profile = try request.draft.validGoal(
            id: request.operationID, effectiveFrom: request.effectiveDay.start(in: zone)
        )
        #expect(profile.energyKcal == 2_100)
        #expect(profile.saturatedFatLimitGrams == 0)
        #expect(profile.fibreGrams == nil)
        #expect(throws: GoalInputError.confirmationRequired) {
            try draft.validGoal(id: request.operationID, effectiveFrom: request.effectiveDay.start(in: zone))
        }
    }

    @Test("An unchanged retry preserves the original operation, confirmation time and baseline")
    func unchangedPayloadReusesRequest() throws {
        var state = GoalFormSaveState()
        let first = state.request(
            draft: makeDraft(), effectiveDay: try day, source: .selfSelected, sourceNote: nil,
            timeZoneIdentifier: zone, expectedBaseline: emptyBaseline, decimalSeparator: ".",
            confirmedAt: clock, operationID: UUID()
        )
        let retry = state.request(
            draft: makeDraft(), effectiveDay: try day, source: .selfSelected, sourceNote: nil,
            timeZoneIdentifier: zone, expectedBaseline: emptyBaseline, decimalSeparator: ".",
            confirmedAt: clock.addingTimeInterval(60), operationID: UUID()
        )
        #expect(retry == first)
        #expect(state.pendingRequest == first)
    }

    @Test("Every raw input and interpretation change replaces the request before observers run", arguments: [
        "energy", "protein", "carbohydrate", "fat", "saturatedFat", "fibre",
        "effectiveDay", "source", "sourceNote", "timeZone", "decimalSeparator", "baseline",
        "numericFormatting", "noteWhitespace"
    ])
    func changedPayloadReplacesRequest(field: String) throws {
        var state = GoalFormSaveState()
        let first = state.request(
            draft: makeDraft(), effectiveDay: try day, source: .selfSelected, sourceNote: "synthetic source",
            timeZoneIdentifier: zone, expectedBaseline: emptyBaseline, decimalSeparator: ".",
            confirmedAt: clock, operationID: UUID()
        )
        var draft = makeDraft()
        var effectiveDay = try day
        var source = GoalSource.selfSelected
        var note = "synthetic source"
        var timeZoneIdentifier = zone
        var decimalSeparator = "."
        var baseline = emptyBaseline
        switch field {
        case "energy": draft.energyKcal = "2200"
        case "protein": draft.proteinGrams = "150"
        case "carbohydrate": draft.carbohydrateGrams = "210"
        case "fat": draft.fatGrams = "65"
        case "saturatedFat": draft.saturatedFatLimitGrams = "1"
        case "fibre": draft.fibreGrams = "0"
        case "effectiveDay": effectiveDay = try effectiveDay.addingDays(1, timeZoneIdentifier: zone)
        case "source": source = .userProvidedReference
        case "sourceNote": note = "updated synthetic source"
        case "timeZone": timeZoneIdentifier = "Europe/Paris"
        case "decimalSeparator": decimalSeparator = ","
        case "baseline":
            let legacy = PersistentGoalProfile(domain: try makeLegacy())
            baseline = GoalHistoryBaseline(versions: [], legacyRecords: [LegacyGoalBaseline(legacy)])
        case "numericFormatting": draft.energyKcal = "2100.0"
        case "noteWhitespace": note = " synthetic source "
        default: Issue.record("Unexpected payload mutation: \(field)")
        }
        let operationID = UUID()
        let confirmedAt = clock.addingTimeInterval(60)
        let changed = state.request(
            draft: draft, effectiveDay: effectiveDay, source: source, sourceNote: note,
            timeZoneIdentifier: timeZoneIdentifier, expectedBaseline: baseline, decimalSeparator: decimalSeparator,
            confirmedAt: confirmedAt, operationID: operationID
        )
        var confirmedCopy = draft
        confirmedCopy.isConfirmed = true
        #expect(changed.operationID == operationID)
        #expect(changed.operationID != first.operationID)
        #expect(changed.confirmedAt == confirmedAt)
        #expect(changed.draft == confirmedCopy)
        #expect(changed.effectiveDay == effectiveDay)
        #expect(changed.source == source)
        #expect(changed.sourceNote == note)
        #expect(changed.timeZoneIdentifier == timeZoneIdentifier)
        #expect(changed.decimalSeparator == decimalSeparator)
        #expect(changed.expectedBaseline == baseline)
        #expect(state.pendingRequest == changed)
        #expect(draft.isConfirmed == false)
    }

    @Test("Invalidation requires a new confirmation even when inputs return to their original values")
    func invalidateForcesFreshRequest() throws {
        var state = GoalFormSaveState()
        let first = state.request(
            draft: makeDraft(), effectiveDay: try day, source: .selfSelected, sourceNote: nil,
            timeZoneIdentifier: zone, expectedBaseline: emptyBaseline, decimalSeparator: ".",
            confirmedAt: clock, operationID: UUID()
        )
        state.invalidate()
        #expect(state.pendingRequest == nil)
        let operationID = UUID()
        let confirmedAt = clock.addingTimeInterval(60)
        let fresh = state.request(
            draft: makeDraft(), effectiveDay: try day, source: .selfSelected, sourceNote: nil,
            timeZoneIdentifier: zone, expectedBaseline: emptyBaseline, decimalSeparator: ".",
            confirmedAt: confirmedAt, operationID: operationID
        )
        #expect(fresh.operationID == operationID)
        #expect(fresh.operationID != first.operationID)
        #expect(fresh.confirmedAt == confirmedAt)
        #expect(fresh.draft.isConfirmed)
    }

    @Test("File-store failure preserves retry identity and an unrelated shared draft")
    func failureThenUnchangedRetryPreservesData() throws {
        try withFileStore { container in
            let old = try seedKnownGoal(in: container)
            let before = try GoalHistoryReader.read(container: container, day: day)
            let draft = makeDraft()
            var state = GoalFormSaveState()
            let first = state.request(
                draft: draft, effectiveDay: try day, source: .selfSelected, sourceNote: "synthetic source",
                timeZoneIdentifier: zone, expectedBaseline: before.baseline, decimalSeparator: ".",
                confirmedAt: clock, operationID: UUID()
            )
            container.mainContext.autosaveEnabled = false
            container.mainContext.insert(try makeMeal())
            var attemptedContext: ModelContext?
            #expect(throws: GoalVersionSaveCommandError.saveFailed) {
                try GoalVersionSaveCommand.save(request: first, container: container, now: clock, currentTimeZoneIdentifier: zone) { context in
                    attemptedContext = context
                    #expect(context !== container.mainContext)
                    #expect(context.autosaveEnabled == false)
                    throw BeforeCommit.injected
                }
            }
            #expect(attemptedContext?.hasChanges == false)
            #expect(container.mainContext.hasChanges)
            #expect(try GoalHistoryReader.read(container: container, day: day).baseline == before.baseline)
            #expect(try ModelContext(container).fetchCount(FetchDescriptor<PersistentMealLog>()) == 0)
            #expect(state.pendingRequest == first)
            #expect(draft.isConfirmed == false)
            let retry = state.request(
                draft: draft, effectiveDay: try day, source: .selfSelected, sourceNote: "synthetic source",
                timeZoneIdentifier: zone, expectedBaseline: before.baseline, decimalSeparator: ".",
                confirmedAt: clock.addingTimeInterval(60), operationID: UUID()
            )
            #expect(retry == first)
            let saved = try GoalVersionSaveCommand.save(request: retry, container: container, now: clock, currentTimeZoneIdentifier: zone)
            #expect(saved.id == first.operationID)
            #expect(saved.confirmedAt == first.confirmedAt)
            #expect(saved.commitSequence == 2)
            try attemptedContext?.save()
            let after = try GoalHistoryReader.read(container: container, day: day)
            #expect(after.versions == [old, saved])
            #expect(after.baseline.legacyRecords == before.baseline.legacyRecords)
            #expect(container.mainContext.hasChanges)
            #expect(try ModelContext(container).fetchCount(FetchDescriptor<PersistentMealLog>()) == 0)
        }
    }

    @Test("Editing after failure saves the new payload without waiting for invalidation", arguments: [
        "energy", "effectiveDay", "source", "sourceNote", "timeZone", "decimalSeparator"
    ])
    func editedFailureRetryUsesCurrentPayload(field: String) throws {
        try withFileStore { container in
            let old = try seedKnownGoal(in: container)
            let before = try GoalHistoryReader.read(container: container, day: day)
            var state = GoalFormSaveState()
            let first = state.request(
                draft: makeDraft(), effectiveDay: try day, source: .selfSelected, sourceNote: "synthetic source",
                timeZoneIdentifier: zone, expectedBaseline: before.baseline, decimalSeparator: ".",
                confirmedAt: clock, operationID: UUID()
            )
            #expect(throws: GoalVersionSaveCommandError.saveFailed) {
                try GoalVersionSaveCommand.save(request: first, container: container, now: clock, currentTimeZoneIdentifier: zone) { _ in
                    throw BeforeCommit.injected
                }
            }
            var draft = makeDraft()
            var effectiveDay = try day
            var source = GoalSource.selfSelected
            var note = "synthetic source"
            var timeZoneIdentifier = zone
            var decimalSeparator = "."
            var expectedEnergy = 2_100.0
            switch field {
            case "energy": draft.energyKcal = "2200"; expectedEnergy = 2_200
            case "effectiveDay": effectiveDay = try effectiveDay.addingDays(1, timeZoneIdentifier: zone)
            case "source": source = .userProvidedReference
            case "sourceNote": note = "updated synthetic source"
            case "timeZone": timeZoneIdentifier = "Europe/Paris"
            case "decimalSeparator": decimalSeparator = ","; draft.energyKcal = "2100,5"; expectedEnergy = 2_100.5
            default: Issue.record("Unexpected payload mutation: \(field)")
            }
            let operationID = UUID()
            let confirmedAt = clock.addingTimeInterval(60)
            // Deliberately do not call invalidate: this is the delayed-observer path.
            let edited = state.request(
                draft: draft, effectiveDay: effectiveDay, source: source, sourceNote: note,
                timeZoneIdentifier: timeZoneIdentifier, expectedBaseline: before.baseline, decimalSeparator: decimalSeparator,
                confirmedAt: confirmedAt, operationID: operationID
            )
            let saved = try GoalVersionSaveCommand.save(request: edited, container: container, now: confirmedAt, currentTimeZoneIdentifier: timeZoneIdentifier)
            #expect(saved.id == operationID)
            #expect(saved.id != first.operationID)
            #expect(saved.confirmedAt == confirmedAt)
            #expect(saved.effectiveDay == effectiveDay)
            #expect(saved.timeZoneIdentifier == timeZoneIdentifier)
            #expect(saved.source == source)
            #expect(saved.sourceNote == note)
            #expect(saved.profile.energyKcal == expectedEnergy)
            #expect(saved.profile.effectiveFrom == (try effectiveDay.start(in: timeZoneIdentifier)))
            #expect(saved.commitSequence == 2)
            #expect(draft.isConfirmed == false)
            let after = try GoalHistoryReader.read(container: container, day: effectiveDay)
            #expect(after.versions == [old, saved])
            #expect(after.selected == saved)
            #expect(after.baseline.legacyRecords == before.baseline.legacyRecords)
        }
    }

    private func makeDraft() -> GoalInputDraft {
        var draft = GoalInputDraft()
        draft.energyKcal = "2100"
        draft.proteinGrams = "140"
        draft.carbohydrateGrams = "200"
        draft.fatGrams = "60"
        draft.saturatedFatLimitGrams = "0"
        return draft
    }

    private func makeLegacy() throws -> GoalProfile {
        try GoalProfile(effectiveFrom: Date(timeIntervalSince1970: 1), energyKcal: 1_800, proteinGrams: 120, carbohydrateGrams: 180, fatGrams: 50)
    }

    private func seedKnownGoal(in container: ModelContainer) throws -> GoalVersion {
        let effectiveDay = try day
        let profile = try GoalProfile(effectiveFrom: effectiveDay.start(in: zone), energyKcal: 2_000, proteinGrams: 140, carbohydrateGrams: 200, fatGrams: 60)
        let version = try GoalVersion(profile: profile, effectiveDay: effectiveDay, source: .selfSelected,
            sourceNote: "existing synthetic source", confirmedAt: clock.addingTimeInterval(-3_600),
            timeZoneIdentifier: zone, commitSequence: 1)
        let context = ModelContext(container)
        context.autosaveEnabled = false
        context.insert(PersistentGoalProfile(domain: try makeLegacy()))
        context.insert(PersistentGoalVersion(domain: version))
        try context.save()
        return version
    }

    private func makeMeal() throws -> PersistentMealLog {
        PersistentMealLog(domain: try MealLog(title: "synthetic", entryMethod: .weighed, coverageStatus: .complete,
            components: [MealComponent(foodItemID: UUID(), foodName: "synthetic", consumedWeightGrams: 1, unit: "g", nutrients: .zero)]))
    }

    private func withFileStore(_ body: @MainActor (ModelContainer) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("goal-form-save-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        try autoreleasepool {
            let schema = Schema(versionedSchema: VersionedSchemaV2.self)
            let configuration = ModelConfiguration(schema: schema, url: directory.appendingPathComponent("synthetic.store"), cloudKitDatabase: .none)
            let container = try ModelContainer(for: schema, migrationPlan: ShiHengMigrationPlan.self, configurations: configuration)
            try body(container)
        }
    }

    private enum BeforeCommit: Error { case injected }
}
