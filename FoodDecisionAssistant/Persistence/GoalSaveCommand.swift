import FoodDecisionCore
import Foundation
import SwiftData

enum GoalHistoryReadError: Error, LocalizedError {
    case unreadable, ambiguousLegacy
    var errorDescription: String? {
        switch self {
        case .unreadable: "无法读取目标历史；原记录保留，未使用默认值或跳过异常版本。"
        case .ambiguousLegacy: "旧安装有多条不同的当前目标，无法确定使用哪条；原记录均保留。"
        }
    }
}

struct LegacyGoalBaseline: Equatable, Sendable {
    let id: UUID
    let effectiveFrom: Date
    let values: [Double?]
    init(_ row: PersistentGoalProfile) {
        id = row.id
        effectiveFrom = row.effectiveFrom
        values = [row.energyKcal, row.proteinGrams, row.carbohydrateGrams, row.fatGrams, row.saturatedFatLimitGrams, row.fibreGrams]
    }
    static func == (a: Self, b: Self) -> Bool {
        a.id == b.id && equalValues([a.effectiveFrom.timeIntervalSinceReferenceDate], [b.effectiveFrom.timeIntervalSinceReferenceDate]) && equalValues(a.values, b.values)
    }
    static func equalValues(_ a: [Double?], _ b: [Double?]) -> Bool {
        a.count == b.count && zip(a, b).allSatisfy { lhs, rhs in
            switch (lhs, rhs) {
            case (nil, nil): true
            case let (x?, y?): x == y || (x.isNaN && y.isNaN)
            default: false
            }
        }
    }
}

struct GoalHistoryBaseline: Equatable, Sendable {
    let versions: [GoalVersion]
    let legacyRecords: [LegacyGoalBaseline]
}
struct GoalHistorySnapshot: Sendable {
    let versions: [GoalVersion]
    let selected: GoalVersion?
    let legacyCurrent: GoalProfile?
    let baseline: GoalHistoryBaseline
    let hasLegacy: Bool
    let legacyNeedsConfirmation: Bool
    var currentProfile: GoalProfile? { selected?.profile ?? legacyCurrent }
}

@MainActor
enum GoalHistoryReader {
    static func read(container: ModelContainer, day: GoalDay, allowLegacyCurrent: Bool = false) throws -> GoalHistorySnapshot {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        do { return try read(context: context, day: day, allowLegacyCurrent: allowLegacyCurrent) }
        catch let error as GoalHistoryReadError { throw error }
        catch { throw GoalHistoryReadError.unreadable }
    }
    static func read(context: ModelContext, day: GoalDay, allowLegacyCurrent: Bool) throws -> GoalHistorySnapshot {
        let versions = try context.fetch(FetchDescriptor<PersistentGoalVersion>()).map { try $0.domainModel }
            .sorted { $0.commitSequence < $1.commitSequence }
        let selected = try GoalSelectionPolicy.v1.select(for: day, versions: versions)
        let legacy = try context.fetch(FetchDescriptor<PersistentGoalProfile>()).sorted { $0.id.uuidString < $1.id.uuidString }
        let rawLegacy = legacy.map(LegacyGoalBaseline.init)
        var current: GoalProfile?
        var needsConfirmation = false
        if allowLegacyCurrent, selected == nil, legacy.contains(where: { !$0.effectiveFrom.timeIntervalSinceReferenceDate.isFinite }) {
            needsConfirmation = true
        } else if allowLegacyCurrent, selected == nil, let latest = legacy.map(\.effectiveFrom).max() {
            let candidates = legacy.filter { $0.effectiveFrom == latest }
            if let first = candidates.first {
                if candidates.allSatisfy({ LegacyGoalBaseline.equalValues(LegacyGoalBaseline($0).values, LegacyGoalBaseline(first).values) }) {
                    current = try? first.domainModel
                    needsConfirmation = current == nil
                } else {
                    needsConfirmation = true
                }
            }
        }
        return GoalHistorySnapshot(versions: versions, selected: selected, legacyCurrent: current,
            baseline: GoalHistoryBaseline(versions: versions, legacyRecords: rawLegacy), hasLegacy: !legacy.isEmpty,
            legacyNeedsConfirmation: needsConfirmation)
    }
}

struct GoalVersionSaveRequest: Equatable, Sendable {
    let draft: GoalInputDraft
    let effectiveDay: GoalDay
    let source: GoalSource
    let sourceNote: String?
    let timeZoneIdentifier: String
    let confirmedAt: Date
    let operationID: UUID
    let expectedBaseline: GoalHistoryBaseline
    var decimalSeparator = "."
}

enum GoalVersionSaveCommandError: Error, Equatable, LocalizedError {
    case readFailed, baselineChanged, sharedGoalHasUnsavedChanges, operationConflict
    case saveFailed, dateInPast, timeZoneChanged, sequenceOverflow
    var errorDescription: String? {
        switch self {
        case .readFailed: "无法读取已提交目标，原记录与本次输入保留。"
        case .baselineChanged: "目标历史已被其他操作修改，请保留输入并重新打开核对后保存。"
        case .sharedGoalHasUnsavedChanges: "其他上下文有未保存的目标修改，请先处理；未提交或丢弃任何草稿。"
        case .operationConflict: "保存操作标识对应不同内容，未覆盖已有版本。"
        case .saveFailed: "目标保存失败，本次事务已回滚；原目标和本次输入保留。"
        case .dateInPast: "所选生效日期已成为过去，请重新选择今天或未来日期并确认；输入仍保留。"
        case .timeZoneChanged: "时区已变化，请核对生效日期并重新确认；输入仍保留。"
        case .sequenceOverflow: "目标版本序号无法继续增加，未写入任何数据。"
        }
    }
}

/// Official writes append a value snapshot in one synchronous MainActor transaction.
@MainActor
enum GoalVersionSaveCommand {
    @discardableResult
    static func save(request: GoalVersionSaveRequest, container: ModelContainer, now: Date = .now,
                     currentTimeZoneIdentifier: String = TimeZone.current.identifier,
                     saveContext: @MainActor (ModelContext) throws -> Void = { try $0.save() }) throws -> GoalVersion {
        let profile = try request.draft.validGoal(id: request.operationID,
            effectiveFrom: request.effectiveDay.start(in: request.timeZoneIdentifier), decimalSeparator: request.decimalSeparator)
        let context = ModelContext(container)
        context.autosaveEnabled = false
        do {
            let snapshot: GoalHistorySnapshot
            do { snapshot = try GoalHistoryReader.read(context: context, day: request.effectiveDay, allowLegacyCurrent: false) }
            catch { throw GoalVersionSaveCommandError.readFailed }
            if let existing = snapshot.versions.first(where: { $0.id == request.operationID }) {
                let retry = try makeVersion(request, profile: profile, sequence: existing.commitSequence)
                guard retry == existing else { throw GoalVersionSaveCommandError.operationConflict }
                return existing
            }
            guard snapshot.baseline == request.expectedBaseline else { throw GoalVersionSaveCommandError.baselineChanged }
            let shared = container.mainContext
            let changed = shared.insertedModelsArray + shared.changedModelsArray + shared.deletedModelsArray
            guard !changed.contains(where: { $0 is PersistentGoalVersion || $0 is PersistentGoalProfile }) else {
                throw GoalVersionSaveCommandError.sharedGoalHasUnsavedChanges
            }
            guard currentTimeZoneIdentifier == request.timeZoneIdentifier else { throw GoalVersionSaveCommandError.timeZoneChanged }
            let today = try GoalDay(containing: now, timeZoneIdentifier: currentTimeZoneIdentifier)
            guard request.effectiveDay >= today else { throw GoalVersionSaveCommandError.dateInPast }
            let lastSequence = snapshot.versions.map(\.commitSequence).max() ?? 0
            guard lastSequence < Int.max else { throw GoalVersionSaveCommandError.sequenceOverflow }
            let version = try makeVersion(request, profile: profile, sequence: lastSequence + 1)
            context.insert(PersistentGoalVersion(domain: version))
            try saveContext(context)
            return version
        } catch {
            context.rollback()
            if let known = error as? GoalVersionSaveCommandError { throw known }
            if let known = error as? GoalInputError { throw known }
            if let known = error as? DomainValidationError { throw known }
            if let known = error as? GoalHistoryError { throw known }
            throw GoalVersionSaveCommandError.saveFailed
        }
    }
    private static func makeVersion(_ request: GoalVersionSaveRequest, profile: GoalProfile, sequence: Int) throws -> GoalVersion {
        try GoalVersion(profile: profile, effectiveDay: request.effectiveDay, source: request.source,
            sourceNote: request.sourceNote, confirmedAt: request.confirmedAt,
            timeZoneIdentifier: request.timeZoneIdentifier, commitSequence: sequence)
    }
}
