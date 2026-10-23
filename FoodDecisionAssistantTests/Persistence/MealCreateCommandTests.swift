import FoodDecisionCore
import Foundation
import SwiftData
import Testing
@testable import FoodDecisionAssistant

@MainActor
struct MealCreateCommandTests {
    private let clock = Date(timeIntervalSince1970: 1_792_713_600)

    @Test("Formal form-to-command saves every snapshot field, identity and order across a file-store reopen", arguments: [false, true])
    func formalCreatePersistsSnapshots(knownZeroFibre: Bool) throws {
        let url = try temporaryDirectory().appendingPathComponent("create.store")
        let request = try autoreleasepool {
            let c = try container(url: url)
            let first = PersistentFoodItem(domain: try food(fibre: knownZeroFibre ? 0 : nil))
            let second = PersistentFoodItem(domain: try food(name: "synthetic second", fibre: 0))
            c.mainContext.insert(first); c.mainContext.insert(second); try c.mainContext.save()
            let rows = [row(food: first, weight: "150"), row(food: second, weight: "50")]
            var state = MealCreateFormSaveState()
            let request = try state.request(title: "  synthetic meal  ", eatenAt: clock,
                entryMethod: .weighed, coverageStatus: .partial, rows: rows, foods: [first, second], templateUsedAt: clock)
            let saved = try MealCreateCommand.save(request: request, in: c)
            #expect(saved == request.meal)
            #expect(saved.title == "synthetic meal")
            #expect(saved.consumedWeightGrams == 200)
            #expect(saved.nutrients.energyKcal == 400)
            #expect(saved.components[0].nutrients.energyKcal == 300)
            #expect(saved.components[0].nutrients.fatGrams == 15)
            #expect(saved.components[0].nutrients.saturatedFatGrams == 3)
            #expect(saved.components[0].nutrients.carbohydrateGrams == 30)
            #expect(saved.components[0].nutrients.sugarGrams == 6)
            #expect(saved.components[0].nutrients.proteinGrams == 7.5)
            #expect(abs(saved.components[0].nutrients.saltGrams - 0.3) < 1e-12)
            #expect(saved.nutrients.fibreGrams == (knownZeroFibre ? 0 : nil))
            #expect(saved.components.map(\.id) == rows.map(\.id))
            #expect(saved.components.map(\.foodItemID) == [first.id, second.id])
            #expect(saved.estimateEvidenceGrade == .a)
            #expect(saved.healthKitSyncVersion == 1)
            #expect(try persisted(c, id: saved.id).domainModel() == saved)
            return request
        }
        try autoreleasepool {
            let reopened = try container(url: url)
            let stored = try persisted(reopened, id: request.meal.id)
            #expect(try stored.domainModel() == request.meal)
            #expect(stored.components.sorted { $0.sortIndex < $1.sortIndex }.map(\.id) == request.meal.components.map(\.id))
            #expect(stored.components.allSatisfy { $0.meal?.id == request.meal.id })
        }
    }

    @Test("Template counting is atomic, immediately refreshes held main-context models and is not repeated", arguments: [false, true])
    func templateUseOnceAndRefresh(disk: Bool) throws {
        let url = try disk ? temporaryDirectory().appendingPathComponent("template.store") : nil
        let c = try container(url: url)
        let template = try seedTemplate(c)
        let beforeChildren = template.components.map(\.id)
        let request = try request(sourceTemplateID: template.id)
        var saveCount = 0
        let saved = try MealCreateCommand.save(request: request, in: c, saveContext: { context in
            saveCount += 1
            #expect(context !== c.mainContext)
            #expect(context.autosaveEnabled == false)
            try context.save()
        })
        // Inspect the already-held object before another fetch can hide a stale cache.
        #expect(template.useCount == 6)
        #expect(template.lastUsedAt == clock)
        #expect(template.components.map(\.id) == beforeChildren)
        let retry = try MealCreateCommand.save(request: request, in: c, saveContext: { _ in
            saveCount += 1; throw Injected.beforeCommit
        })
        #expect(retry == saved)
        #expect(saveCount == 1)
        #expect(try counts(c) == [1, request.meal.components.count])
        let storedTemplate = try fetchTemplate(c, id: template.id)
        #expect(storedTemplate.useCount == 6)
        #expect(storedTemplate.lastUsedAt == clock)
        #expect(storedTemplate.updatedAt == template.updatedAt)
        #expect(c.mainContext.hasChanges == false)
    }

    @Test("A source template that no longer exists does not prevent recording the meal")
    func missingSourceTemplateIsAllowed() throws {
        let c = try container()
        let request = try request(sourceTemplateID: UUID())
        #expect(try MealCreateCommand.save(request: request, in: c) == request.meal)
        #expect(try counts(c) == [1, 1])
        #expect(try ModelContext(c).fetchCount(FetchDescriptor<PersistentMealTemplate>()) == 0)
    }

    @Test("A damaged or overflowed source template refuses the whole meal", arguments: ["negativeCount", "overflow", "emptyName", "invalidChildUnit", "invalidChildWeight"])
    func invalidTemplateIsAtomic(issue: String) throws {
        let c = try container(); let template = try seedTemplate(c)
        switch issue {
        case "negativeCount": template.useCount = -1
        case "overflow": template.useCount = Int.max
        case "emptyName": template.name = " "
        case "invalidChildUnit": template.components[0].unit = "ml"
        default: template.components[0].defaultWeightGrams = -1
        }
        try c.mainContext.save()
        let beforeCount = template.useCount, beforeTime = template.lastUsedAt
        #expect(throws: MealCreateCommandError.invalidSourceTemplate) {
            try MealCreateCommand.save(request: request(sourceTemplateID: template.id), in: c)
        }
        #expect(try counts(c) == [0, 0])
        let stored = try fetchTemplate(c, id: template.id)
        #expect(stored.useCount == beforeCount)
        #expect(stored.lastUsedAt == beforeTime)
    }

    @Test("An existing meal UUID with different content is never overwritten")
    func mealIdentityCollisionIsNotAnUpsert() throws {
        let c = try container(); let first = try request()
        _ = try MealCreateCommand.save(request: first, in: c)
        let conflicting = try request(id: first.meal.id, title: "different payload")
        #expect(throws: MealCreateCommandError.mealIDConflict) {
            try MealCreateCommand.save(request: conflicting, in: c)
        }
        #expect(try persisted(c, id: first.meal.id).domainModel() == first.meal)
        #expect(try counts(c) == [1, 1])
    }

    @Test("A component UUID belonging to another meal never moves or overwrites that component")
    func foreignComponentCollisionIsNotAnUpsert() throws {
        let c = try container(); let first = try request()
        _ = try MealCreateCommand.save(request: first, in: c)
        let conflicting = try request(childID: first.meal.components[0].id)
        #expect(throws: MealCreateCommandError.componentIDConflict) {
            try MealCreateCommand.save(request: conflicting, in: c)
        }
        #expect(try persisted(c, id: first.meal.id).domainModel() == first.meal)
        #expect(try counts(c) == [1, 1])
    }

    @Test("An apparent retry with unchanged metadata refuses differing archived component values or order", arguments: [false, true])
    func componentSnapshotCollisionIsNotRepaired(reorder: Bool) throws {
        let c = try container()
        let a = try MealComponent(foodItem: food(name: "first synthetic"), consumedWeightGrams: 100)
        let b = try MealComponent(foodItem: food(name: "second synthetic"), consumedWeightGrams: 50)
        let meal = try MealLog(eatenAt: clock, title: "synthetic meal", entryMethod: .weighed,
            coverageStatus: .complete, components: [a, b])
        let request = MealCreateRequest(meal: meal, sourceTemplateID: nil, templateUsedAt: clock)
        _ = try MealCreateCommand.save(request: request, in: c)
        let id = meal.id
        let stored = try #require(c.mainContext.fetch(FetchDescriptor<PersistentMealLog>(predicate: #Predicate { $0.id == id })).first)
        if reorder {
            for child in stored.components { child.sortIndex = child.id == a.id ? 1 : 0 }
        } else {
            let first = try #require(stored.components.first { $0.id == a.id })
            first.energyKcal += 1
        }
        try c.mainContext.save()
        let before = MealEditSnapshot(stored)
        #expect(throws: MealCreateCommandError.mealIDConflict) {
            try MealCreateCommand.save(request: request, in: c)
        }
        #expect(MealEditSnapshot(try persisted(c, id: id)) == before)
        #expect(try counts(c) == [1, 2])
    }

    @Test("A committed create whose page refresh fails retries reads only and retains an unrelated draft")
    func committedRefreshFailureDoesNotRecordAgain() throws {
        let c = try container(); let template = try seedTemplate(c)
        let request = try request(sourceTemplateID: template.id)
        let unrelated = PersistentContainerProfile(domain: try ContainerProfile(name: "shared draft", tareWeightGrams: 123))
        c.mainContext.insert(unrelated)
        var saves = 0, refreshes = 0
        let failingRefresh: @MainActor (ModelContext, MealCreateRequest) throws -> Void = { context, value in
            #expect(context === c.mainContext)
            #expect(value == request)
            refreshes += 1
            throw Injected.refreshRead
        }
        for _ in 0..<2 {
            #expect(throws: MealCreateCommandError.savedButRefreshFailed) {
                try MealCreateCommand.save(request: request, in: c, saveContext: { context in
                    saves += 1; try context.save()
                }, refreshContext: failingRefresh)
            }
        }
        #expect(saves == 1)
        #expect(refreshes == 2)
        #expect(c.mainContext.hasChanges)
        #expect(try ModelContext(c).fetchCount(FetchDescriptor<PersistentContainerProfile>()) == 0)
        #expect(try counts(c) == [1, 1])
        #expect(try fetchTemplate(c, id: template.id).useCount == 6)
        #expect(try MealCreateCommand.save(request: request, in: c) == request.meal)
        #expect(template.useCount == 6)
        #expect(c.mainContext.hasChanges)
        #expect(unrelated.name == "shared draft")
    }

    @Test("A save that commits and then throws is safely retried without a second meal or template use")
    func ambiguousCommitRetriesSameIdentity() throws {
        let c = try container(); let template = try seedTemplate(c)
        let request = try request(sourceTemplateID: template.id)
        var saves = 0
        #expect(throws: MealCreateCommandError.saveFailed) {
            try MealCreateCommand.save(request: request, in: c, saveContext: { context in
                saves += 1
                try context.save()
                throw Injected.beforeCommit
            })
        }
        #expect(try counts(c) == [1, 1])
        #expect(try fetchTemplate(c, id: template.id).useCount == 6)
        let retry = try MealCreateCommand.save(request: request, in: c, saveContext: { _ in
            saves += 1; throw Injected.beforeCommit
        })
        #expect(retry == request.meal)
        #expect(saves == 1)
        #expect(template.useCount == 6)
        #expect(template.lastUsedAt == clock)
        #expect(try counts(c) == [1, 1])
    }

    @Test("Pending insertion, modification or deletion of a selected food is never formalized", arguments: ["insert", "modify", "delete"])
    func selectedFoodPendingWorkIsProtected(kind: String) throws {
        let c = try container()
        let source = PersistentFoodItem(domain: try food())
        if kind != "insert" { c.mainContext.insert(source); try c.mainContext.save() }
        let component = try MealComponent(foodItem: source.domainModel, consumedWeightGrams: 150)
        let request = MealCreateRequest(meal: try MealLog(eatenAt: clock, title: "synthetic meal",
            entryMethod: .weighed, coverageStatus: .complete, components: [component]),
            sourceTemplateID: nil, templateUsedAt: clock)
        switch kind {
        case "insert": c.mainContext.insert(source)
        case "modify": source.energyKcalPer100Units = 999
        default: c.mainContext.delete(source)
        }
        let inserted = Set(c.mainContext.insertedModelsArray.map(\.persistentModelID))
        let changed = Set(c.mainContext.changedModelsArray.map(\.persistentModelID))
        let deleted = Set(c.mainContext.deletedModelsArray.map(\.persistentModelID))
        #expect(throws: MealCreateCommandError.sharedModelsHaveUnsavedChanges) {
            try MealCreateCommand.save(request: request, in: c)
        }
        #expect(c.mainContext.hasChanges)
        #expect(Set(c.mainContext.insertedModelsArray.map(\.persistentModelID)) == inserted)
        #expect(Set(c.mainContext.changedModelsArray.map(\.persistentModelID)) == changed)
        #expect(Set(c.mainContext.deletedModelsArray.map(\.persistentModelID)) == deleted)
        #expect(try counts(c) == [0, 0])
        let stored = try ModelContext(c).fetch(FetchDescriptor<PersistentFoodItem>())
        #expect(stored.count == (kind == "insert" ? 0 : 1))
        #expect(stored.first?.energyKcalPer100Units == (kind == "insert" ? nil : 200))
    }

    @Test("An unrelated shared insertion, modification or deletion survives a successful or failed private save", arguments: ["insert", "modify", "delete"], [false, true])
    func unrelatedPendingModelsAreUntouched(kind: String, fail: Bool) throws {
        let c = try container()
        let unrelated = PersistentContainerProfile(domain: try ContainerProfile(name: "persisted", tareWeightGrams: 123))
        if kind != "insert" { c.mainContext.insert(unrelated); try c.mainContext.save() }
        switch kind {
        case "insert": c.mainContext.insert(unrelated)
        case "modify": unrelated.name = "pending name"
        default: c.mainContext.delete(unrelated)
        }
        let inserted = Set(c.mainContext.insertedModelsArray.map(\.persistentModelID))
        let changed = Set(c.mainContext.changedModelsArray.map(\.persistentModelID))
        let deleted = Set(c.mainContext.deletedModelsArray.map(\.persistentModelID))
        let request = try request()
        if fail {
            #expect(throws: MealCreateCommandError.saveFailed) {
                try MealCreateCommand.save(request: request, in: c, saveContext: { _ in throw Injected.beforeCommit })
            }
        } else {
            #expect(try MealCreateCommand.save(request: request, in: c) == request.meal)
        }
        #expect(c.mainContext.hasChanges)
        #expect(Set(c.mainContext.insertedModelsArray.map(\.persistentModelID)) == inserted)
        #expect(Set(c.mainContext.changedModelsArray.map(\.persistentModelID)) == changed)
        #expect(Set(c.mainContext.deletedModelsArray.map(\.persistentModelID)) == deleted)
        let stored = try ModelContext(c).fetch(FetchDescriptor<PersistentContainerProfile>())
        #expect(stored.count == (kind == "insert" ? 0 : 1))
        #expect(stored.first?.name == (kind == "insert" ? nil : "persisted"))
        #expect(try counts(c) == (fail ? [0, 0] : [1, 1]))
        try c.mainContext.save()
        let after = try ModelContext(c).fetch(FetchDescriptor<PersistentContainerProfile>())
        #expect(after.count == (kind == "delete" ? 0 : 1))
        if kind == "modify" { #expect(after.first?.name == "pending name") }
    }

    @Test("Pending changes to a source template or its children refuse creation without discarding the shared work", arguments: ["parent", "child", "deleteParent", "deleteChild", "insertChild"])
    func sourceTemplatePendingWorkIsProtected(kind: String) throws {
        let c = try container(); let template = try seedTemplate(c)
        let templateID = template.id
        switch kind {
        case "parent": template.name = "pending template name"
        case "child": template.components[0].defaultWeightGrams = 88
        case "deleteParent": c.mainContext.delete(template)
        case "deleteChild": c.mainContext.delete(template.components[0])
        default:
            let child = PersistentMealTemplateComponent(domain: try MealTemplateComponent(foodItemID: UUID(),
                foodName: "pending child", defaultWeightGrams: 20, unit: "g"))
            c.mainContext.insert(child); child.template = template
        }
        let inserted = Set(c.mainContext.insertedModelsArray.map(\.persistentModelID))
        let changed = Set(c.mainContext.changedModelsArray.map(\.persistentModelID))
        let deleted = Set(c.mainContext.deletedModelsArray.map(\.persistentModelID))
        #expect(throws: MealCreateCommandError.sharedModelsHaveUnsavedChanges) {
            try MealCreateCommand.save(request: request(sourceTemplateID: templateID), in: c)
        }
        #expect(c.mainContext.hasChanges)
        #expect(Set(c.mainContext.insertedModelsArray.map(\.persistentModelID)) == inserted)
        #expect(Set(c.mainContext.changedModelsArray.map(\.persistentModelID)) == changed)
        #expect(Set(c.mainContext.deletedModelsArray.map(\.persistentModelID)) == deleted)
        #expect(try counts(c) == [0, 0])
        #expect(try fetchTemplate(c, id: templateID).useCount == 5)
    }

    @Test("Pending meal or component identities cannot be upserted or silently committed", arguments: [false, true])
    func sharedPendingIdentityIsProtected(childOnly: Bool) throws {
        let c = try container(); let pending = try request()
        c.mainContext.insert(PersistentMealLog(domain: pending.meal))
        let request = childOnly ? try self.request(childID: pending.meal.components[0].id) : pending
        #expect(throws: MealCreateCommandError.sharedModelsHaveUnsavedChanges) {
            try MealCreateCommand.save(request: request, in: c)
        }
        #expect(c.mainContext.hasChanges)
        #expect(try counts(c) == [0, 0])
    }

    @Test("A failed save rolls back its private changes, template counters and any later save on the failed context")
    func failedPrivateContextDoesNotLeak() throws {
        let c = try container(); let template = try seedTemplate(c)
        let request = try request(sourceTemplateID: template.id)
        var attempted: ModelContext?
        #expect(throws: MealCreateCommandError.saveFailed) {
            try MealCreateCommand.save(request: request, in: c, saveContext: { context in
                attempted = context
                #expect(context !== c.mainContext)
                #expect(context.autosaveEnabled == false)
                throw Injected.beforeCommit
            })
        }
        #expect(attempted?.hasChanges == false)
        #expect(try counts(c) == [0, 0])
        #expect(template.useCount == 5)
        #expect(try fetchTemplate(c, id: template.id).useCount == 5)
        try attempted?.save()
        #expect(try counts(c) == [0, 0])
        #expect(try MealCreateCommand.save(request: request, in: c) == request.meal)
        #expect(try counts(c) == [1, 1])
        #expect(template.useCount == 6)
    }

    @Test("A real read-only file-store failure changes neither existing meals nor template state after reopen")
    func realReadOnlyFailurePreservesDisk() throws {
        let url = try temporaryDirectory().appendingPathComponent("read-only.store")
        let (existing, templateID) = try autoreleasepool {
            let c = try container(url: url); let template = try seedTemplate(c)
            let existing = try request(); _ = try MealCreateCommand.save(request: existing, in: c)
            return (existing.meal, template.id)
        }
        let refused = try request(sourceTemplateID: templateID)
        try autoreleasepool {
            let readOnly = try container(url: url, allowsSave: false)
            #expect(throws: MealCreateCommandError.saveFailed) {
                try MealCreateCommand.save(request: refused, in: readOnly)
            }
            #expect(try counts(readOnly) == [1, 1])
        }
        try autoreleasepool {
            let reopened = try container(url: url)
            #expect(try persisted(reopened, id: existing.id).domainModel() == existing)
            #expect(try counts(reopened) == [1, 1])
            let template = try fetchTemplate(reopened, id: templateID)
            #expect(template.useCount == 5)
            #expect(template.lastUsedAt == clock.addingTimeInterval(-60))
        }
    }

    private func container(url: URL? = nil, allowsSave: Bool = true) throws -> ModelContainer {
        let schema = Schema(versionedSchema: VersionedSchemaV2.self)
        let config: ModelConfiguration
        if let url { config = ModelConfiguration(schema: schema, url: url, allowsSave: allowsSave, cloudKitDatabase: .none) }
        else { config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none) }
        let c = try ModelContainer(for: schema, migrationPlan: ShiHengMigrationPlan.self, configurations: config)
        c.mainContext.autosaveEnabled = false
        return c
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("meal-create-synthetic-\(UUID())")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        // SwiftData can retain SQLite handles briefly after scope exit. These
        // synthetic App-tmp stores are reclaimed with the QA App lifecycle.
        return url
    }

    private func food(name: String = "synthetic food", fibre: Double? = nil) throws -> FoodItem {
        try FoodItem(name: name, category: .stapleGrain,
            nutrientsPer100Units: NutrientValues(energyKcal: 200, fatGrams: 10, saturatedFatGrams: 2,
                carbohydrateGrams: 20, sugarGrams: 4, proteinGrams: 5, saltGrams: 0.2, fibreGrams: fibre),
            source: "synthetic acceptance fixture")
    }

    private func row(food: PersistentFoodItem, weight: String) -> MealFormComponentDraft {
        var row = MealFormComponentDraft(component: .init(foodItemID: food.id, foodName: food.name), decimalSeparator: ".")
        row.weightText = weight
        return row
    }

    private func request(id: UUID = UUID(), childID: UUID = UUID(), title: String = "synthetic meal",
                         sourceTemplateID: UUID? = nil) throws -> MealCreateRequest {
        let component = try MealComponent(id: childID, foodItem: food(), consumedWeightGrams: 150)
        return MealCreateRequest(meal: try MealLog(id: id, eatenAt: clock, title: title,
            entryMethod: .weighed, coverageStatus: .complete, components: [component]),
            sourceTemplateID: sourceTemplateID, templateUsedAt: clock)
    }

    private func seedTemplate(_ c: ModelContainer) throws -> PersistentMealTemplate {
        let template = PersistentMealTemplate(domain: try MealTemplate(name: "synthetic template", createdAt: clock,
            updatedAt: clock, lastUsedAt: clock.addingTimeInterval(-60), useCount: 5,
            components: [MealTemplateComponent(foodItemID: UUID(), foodName: "synthetic ingredient", defaultWeightGrams: 150, unit: "g")]))
        c.mainContext.insert(template); try c.mainContext.save()
        return template
    }

    private func persisted(_ c: ModelContainer, id: UUID) throws -> PersistentMealLog {
        try #require(ModelContext(c).fetch(FetchDescriptor<PersistentMealLog>(predicate: #Predicate { $0.id == id })).first)
    }

    private func fetchTemplate(_ c: ModelContainer, id: UUID) throws -> PersistentMealTemplate {
        try #require(ModelContext(c).fetch(FetchDescriptor<PersistentMealTemplate>(predicate: #Predicate { $0.id == id })).first)
    }

    private func counts(_ c: ModelContainer) throws -> [Int] {
        let context = ModelContext(c)
        return try [context.fetchCount(FetchDescriptor<PersistentMealLog>()), context.fetchCount(FetchDescriptor<PersistentMealComponent>())]
    }

    private enum Injected: Error { case beforeCommit, refreshRead }
}
