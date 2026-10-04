import FoodDecisionCore
import Foundation
import SwiftData
import Testing

@testable import FoodDecisionAssistant

@MainActor
struct BackupServiceTests {
    @Test("All twelve entity kinds survive a file-backed restore and container reopen")
    func allEntitiesRestoreAndReopen() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = try populatedContainer()
        let data = try LocalStoreBackupService.export(from: source)
        let document = try LocalStoreBackupCodec.decode(data)

        #expect(Set(document.records.map(\.entity)) == Set(LocalStoreBackupEntityKind.allCases))
        let restoredURL = try LocalStoreBackupService.stageRestore(data: data, directory: directory)
        let reopened = try container(at: restoredURL)
        let restored = try LocalStoreBackupCodec.decode(LocalStoreBackupService.export(from: reopened))
        #expect(restored.records == document.records)
        #expect(restoredURL.deletingLastPathComponent().deletingLastPathComponent() == directory)
        #expect(try reopened.mainContext.fetch(FetchDescriptor<PersistentMealComponent>()).count == 3)
    }

    @Test("Raw enums, optional nils, historical invalid values and orphan children are preserved")
    func rawValuesAndOrphansArePreserved() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = try populatedContainer()
        let context = source.mainContext
        let meal = try #require(context.fetch(FetchDescriptor<PersistentMealLog>()).first)
        meal.entryMethodRawValue = "legacy_unrecognized_method"
        meal.coverageStatusRawValue = "legacy_unrecognized_coverage"
        meal.estimateEvidenceGradeRawValue = "legacy_unrecognized_evidence"
        meal.energyKcal = -10
        let photo = try #require(context.fetch(FetchDescriptor<PersistentMealPhotoEstimate>()).first)
        photo.confirmationStatusRawValue = "legacy_unrecognized_confirmation"
        let component = try #require(context.fetch(FetchDescriptor<PersistentMealPhotoComponent>()).first)
        component.cookingMethodRawValue = "legacy_unrecognized_cooking"
        component.confidence = 7
        component.userCorrectedWeightGrams = nil
        try context.save()

        let data = try LocalStoreBackupService.export(from: source)
        let restored = try container(at: LocalStoreBackupService.stageRestore(data: data, directory: directory))
        let result = try #require(restored.mainContext.fetch(FetchDescriptor<PersistentMealLog>()).first)
        #expect(result.entryMethodRawValue == "legacy_unrecognized_method")
        #expect(result.coverageStatusRawValue == "legacy_unrecognized_coverage")
        #expect(result.estimateEvidenceGradeRawValue == "legacy_unrecognized_evidence")
        #expect(result.energyKcal == -10)
        let allComponents = try restored.mainContext.fetch(FetchDescriptor<PersistentMealComponent>())
        #expect(allComponents.filter { $0.meal == nil }.count == 1)
        #expect(result.components.sorted { $0.sortIndex < $1.sortIndex }.map(\.foodName) == ["first", "second"])
        let restoredPhoto = try #require(restored.mainContext.fetch(FetchDescriptor<PersistentMealPhotoEstimate>()).first)
        #expect(restoredPhoto.confirmationStatusRawValue == "legacy_unrecognized_confirmation")
        let restoredPhotoComponent = try #require(restored.mainContext.fetch(FetchDescriptor<PersistentMealPhotoComponent>()).first)
        #expect(restoredPhotoComponent.confidence == 7)
        #expect(restoredPhotoComponent.cookingMethodRawValue == "legacy_unrecognized_cooking")
        #expect(restoredPhotoComponent.userCorrectedWeightGrams == nil)
    }

    @Test("A duplicate entity UUID with different content is rejected before any store is created")
    func conflictingIDIsRejected() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        var document = try LocalStoreBackupCodec.decode(LocalStoreBackupService.export(from: populatedContainer()))
        var conflicting = try #require(document.records.first)
        conflicting.fields["name"] = .string("conflicting content")
        document.records.append(conflicting)
        let data = try LocalStoreBackupCodec.encode(document)

        #expect(throws: LocalStoreBackupError.conflictingID(entity: conflicting.entity, id: conflicting.id)) {
            try LocalStoreBackupService.stageRestore(data: data, directory: directory)
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
    }

    @Test("Malformed JSON and inconsistent inverse relationships cannot modify the source store")
    func damagedBackupIsRejected() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = try populatedContainer()
        let before = try LocalStoreBackupCodec.decode(LocalStoreBackupService.export(from: source)).records
        #expect(throws: LocalStoreBackupError.malformedBackup) {
            try LocalStoreBackupService.stageRestore(data: Data("{broken".utf8), directory: directory)
        }
        var document = try LocalStoreBackupCodec.decode(LocalStoreBackupService.export(from: source))
        let index = try #require(document.records.firstIndex { $0.entity == .mealLog })
        let parentID = document.records[index].id
        let inconsistentChild = try #require(document.records.first {
            $0.entity == .mealComponent && $0.relationships["meal"] == .toOne(parentID)
        })
        document.records[index].relationships["components"] = .toMany([])
        #expect(throws: LocalStoreBackupError.invalidRelationship(entity: .mealComponent, id: inconsistentChild.id, relationship: "meal")) {
            try LocalStoreBackupService.stageRestore(data: LocalStoreBackupCodec.encode(document), directory: directory)
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
        #expect(try LocalStoreBackupCodec.decode(LocalStoreBackupService.export(from: source)).records == before)
    }

    @Test("Repeated imports create isolated stores, each containing exactly one copy of each record")
    func repeatedImportsAreIsolated() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let data = try LocalStoreBackupService.export(from: populatedContainer())
        let firstURL = try LocalStoreBackupService.stageRestore(data: data, directory: directory)
        let secondURL = try LocalStoreBackupService.stageRestore(data: data, directory: directory)
        #expect(firstURL != secondURL)
        let first = try LocalStoreBackupCodec.decode(LocalStoreBackupService.export(from: container(at: firstURL)))
        let second = try LocalStoreBackupCodec.decode(LocalStoreBackupService.export(from: container(at: secondURL)))
        #expect(first.records == second.records)
    }

    @Test("Non-finite numbers are explicit JSON markers and missing image bytes are reported")
    func nonFiniteNumbersAndImageWarnings() throws {
        var document = try LocalStoreBackupCodec.decode(LocalStoreBackupService.export(from: populatedContainer()))
        let index = try #require(document.records.firstIndex { $0.entity == .goalProfile })
        document.records[index].fields["energyKcal"] = .number(.infinity)
        document.records[index].fields["proteinGrams"] = .number(.nan)
        document.records[index].fields["fatGrams"] = .number(-.infinity)
        let data = try LocalStoreBackupCodec.encode(document)
        #expect(try LocalStoreBackupCodec.decode(data) == document)
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.contains("+Infinity"))
        #expect(text.contains("-Infinity"))
        #expect(text.contains("NaN"))
        let summary = try LocalStoreBackupService.inspect(data: data)
        #expect(summary.imageWarnings.contains { $0.reference == "sha256:fixture-photo" })
    }

    @Test("Non-finite restore is explicitly rejected before disk writes, preserving source and input")
    func nonFiniteRestoreCannotSilentlyNormalize() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = try populatedContainer()
        let sourceBefore = try LocalStoreBackupCodec.decode(LocalStoreBackupService.export(from: source)).records
        var document = try LocalStoreBackupCodec.decode(LocalStoreBackupService.export(from: source))
        let index = try #require(document.records.firstIndex { $0.entity == .goalProfile })
        document.records[index].fields["energyKcal"] = .number(.infinity)
        document.records[index].fields["proteinGrams"] = .number(.nan)
        document.records[index].fields["fatGrams"] = .number(-.infinity)
        let data = try LocalStoreBackupCodec.encode(document)
        let originalInput = data

        #expect(throws: LocalStoreBackupError.nonFiniteValueCannotBeRestored(
            entity: .goalProfile, id: document.records[index].id, field: "energyKcal"
        )) {
            try LocalStoreBackupService.stageRestore(data: data, directory: directory)
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
        #expect(data == originalInput)
        #expect(try LocalStoreBackupCodec.decode(data).canonicalRecords == document.canonicalRecords)
        #expect(try LocalStoreBackupCodec.decode(LocalStoreBackupService.export(from: source)).records == sourceBefore)
    }

    @Test("A source file store closes and reopens before export, and the restored values still match")
    func sourceFileStoreReopensBeforeExport() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let sourceURL = directory.appendingPathComponent("source.store")
        try autoreleasepool {
            _ = try populatedContainer(at: sourceURL)
        }
        let data = try autoreleasepool {
            try LocalStoreBackupService.export(from: container(at: sourceURL))
        }
        let expected = try LocalStoreBackupCodec.decode(data).canonicalRecords
        let restoredURL = try LocalStoreBackupService.stageRestore(data: data, directory: directory)
        let actual = try autoreleasepool {
            try LocalStoreBackupCodec.decode(LocalStoreBackupService.export(from: container(at: restoredURL))).canonicalRecords
        }
        #expect(actual == expected)
    }

    @Test("Unsupported format versions are rejected exactly")
    func unsupportedVersionIsRejected() throws {
        var document = try LocalStoreBackupCodec.decode(LocalStoreBackupService.export(from: populatedContainer()))
        document.formatVersion = 99
        #expect(throws: LocalStoreBackupError.unsupportedVersion) {
            try LocalStoreBackupService.inspect(data: LocalStoreBackupCodec.encode(document))
        }
    }

    @Test("A missing stored field is rejected without constructing a model")
    func missingFieldIsRejected() throws {
        var document = try LocalStoreBackupCodec.decode(LocalStoreBackupService.export(from: populatedContainer()))
        let index = try #require(document.records.firstIndex { $0.entity == .containerProfile })
        let id = document.records[index].id
        document.records[index].fields.removeValue(forKey: "tareWeightGrams")
        #expect(throws: LocalStoreBackupError.invalidRecord(entity: .containerProfile, id: id, field: "field names")) {
            try LocalStoreBackupService.inspect(data: LocalStoreBackupCodec.encode(document))
        }
    }

    @Test("An identical duplicate UUID is rejected rather than silently imported twice")
    func identicalDuplicateIsRejected() throws {
        var document = try LocalStoreBackupCodec.decode(LocalStoreBackupService.export(from: populatedContainer()))
        let duplicate = try #require(document.records.first)
        document.records.append(duplicate)
        #expect(throws: LocalStoreBackupError.duplicateID(entity: duplicate.entity, id: duplicate.id)) {
            try LocalStoreBackupService.inspect(data: LocalStoreBackupCodec.encode(document))
        }
    }

    @Test("A parent referencing a missing child fails relationship validation")
    func missingRelationshipChildIsRejected() throws {
        var document = try LocalStoreBackupCodec.decode(LocalStoreBackupService.export(from: populatedContainer()))
        let parent = try #require(document.records.first { $0.entity == .mealLog })
        guard case let .toMany(ids) = parent.relationships["components"] else {
            Issue.record("Fixture has no component relationship")
            return
        }
        let childID = try #require(ids.first)
        document.records.removeAll { $0.entity == .mealComponent && $0.id == childID }
        #expect(throws: LocalStoreBackupError.invalidRelationship(entity: .mealLog, id: parent.id, relationship: "components")) {
            try LocalStoreBackupService.inspect(data: LocalStoreBackupCodec.encode(document))
        }
    }

    @Test("Same-ID template edits survive repeated saves, a file-store reopen and backup restoration")
    func sameIDTemplateEditsAreProtected() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let sourceURL = directory.appendingPathComponent("source.store")
        let componentIDs = try autoreleasepool {
            let source = try populatedContainer(at: sourceURL)
            let context = source.mainContext
            let template = try #require(context.fetch(FetchDescriptor<PersistentMealTemplate>()).first)
            let ids = template.components.map(\.id).sorted { $0.uuidString < $1.uuidString }
            for iteration in 1...3 {
                var changed = try template.domainModel()
                changed.name = "edited \(iteration)"
                changed.components[0].defaultWeightGrams = Double(100 + iteration)
                template.update(from: changed, in: context)
                try context.save()
            }
            return ids
        }
        let source = try container(at: sourceURL)
        let restoredTemplate = try #require(source.mainContext.fetch(FetchDescriptor<PersistentMealTemplate>()).first)
        #expect(restoredTemplate.components.map(\.id).sorted { $0.uuidString < $1.uuidString } == componentIDs)
        #expect(restoredTemplate.components.sorted { $0.sortIndex < $1.sortIndex }.first?.defaultWeightGrams == 103)
        let data = try LocalStoreBackupService.export(from: source)
        let restored = try container(at: LocalStoreBackupService.stageRestore(data: data, directory: directory))
        let restoredRecords = try LocalStoreBackupCodec.decode(LocalStoreBackupService.export(from: restored)).records
        let expectedRecords = try LocalStoreBackupCodec.decode(data).records
        #expect(restoredRecords == expectedRecords)
    }

    @Test("Export does not commit cancelled meal or template-usage mutations from the shared context")
    func cancelledMutationsAreNotExported() throws {
        let source = try populatedContainer()
        let before = try LocalStoreBackupCodec.decode(LocalStoreBackupService.export(from: source)).records
        let context = source.mainContext
        context.autosaveEnabled = false
        let template = try #require(context.fetch(FetchDescriptor<PersistentMealTemplate>()).first)
        template.markUsed()
        context.insert(PersistentMealLog(domain: MealLog(title: "cancelled", consumedWeightGrams: 0, nutrients: zeroNutrients, coverageStatus: .incomplete, estimateEvidenceGrade: .d)))
        #expect(try LocalStoreBackupCodec.decode(LocalStoreBackupService.export(from: source)).records == before)
        context.rollback()
        #expect(try LocalStoreBackupCodec.decode(LocalStoreBackupService.export(from: source)).records == before)
    }

    @Test("A failed read-only save cannot commit a meal or its usage count")
    func failedSavePreservesCommittedRecords() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let sourceURL = directory.appendingPathComponent("source.store")
        let before = try autoreleasepool {
            try LocalStoreBackupCodec.decode(LocalStoreBackupService.export(from: populatedContainer(at: sourceURL))).records
        }
        let schema = Schema(versionedSchema: VersionedSchemaV1.self)
        let configuration = ModelConfiguration(schema: schema, url: sourceURL, allowsSave: false, cloudKitDatabase: .none)
        let readOnly = try ModelContainer(for: schema, configurations: configuration)
        let context = ModelContext(readOnly)
        context.autosaveEnabled = false
        let template = try #require(context.fetch(FetchDescriptor<PersistentMealTemplate>()).first)
        template.markUsed()
        context.insert(PersistentMealLog(domain: MealLog(title: "failed", consumedWeightGrams: 0, nutrients: zeroNutrients, coverageStatus: .incomplete, estimateEvidenceGrade: .d)))
        do {
            try context.save()
            Issue.record("The read-only store unexpectedly permitted a write")
        } catch {
            context.rollback()
        }
        #expect(try LocalStoreBackupCodec.decode(LocalStoreBackupService.export(from: readOnly)).records == before)
    }

    @Test("Staged backup and database files have owner-only permissions")
    func stagedFilesArePrivate() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let data = try LocalStoreBackupService.export(from: populatedContainer())
        let storeURL = try LocalStoreBackupService.stageRestore(data: data, directory: directory)
        let stage = storeURL.deletingLastPathComponent()
        let permissions = try FileManager.default.attributesOfItem(atPath: stage.path)[.posixPermissions] as? NSNumber
        #expect(permissions?.intValue == 0o700)
        for file in try FileManager.default.contentsOfDirectory(at: stage, includingPropertiesForKeys: nil) {
            let filePermissions = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber
            #expect(filePermissions?.intValue == 0o600)
        }
    }

    private var zeroNutrients: NutrientValues {
        NutrientValues(energyKcal: 0, fatGrams: 0, saturatedFatGrams: 0, carbohydrateGrams: 0, sugarGrams: 0, proteinGrams: 0, saltGrams: 0)
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("BackupTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        return directory
    }

    private func container(at url: URL? = nil) throws -> ModelContainer {
        let schema = Schema(versionedSchema: VersionedSchemaV1.self)
        let configuration: ModelConfiguration
        if let url {
            configuration = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        } else {
            configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        }
        return try ModelContainer(for: schema, configurations: configuration)
    }

    private func populatedContainer(at url: URL? = nil) throws -> ModelContainer {
        let container = try container(at: url)
        let context = container.mainContext
        let nutrients = NutrientValues(energyKcal: 123, fatGrams: 4, saturatedFatGrams: 1, carbohydrateGrams: 9, sugarGrams: 2, proteinGrams: 8, saltGrams: 0.3, fibreGrams: nil)
        let food = FoodItem(name: "fixture food", category: .mixedMeal, nutrientsPer100Units: nutrients, source: "fixture")
        context.insert(PersistentFoodItem(domain: food))
        context.insert(PersistentGoalProfile(domain: GoalProfile(energyKcal: 2000, proteinGrams: 140, carbohydrateGrams: 210, fatGrams: 60)))
        context.insert(PersistentContainerProfile(domain: ContainerProfile(name: "bowl", tareWeightGrams: 42)))
        let first = try MealComponent(foodItemID: food.id, foodName: "first", consumedWeightGrams: 100, unit: "g", nutrients: nutrients)
        let second = try MealComponent(foodItemID: food.id, foodName: "second", consumedWeightGrams: 50, unit: "g", nutrients: nutrients)
        let meal = try MealLog(title: "fixture meal", entryMethod: .weighed, coverageStatus: .complete, components: [first, second])
        let persistentMeal = PersistentMealLog(domain: meal)
        persistentMeal.components[0].sortIndex = 8
        persistentMeal.components[1].sortIndex = 17
        context.insert(persistentMeal)
        context.insert(PersistentMealComponent(domain: try MealComponent(foodItem: food, consumedWeightGrams: 10), sortIndex: 99))
        context.insert(PersistentReviewQueueItem(domain: ReviewQueueItem(sourceImageIdentifier: nil, missingFields: ["one", "two"])))
        context.insert(PersistentHealthKitSyncRecord(domain: HealthKitSyncRecord(mealID: meal.id, objectType: .energy, syncIdentifier: "fixture.sync", syncVersion: 3, healthKitUUID: UUID(), isDeleted: true)))
        let photoComponent = try MealPhotoComponent(foodItemID: food.id, templateID: nil, freeTextName: "hidden oil", cookingMethod: .stirFried, portionRange: PortionEstimateRange(lowGrams: 2, midpointGrams: 4, highGrams: 7), confidence: 0.7, isHiddenOilOrSauce: true)
        let photoID = UUID()
        let calibration = try PortionCalibration(photoEstimateID: photoID, componentID: photoComponent.id, estimatedWeightGrams: 4, actualWeightGrams: 5)
        let photo = try MealPhotoEstimate(id: photoID, mealTitle: "fixture photo", imageReference: "sha256:fixture-photo", providerName: "fixture", modelVersion: "fixture-1", outputSchemaVersion: "schema-1", confirmationStatus: .confirmed, consumedShareRatio: 0.5, components: [photoComponent], calibrations: [calibration])
        context.insert(PersistentMealPhotoEstimate(domain: photo))
        context.insert(PersistentMealTemplate(domain: try MealTemplate(meal: meal)))
        try context.save()
        return container
    }
}
