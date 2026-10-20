import FoodDecisionCore
import Foundation
import SwiftData

private func mealEditBitsEqual(_ lhs: Double?, _ rhs: Double?) -> Bool {
    lhs?.bitPattern == rhs?.bitPattern
}

struct MealEditNutritionSnapshot: Equatable, Sendable {
    let energyKcal: Double
    let fatGrams: Double
    let saturatedFatGrams: Double
    let carbohydrateGrams: Double
    let sugarGrams: Double
    let proteinGrams: Double
    let saltGrams: Double
    let fibreGrams: Double?

    init(_ values: NutrientValues) {
        energyKcal = values.energyKcal; fatGrams = values.fatGrams
        saturatedFatGrams = values.saturatedFatGrams; carbohydrateGrams = values.carbohydrateGrams
        sugarGrams = values.sugarGrams; proteinGrams = values.proteinGrams
        saltGrams = values.saltGrams; fibreGrams = values.fibreGrams
    }
    @MainActor init(_ row: PersistentMealLog) {
        energyKcal = row.energyKcal; fatGrams = row.fatGrams
        saturatedFatGrams = row.saturatedFatGrams; carbohydrateGrams = row.carbohydrateGrams
        sugarGrams = row.sugarGrams; proteinGrams = row.proteinGrams
        saltGrams = row.saltGrams; fibreGrams = row.fibreGrams
    }
    @MainActor init(_ row: PersistentMealComponent) {
        energyKcal = row.energyKcal; fatGrams = row.fatGrams
        saturatedFatGrams = row.saturatedFatGrams; carbohydrateGrams = row.carbohydrateGrams
        sugarGrams = row.sugarGrams; proteinGrams = row.proteinGrams
        saltGrams = row.saltGrams; fibreGrams = row.fibreGrams
    }
    var domain: NutrientValues {
        get throws {
            try NutrientValues(energyKcal: energyKcal, fatGrams: fatGrams, saturatedFatGrams: saturatedFatGrams,
                carbohydrateGrams: carbohydrateGrams, sugarGrams: sugarGrams, proteinGrams: proteinGrams,
                saltGrams: saltGrams, fibreGrams: fibreGrams)
        }
    }
    static func == (a: Self, b: Self) -> Bool {
        zip([a.energyKcal, a.fatGrams, a.saturatedFatGrams, a.carbohydrateGrams, a.sugarGrams, a.proteinGrams, a.saltGrams, a.fibreGrams],
            [b.energyKcal, b.fatGrams, b.saturatedFatGrams, b.carbohydrateGrams, b.sugarGrams, b.proteinGrams, b.saltGrams, b.fibreGrams])
            .allSatisfy { mealEditBitsEqual($0, $1) }
    }
    @MainActor func apply(to row: PersistentMealLog) {
        row.energyKcal = energyKcal; row.fatGrams = fatGrams; row.saturatedFatGrams = saturatedFatGrams
        row.carbohydrateGrams = carbohydrateGrams; row.sugarGrams = sugarGrams; row.proteinGrams = proteinGrams
        row.saltGrams = saltGrams; row.fibreGrams = fibreGrams
    }
    @MainActor func apply(to row: PersistentMealComponent) {
        row.energyKcal = energyKcal; row.fatGrams = fatGrams; row.saturatedFatGrams = saturatedFatGrams
        row.carbohydrateGrams = carbohydrateGrams; row.sugarGrams = sugarGrams; row.proteinGrams = proteinGrams
        row.saltGrams = saltGrams; row.fibreGrams = fibreGrams
    }
}

struct MealEditComponentSnapshot: Equatable, Sendable {
    let id: UUID
    let foodItemID: UUID
    let foodName: String
    let consumedWeightGrams: Double
    let unit: String
    let nutrition: MealEditNutritionSnapshot
    var sortIndex: Int
    let mealID: UUID?

    @MainActor init(_ row: PersistentMealComponent) {
        id = row.id; foodItemID = row.foodItemID; foodName = row.foodName
        consumedWeightGrams = row.consumedWeightGrams; unit = row.unit
        nutrition = MealEditNutritionSnapshot(row); sortIndex = row.sortIndex; mealID = row.meal?.id
    }
    init(_ domain: MealComponent, sortIndex: Int, mealID: UUID) {
        id = domain.id; foodItemID = domain.foodItemID; foodName = domain.foodName
        consumedWeightGrams = domain.consumedWeightGrams; unit = domain.unit
        nutrition = MealEditNutritionSnapshot(domain.nutrients); self.sortIndex = sortIndex; self.mealID = mealID
    }
    func domainModel() throws -> MealComponent {
        try MealComponent(id: id, foodItemID: foodItemID, foodName: foodName,
            consumedWeightGrams: consumedWeightGrams, unit: unit, nutrients: nutrition.domain)
    }
    func hasSameContent(as other: Self) -> Bool {
        id == other.id && foodItemID == other.foodItemID && foodName == other.foodName
            && mealEditBitsEqual(consumedWeightGrams, other.consumedWeightGrams)
            && unit == other.unit && nutrition == other.nutrition
    }
    static func == (a: Self, b: Self) -> Bool {
        a.hasSameContent(as: b) && a.sortIndex == b.sortIndex && a.mealID == b.mealID
    }
}

struct MealEditSnapshot: Equatable, Sendable {
    let id: UUID
    var eatenAt: Date
    var title: String
    var consumedWeightGrams: Double
    var nutrition: MealEditNutritionSnapshot
    var entryMethodRawValue: String
    var coverageStatusRawValue: String
    var estimateEvidenceGradeRawValue: String
    let healthKitSyncVersion: Int
    var components: [MealEditComponentSnapshot]

    @MainActor init(_ meal: PersistentMealLog) {
        id = meal.id; eatenAt = meal.eatenAt; title = meal.title; consumedWeightGrams = meal.consumedWeightGrams
        nutrition = MealEditNutritionSnapshot(meal); entryMethodRawValue = meal.entryMethodRawValue
        coverageStatusRawValue = meal.coverageStatusRawValue; estimateEvidenceGradeRawValue = meal.estimateEvidenceGradeRawValue
        healthKitSyncVersion = meal.healthKitSyncVersion
        components = meal.components.map(MealEditComponentSnapshot.init).sorted {
            $0.sortIndex == $1.sortIndex ? $0.id.uuidString < $1.id.uuidString : $0.sortIndex < $1.sortIndex
        }
    }
    @MainActor static func capture(_ meal: PersistentMealLog) -> Self { Self(meal) }
    var nutrientSnapshot: NutrientValues { get throws { try nutrition.domain } }
    var evidenceGradeRawValue: String { estimateEvidenceGradeRawValue }
    func originalComponents() throws -> [MealComponent] { try components.map { try $0.domainModel() } }
    func originalComponent(id: UUID) throws -> MealComponent? {
        guard components.filter({ $0.id == id }).count <= 1 else { throw MealEditCommandError.invalidChanges }
        return try components.first { $0.id == id }?.domainModel()
    }
    static func == (a: Self, b: Self) -> Bool {
        a.id == b.id && mealEditBitsEqual(a.eatenAt.timeIntervalSinceReferenceDate, b.eatenAt.timeIntervalSinceReferenceDate)
            && a.title == b.title && mealEditBitsEqual(a.consumedWeightGrams, b.consumedWeightGrams)
            && a.nutrition == b.nutrition && a.entryMethodRawValue == b.entryMethodRawValue
            && a.coverageStatusRawValue == b.coverageStatusRawValue
            && a.estimateEvidenceGradeRawValue == b.estimateEvidenceGradeRawValue
            && a.healthKitSyncVersion == b.healthKitSyncVersion && a.components == b.components
    }
}

struct MealEditChanges: Sendable {
    var title: String?
    var eatenAt: Date?
    var entryMethod: MealEntryMethod?
    var coverageStatus: MealCoverageStatus?
    var components: [MealComponent]?
    init(title: String? = nil, eatenAt: Date? = nil, entryMethod: MealEntryMethod? = nil,
         coverageStatus: MealCoverageStatus? = nil, components: [MealComponent]? = nil) {
        self.title = title; self.eatenAt = eatenAt; self.entryMethod = entryMethod
        self.coverageStatus = coverageStatus; self.components = components
    }
}

enum MealEditCommandError: Error, Equatable, LocalizedError {
    case readFailed, mealUnavailable, baselineChanged, sharedMealHasUnsavedChanges
    case invalidChanges, componentIDConflict, saveFailed, savedButRefreshFailed
    var errorDescription: String? {
        switch self {
        case .readFailed: "无法读取原餐食，原记录和本次输入仍保留。"
        case .mealUnavailable: "原餐食已不存在，未新建或替换其他记录。"
        case .baselineChanged: "餐食已被其他操作修改，请保留输入并重新核对后保存。"
        case .sharedMealHasUnsavedChanges: "此餐食还有未保存的修改，请先处理；原记录和本次输入仍保留。"
        case .invalidChanges: "本次修改无法安全保存，请检查餐名、时间及每个分项。旧异常记录和输入仍保留。"
        case .componentIDConflict: "分项编号已用于其他记录，未覆盖原分项。"
        case .saveFailed: "未能确认餐食保存完成，请重试；本次输入仍保留，不会重复应用重量调整。"
        case .savedButRefreshFailed: "餐食已保存，但当前页面未能刷新。输入仍保留；重试会核对已保存内容，不会重复保存。"
        }
    }
}

@MainActor
enum MealEditCommand {
    @discardableResult
    static func save(baseline: MealEditSnapshot, changes: MealEditChanges,
                     refreshContext: @MainActor (ModelContext, Set<UUID>, UUID) throws -> Void = { context, childIDs, mealID in
                         try refreshSharedModels(in: context, childIDs: childIDs, mealID: mealID)
                     },
                     in container: ModelContainer,
                     saveContext: @MainActor (ModelContext) throws -> Void = { try $0.save() }) throws -> MealEditSnapshot {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        do {
            let target = try targetSnapshot(baseline: baseline, changes: changes)
            let touchedIDs = Set(baseline.components.map(\.id) + target.components.map(\.id))
            let shared = container.mainContext
            let dirty = shared.insertedModelsArray + shared.changedModelsArray + shared.deletedModelsArray
            guard !dirty.contains(where: { model in
                if let meal = model as? PersistentMealLog { return meal.id == baseline.id }
                if let component = model as? PersistentMealComponent {
                    return component.meal?.id == baseline.id || touchedIDs.contains(component.id)
                }
                return false
            }) else { throw MealEditCommandError.sharedMealHasUnsavedChanges }
            let id = baseline.id
            let descriptor = FetchDescriptor<PersistentMealLog>(predicate: #Predicate { $0.id == id })
            let found: [PersistentMealLog]
            do { found = try context.fetch(descriptor) } catch { throw MealEditCommandError.readFailed }
            guard found.count == 1, let meal = found.first else { throw MealEditCommandError.mealUnavailable }
            let current = MealEditSnapshot(meal)
            if current == target {
                do { try refreshContext(shared, touchedIDs, baseline.id) }
                catch { throw MealEditCommandError.savedButRefreshFailed }
                return current
            }
            guard current == baseline else { throw MealEditCommandError.baselineChanged }
            let oldIDs = Set(current.components.map(\.id))
            let newIDs = Set(target.components.map(\.id)).subtracting(oldIDs)
            if !newIDs.isEmpty {
                let existing: [PersistentMealComponent]
                do { existing = try context.fetch(FetchDescriptor<PersistentMealComponent>()) }
                catch { throw MealEditCommandError.readFailed }
                guard !existing.contains(where: { newIDs.contains($0.id) }) else { throw MealEditCommandError.componentIDConflict }
            }
            try apply(target, from: current, to: meal, context: context)
            do { try saveContext(context) } catch { throw MealEditCommandError.saveFailed }
            do { try refreshContext(shared, touchedIDs, baseline.id) }
            catch { throw MealEditCommandError.savedButRefreshFailed }
            return target
        } catch {
            // The store already contains the exact target in this category. Do
            // not report or attempt to undo that committed save on a read error.
            if error as? MealEditCommandError == .savedButRefreshFailed { throw error }
            context.rollback()
            if let known = error as? MealEditCommandError { throw known }
            throw MealEditCommandError.invalidChanges
        }
    }

    private static func refreshSharedModels(in context: ModelContext, childIDs: Set<UUID>, mealID: UUID) throws {
        // A parent fetch alone can leave an already-read child object stale. Read
        // each touched child first, without including or committing shared drafts.
        for id in childIDs.sorted(by: { $0.uuidString < $1.uuidString }) {
            var descriptor = FetchDescriptor<PersistentMealComponent>(predicate: #Predicate { $0.id == id })
            descriptor.includePendingChanges = false
            _ = try context.fetch(descriptor)
        }
        var descriptor = FetchDescriptor<PersistentMealLog>(predicate: #Predicate { $0.id == mealID })
        descriptor.includePendingChanges = false
        _ = try context.fetch(descriptor)
    }

    private static func targetSnapshot(baseline: MealEditSnapshot, changes: MealEditChanges) throws -> MealEditSnapshot {
        var target = baseline
        if let title = changes.title {
            let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { throw MealEditCommandError.invalidChanges }
            target.title = trimmed
        }
        if let date = changes.eatenAt {
            guard date.timeIntervalSinceReferenceDate.isFinite else { throw MealEditCommandError.invalidChanges }
            target.eatenAt = date
        }
        if let method = changes.entryMethod, method.rawValue != baseline.entryMethodRawValue {
            guard let grade = EstimateEvidenceGrade(rawValue: baseline.estimateEvidenceGradeRawValue), grade != .d else {
                throw MealEditCommandError.invalidChanges
            }
            target.entryMethodRawValue = method.rawValue
            target.estimateEvidenceGradeRawValue = method.evidenceGrade.rawValue
        }
        if let coverage = changes.coverageStatus { target.coverageStatusRawValue = coverage.rawValue }
        if let requested = changes.components {
            guard Set(requested.map(\.id)).count == requested.count else { throw MealEditCommandError.invalidChanges }
            guard Set(baseline.components.map(\.id)).count == baseline.components.count else { throw MealEditCommandError.invalidChanges }
            let oldByID = Dictionary(uniqueKeysWithValues: baseline.components.map { ($0.id, $0) })
            var contentsChanged = Set(requested.map(\.id)) != Set(oldByID.keys)
            let retained = requested.compactMap { oldByID[$0.id] }
            let retainedInOriginalOrder = baseline.components.filter { Set(retained.map(\.id)).contains($0.id) }
            let oldOrderKept = retained.map(\.id) == retainedInOriginalOrder.map(\.id)
            var previousIndex: Int?
            var projected: [MealEditComponentSnapshot] = []
            var needsRenumbering = !oldOrderKept
            for value in requested {
                let old = oldByID[value.id]
                let index: Int
                if let old { index = old.sortIndex }
                else if let previousIndex, previousIndex < Int.max { index = previousIndex + 1 }
                else if previousIndex == nil { index = 0 }
                else { index = 0; needsRenumbering = true }
                let candidate = MealEditComponentSnapshot(value, sortIndex: index, mealID: baseline.id)
                if old?.hasSameContent(as: candidate) != true { contentsChanged = true }
                if let previousIndex, index <= previousIndex, oldByID[value.id] == nil || !oldOrderKept { needsRenumbering = true }
                projected.append(candidate); previousIndex = index
            }
            // Insertion between adjacent/tied stored indices also requires an explicit new order.
            for pair in zip(projected, projected.dropFirst()) {
                if pair.0.sortIndex > pair.1.sortIndex
                    || (pair.0.sortIndex == pair.1.sortIndex
                        && (oldByID[pair.0.id] == nil || oldByID[pair.1.id] == nil
                            || pair.0.id.uuidString > pair.1.id.uuidString)) { needsRenumbering = true }
            }
            if needsRenumbering { for index in projected.indices { projected[index].sortIndex = index } }
            target.components = projected
            if contentsChanged {
                guard let method = MealEntryMethod(rawValue: target.entryMethodRawValue),
                      let coverage = MealCoverageStatus(rawValue: target.coverageStatusRawValue),
                      let grade = EstimateEvidenceGrade(rawValue: target.estimateEvidenceGradeRawValue), grade != .d else {
                    throw MealEditCommandError.invalidChanges
                }
                var weight = 0.0
                for component in requested { weight += component.consumedWeightGrams }
                let nutrients = try NutrientValues.sum(requested.map(\.nutrients))
                _ = try MealLog(id: target.id, eatenAt: target.eatenAt, title: target.title,
                    consumedWeightGrams: weight, nutrients: nutrients, entryMethod: method,
                    coverageStatus: coverage, estimateEvidenceGrade: grade,
                    healthKitSyncVersion: target.healthKitSyncVersion, components: requested)
                target.consumedWeightGrams = weight; target.nutrition = MealEditNutritionSnapshot(nutrients)
            }
        }
        // A method change can explicitly raise C to A/B, but cannot make an otherwise
        // invalid legacy record appear formal merely by replacing its grade string.
        if target.entryMethodRawValue != baseline.entryMethodRawValue {
            guard let method = MealEntryMethod(rawValue: target.entryMethodRawValue),
                  let coverage = MealCoverageStatus(rawValue: target.coverageStatusRawValue),
                  let grade = EstimateEvidenceGrade(rawValue: target.estimateEvidenceGradeRawValue) else {
                throw MealEditCommandError.invalidChanges
            }
            _ = try MealLog(id: target.id, eatenAt: target.eatenAt, title: target.title,
                consumedWeightGrams: target.consumedWeightGrams, nutrients: target.nutrientSnapshot,
                entryMethod: method, coverageStatus: coverage, estimateEvidenceGrade: grade,
                healthKitSyncVersion: target.healthKitSyncVersion, components: target.originalComponents())
        }
        return target
    }

    private static func apply(_ target: MealEditSnapshot, from old: MealEditSnapshot,
                              to meal: PersistentMealLog, context: ModelContext) throws {
        if target.title != old.title { meal.title = target.title }
        if !mealEditBitsEqual(target.eatenAt.timeIntervalSinceReferenceDate, old.eatenAt.timeIntervalSinceReferenceDate) { meal.eatenAt = target.eatenAt }
        if !mealEditBitsEqual(target.consumedWeightGrams, old.consumedWeightGrams) { meal.consumedWeightGrams = target.consumedWeightGrams }
        if target.nutrition != old.nutrition { target.nutrition.apply(to: meal) }
        if target.entryMethodRawValue != old.entryMethodRawValue { meal.entryMethodRawValue = target.entryMethodRawValue }
        if target.coverageStatusRawValue != old.coverageStatusRawValue { meal.coverageStatusRawValue = target.coverageStatusRawValue }
        if target.estimateEvidenceGradeRawValue != old.estimateEvidenceGradeRawValue { meal.estimateEvidenceGradeRawValue = target.estimateEvidenceGradeRawValue }
        guard target.components != old.components else { return }
        let existing = Dictionary(uniqueKeysWithValues: meal.components.map { ($0.id, $0) })
        let desiredIDs = Set(target.components.map(\.id))
        for row in meal.components where !desiredIDs.contains(row.id) { context.delete(row) }
        for value in target.components {
            if let row = existing[value.id] {
                let before = MealEditComponentSnapshot(row)
                if !before.hasSameContent(as: value) {
                    row.foodItemID = value.foodItemID; row.foodName = value.foodName
                    row.consumedWeightGrams = value.consumedWeightGrams; row.unit = value.unit
                    value.nutrition.apply(to: row)
                }
                if row.sortIndex != value.sortIndex { row.sortIndex = value.sortIndex }
            } else {
                // Domain validity was checked while building the target. No stored old row is
                // reconstructed through a domain initializer, including metadata-only changes.
                let domain = try value.domainModel()
                let row = PersistentMealComponent(domain: domain, sortIndex: value.sortIndex)
                context.insert(row); row.meal = meal
            }
        }
    }
}
