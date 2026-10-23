import FoodDecisionCore
import Foundation
import SwiftData

/// A frozen attempt, including identities and the time used for template usage.
/// Retrying this value must never create a second meal or count a template twice.
struct MealCreateRequest: Equatable, Sendable {
    let meal: MealLog
    let sourceTemplateID: UUID?
    let templateUsedAt: Date
}

enum MealCreateCommandError: Error, Equatable, LocalizedError {
    case invalidRequest, readFailed, mealIDConflict, componentIDConflict
    case sharedModelsHaveUnsavedChanges, invalidSourceTemplate
    case saveFailed, savedButRefreshFailed

    var errorDescription: String? {
        switch self {
        case .invalidRequest: "本次餐食无法安全保存，请检查餐名、时间和全部食物分项；输入仍保留。"
        case .readFailed: "无法核对已保存记录，已有数据和本次输入仍保留，请重试。"
        case .mealIDConflict: "餐食编号已对应其他内容，未覆盖已有餐食；本次输入仍保留。"
        case .componentIDConflict: "食物分项编号已用于其他记录，未覆盖已有分项；本次输入仍保留。"
        case .sharedModelsHaveUnsavedChanges: "相关食品、餐食或模板还有未保存的修改，请先处理；未提交或丢弃其他草稿。"
        case .invalidSourceTemplate: "来源模板数据异常或使用次数已达上限，本次餐食未保存；已有数据和输入仍保留。"
        case .saveFailed: "未能确认餐食保存完成，本次输入仍保留。请重试核对同一次结果，避免重复记餐。"
        case .savedButRefreshFailed: "餐食已保存，但当前页面未能刷新。输入仍保留；重试会核对同一次结果，不会重复记餐。"
        }
    }
}

/// Saves a new meal and its optional template usage in one private transaction.
/// The main context is read only: unrelated drafts are never saved or rolled back.
@MainActor
enum MealCreateCommand {
    @discardableResult
    static func save(
        request: MealCreateRequest,
        in container: ModelContainer,
        saveContext: @MainActor (ModelContext) throws -> Void = { try $0.save() },
        refreshContext: @MainActor (ModelContext, MealCreateRequest) throws -> Void = { context, request in
            try refreshSharedModels(in: context, request: request)
        }
    ) throws -> MealLog {
        try validate(request)
        let context = ModelContext(container)
        context.autosaveEnabled = false
        do {
            let mealID = request.meal.id
            let meals: [PersistentMealLog]
            let template: PersistentMealTemplate?
            do {
                meals = try context.fetch(FetchDescriptor<PersistentMealLog>(predicate: #Predicate { $0.id == mealID }))
                if let templateID = request.sourceTemplateID {
                    let found = try context.fetch(FetchDescriptor<PersistentMealTemplate>(predicate: #Predicate { $0.id == templateID }))
                    guard found.count <= 1 else { throw MealCreateCommandError.invalidSourceTemplate }
                    template = found.first
                } else {
                    template = nil
                }
            } catch let known as MealCreateCommandError {
                throw known
            } catch {
                throw MealCreateCommandError.readFailed
            }

            try rejectRelatedSharedDrafts(request: request, template: template, in: container.mainContext)
            guard meals.count <= 1 else { throw MealCreateCommandError.mealIDConflict }
            if let existing = meals.first {
                guard matches(existing, request.meal) else { throw MealCreateCommandError.mealIDConflict }
                // A preceding save may have committed before its caller observed
                // success. Its template usage is already part of that transaction.
                try refresh(request: request, context: container.mainContext, using: refreshContext)
                return request.meal
            }

            // Do not rely on SwiftData's unique-attribute upsert: a child ID can
            // already belong to another meal, or to a retained orphan row.
            for componentID in request.meal.components.map(\.id) {
                let found: [PersistentMealComponent]
                do {
                    found = try context.fetch(FetchDescriptor<PersistentMealComponent>(predicate: #Predicate { $0.id == componentID }))
                } catch {
                    throw MealCreateCommandError.readFailed
                }
                guard found.isEmpty else { throw MealCreateCommandError.componentIDConflict }
            }

            // A removed template does not invalidate the already-selected meal.
            // An existing, corrupt template must fail before anything commits.
            if let template {
                do { try template.markUsed(at: request.templateUsedAt) }
                catch { throw MealCreateCommandError.invalidSourceTemplate }
            }
            context.insert(PersistentMealLog(domain: request.meal))
            do { try saveContext(context) }
            catch { throw MealCreateCommandError.saveFailed }
            try refresh(request: request, context: container.mainContext, using: refreshContext)
            return request.meal
        } catch {
            // Refresh cannot undo an already committed transaction. An ambiguous
            // save error can also be retried by the same immutable request/ID.
            if error as? MealCreateCommandError == .savedButRefreshFailed { throw error }
            context.rollback()
            if let known = error as? MealCreateCommandError { throw known }
            throw MealCreateCommandError.saveFailed
        }
    }

    private static func validate(_ request: MealCreateRequest) throws {
        do {
            guard request.templateUsedAt.timeIntervalSinceReferenceDate.isFinite else {
                throw MealCreateCommandError.invalidRequest
            }
            let meal = request.meal
            _ = try MealLog(id: meal.id, eatenAt: meal.eatenAt, title: meal.title,
                consumedWeightGrams: meal.consumedWeightGrams, nutrients: meal.nutrients,
                entryMethod: meal.entryMethod, coverageStatus: meal.coverageStatus,
                estimateEvidenceGrade: meal.estimateEvidenceGrade,
                healthKitSyncVersion: meal.healthKitSyncVersion, components: meal.components)
        } catch {
            throw MealCreateCommandError.invalidRequest
        }
    }

    private static func rejectRelatedSharedDrafts(
        request: MealCreateRequest, template: PersistentMealTemplate?, in context: ModelContext
    ) throws {
        let componentIDs = Set(request.meal.components.map(\.id))
        let foodIDs = Set(request.meal.components.map(\.foodItemID))
        // Fetching the saved template in the private context retains these IDs
        // even when a shared draft has detached/deleted one of its child rows.
        let templateComponentIDs = Set(template?.components.map(\.id) ?? [])
        let pending = context.insertedModelsArray + context.changedModelsArray + context.deletedModelsArray
        guard !pending.contains(where: { model in
            if let food = model as? PersistentFoodItem { return foodIDs.contains(food.id) }
            if let meal = model as? PersistentMealLog { return meal.id == request.meal.id }
            if let component = model as? PersistentMealComponent {
                return component.meal?.id == request.meal.id || componentIDs.contains(component.id)
            }
            if let template = model as? PersistentMealTemplate { return template.id == request.sourceTemplateID }
            if let component = model as? PersistentMealTemplateComponent {
                return templateComponentIDs.contains(component.id)
                    || (request.sourceTemplateID != nil && component.template?.id == request.sourceTemplateID)
            }
            return false
        }) else { throw MealCreateCommandError.sharedModelsHaveUnsavedChanges }
    }

    private static func matches(_ row: PersistentMealLog, _ meal: MealLog) -> Bool {
        // Domain conversion intentionally normalizes titles. Compare the stored
        // fields directly instead, including exact numeric snapshots and order.
        let storedComponents = row.components.map(MealEditComponentSnapshot.init).sorted { $0.sortIndex < $1.sortIndex }
        let requestedComponents = meal.components.enumerated().map {
            MealEditComponentSnapshot($0.element, sortIndex: $0.offset, mealID: meal.id)
        }
        return row.id == meal.id && row.title == meal.title
            && row.eatenAt.timeIntervalSinceReferenceDate.bitPattern == meal.eatenAt.timeIntervalSinceReferenceDate.bitPattern
            && row.consumedWeightGrams.bitPattern == meal.consumedWeightGrams.bitPattern
            && MealEditNutritionSnapshot(row) == MealEditNutritionSnapshot(meal.nutrients)
            && row.entryMethodRawValue == meal.entryMethod.rawValue
            && row.coverageStatusRawValue == meal.coverageStatus.rawValue
            && row.estimateEvidenceGradeRawValue == meal.estimateEvidenceGrade.rawValue
            && row.healthKitSyncVersion == meal.healthKitSyncVersion
            && storedComponents == requestedComponents
    }

    private static func refresh(
        request: MealCreateRequest, context: ModelContext,
        using refreshContext: @MainActor (ModelContext, MealCreateRequest) throws -> Void
    ) throws {
        do { try refreshContext(context, request) }
        catch { throw MealCreateCommandError.savedButRefreshFailed }
    }

    private static func refreshSharedModels(in context: ModelContext, request: MealCreateRequest) throws {
        for componentID in request.meal.components.map(\.id) {
            var descriptor = FetchDescriptor<PersistentMealComponent>(predicate: #Predicate { $0.id == componentID })
            descriptor.includePendingChanges = false
            _ = try context.fetch(descriptor)
        }
        let mealID = request.meal.id
        var mealDescriptor = FetchDescriptor<PersistentMealLog>(predicate: #Predicate { $0.id == mealID })
        mealDescriptor.includePendingChanges = false
        _ = try context.fetch(mealDescriptor)
        if let templateID = request.sourceTemplateID {
            var descriptor = FetchDescriptor<PersistentMealTemplate>(predicate: #Predicate { $0.id == templateID })
            descriptor.includePendingChanges = false
            _ = try context.fetch(descriptor)
        }
    }
}
