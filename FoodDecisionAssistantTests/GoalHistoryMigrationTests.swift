import FoodDecisionCore
import Foundation
import SwiftData
import Testing

@testable import FoodDecisionAssistant

@MainActor
struct GoalHistoryMigrationTests {
    @Test("Frozen V1 keeps twelve original hashes and V2 adds only goal history")
    func schemasHaveDistinctVerifiedHashes() throws {
        let fixture = try GoalHistoryStoreFixture()
        defer { fixture.remove() }
        try fixture.seedLegacyStore()
        #expect(VersionedSchemaV1.models.count == 12)
        #expect(VersionedSchemaV2.models.count == 13)
        #expect(ShiHengMigrationPlan.schemas.count == 2)
        #expect(ShiHengMigrationPlan.stages.count == 1)
        #expect(try StoreSchemaCompatibility.modelHashes(at: fixture.defaultStoreURL) == StoreSchemaCompatibility.frozenModelHashes)
        let latestURL = fixture.directory.appendingPathComponent("latest.store")
        try autoreleasepool { _ = try LocalStoreBootstrap.openStore(at: latestURL) }
        #expect(try StoreSchemaCompatibility.modelHashes(at: latestURL) == StoreSchemaCompatibility.latestModelHashes)
        #expect(try StoreSchemaCompatibility.recognizedVersion(at: latestURL) == .v2)
    }

    @Test("V1 production upgrade publishes only a verified candidate and leaves source bytes unchanged")
    func automaticUpgradePreservesLegacySource() throws {
        let fixture = try GoalHistoryStoreFixture()
        defer { fixture.remove() }
        try fixture.seedLegacyStore()
        let before = try fixture.sourceFiles()
        let original = try fixture.legacyDocument()
        let bootstrap = fixture.bootstrap()
        #expect(bootstrap.failure == nil)
        let current = try #require(bootstrap.container)
        let activeURL = try #require(bootstrap.activeStoreURL)
        #expect(activeURL != fixture.defaultStoreURL)
        #expect(try fixture.sourceFiles() == before)
        #expect(try LocalStoreBackupService.records(from: current) == original.canonicalRecords)
        #expect(try current.mainContext.fetchCount(FetchDescriptor<PersistentGoalVersion>()) == 0)
        #expect(try StoreSchemaCompatibility.recognizedVersion(at: activeURL) == .v2)
        let restart = fixture.bootstrap()
        #expect(restart.failure == nil)
        #expect(restart.activeStoreURL == activeURL)
        #expect(try fixture.sourceFiles() == before)
    }

    @Test("Candidate migration failure leaves original selection and V1 store intact")
    func migrationFailurePreservesSelection() throws {
        let fixture = try GoalHistoryStoreFixture()
        defer { fixture.remove() }
        try fixture.seedLegacyStore()
        try JSONEncoder().encode(LocalStoreSelection(kind: .defaultStore)).write(to: fixture.selectionURL)
        let oldSelection = try Data(contentsOf: fixture.selectionURL)
        let oldFiles = try fixture.sourceFiles()
        var attempts = 0
        var candidateInspected = false
        let failed = fixture.bootstrap(candidateInspectionObserver: { candidateInspected = true }) { _ in
            attempts += 1
            throw GoalHistoryStoreFixture.Failure.migration
        }
        #expect(failed.container == nil)
        #expect(failed.failure as? LocalStoreBootstrapError == .openFailed,
            "failure=\(fixture.safeFailureCategory(failed.failure)); candidateInspected=\(candidateInspected)")
        #expect(attempts == 1,
            "failure=\(fixture.safeFailureCategory(failed.failure)); candidateInspected=\(candidateInspected)")
        #expect(try Data(contentsOf: fixture.selectionURL) == oldSelection)
        #expect(try fixture.sourceFiles() == oldFiles)
        #expect(try StoreSchemaCompatibility.recognizedVersion(at: fixture.defaultStoreURL) == .v1)
        let retried = fixture.bootstrap()
        #expect(retried.failure == nil)
        #expect(retried.activeStoreURL != fixture.defaultStoreURL)
    }

    @Test("After automatic upgrade a goal version survives restart without rechecking the old archive")
    func newHistorySurvivesRestart() throws {
        let fixture = try GoalHistoryStoreFixture()
        defer { fixture.remove() }
        try fixture.seedLegacyStore()
        let bootstrap = fixture.bootstrap()
        let current = try #require(bootstrap.container)
        let version = try fixture.version()
        current.mainContext.insert(PersistentGoalVersion(domain: version))
        try current.mainContext.save()
        let restart = fixture.bootstrap()
        #expect(restart.failure == nil)
        let saved = try #require(restart.container?.mainContext.fetch(FetchDescriptor<PersistentGoalVersion>()).first)
        #expect(try saved.domainModel == version)
    }

    @Test("A V2 reopen failure after candidate migration cannot publish a new store selection")
    func postMigrationReopenFailurePreservesSource() throws {
        let fixture = try GoalHistoryStoreFixture()
        defer { fixture.remove() }
        try fixture.seedLegacyStore()
        try JSONEncoder().encode(LocalStoreSelection(kind: .defaultStore)).write(to: fixture.selectionURL)
        let originalSelection = try Data(contentsOf: fixture.selectionURL)
        let sourceFiles = try fixture.sourceFiles()
        var attempts = 0
        var candidateInspected = false
        let failed = fixture.bootstrap(candidateInspectionObserver: { candidateInspected = true }) { url in
            attempts += 1
            if attempts == 2 { throw GoalHistoryStoreFixture.Failure.migration }
            return try LocalStoreBootstrap.openStore(at: url)
        }
        #expect(attempts == 2,
            "failure=\(fixture.safeFailureCategory(failed.failure)); candidateInspected=\(candidateInspected)")
        #expect(failed.container == nil)
        #expect(failed.failure as? LocalStoreBootstrapError == .openFailed,
            "failure=\(fixture.safeFailureCategory(failed.failure)); candidateInspected=\(candidateInspected)")
        #expect(try Data(contentsOf: fixture.selectionURL) == originalSelection)
        #expect(try fixture.sourceFiles() == sourceFiles)
        #expect(try StoreSchemaCompatibility.recognizedVersion(at: fixture.defaultStoreURL) == .v1)
    }

    @Test("Snapshot verification rejects changed original files without adopting a new baseline")
    func changedSourceCannotPassSnapshotVerification() throws {
        let fixture = try GoalHistoryStoreFixture()
        defer { fixture.remove() }
        let source = fixture.directory.appendingPathComponent("synthetic-source.store")
        try Data("first synthetic bytes".utf8).write(to: source)
        let snapshot = try LocalStoreFileSnapshot.make(from: source, in: fixture.restoreDirectory)
        defer { snapshot.remove() }
        try Data("changed synthetic bytes".utf8).write(to: source)
        #expect(throws: LocalStoreFileSnapshotError.sourceChanged([.init(file: .main, kind: .contentChanged)])) {
            try snapshot.verifySource(at: source)
        }
        #expect(try Data(contentsOf: snapshot.storeURL) == Data("first synthetic bytes".utf8))
    }
}

@MainActor
struct GoalHistoryStoreFixture {
    enum Failure: Error { case migration, fixtureCopyMismatch }
    struct PhaseFailure: Error, CustomStringConvertible {
        let phase: String
        let category: String
        var description: String { "\(phase): \(category)" }
    }
    let directory: URL
    var defaultStoreURL: URL { directory.appendingPathComponent("default.store") }
    var restoreDirectory: URL { directory.appendingPathComponent("BackupVerification", isDirectory: true) }
    var selectionURL: URL { directory.appendingPathComponent("active-store.json") }

    init() throws {
        directory = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("goal-history-migration-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    }

    func remove() { try? FileManager.default.removeItem(at: directory) }

    func atPhase<Value>(_ phase: String, operation: () throws -> Value) throws -> Value {
        do { return try operation() }
        catch {
            let category: String
            if let schemaError = error as? StoreSchemaCompatibilityError {
                category = String(describing: schemaError)
            } else if let snapshotError = error as? LocalStoreFileSnapshotError {
                category = String(describing: snapshotError)
            } else {
                // Only this synthetic fixture adds a phase; do not print record values or paths.
                category = String(describing: type(of: error))
            }
            throw PhaseFailure(phase: phase, category: category)
        }
    }

    func safeFailureCategory(_ error: (any Error)?) -> String {
        guard let error else { return "none" }
        if let safe = error as? LocalStoreBootstrapError { return String(describing: safe) }
        if let safe = error as? StoreSchemaCompatibilityError { return String(describing: safe) }
        if let safe = error as? LocalStoreFileSnapshotError { return String(describing: safe) }
        return String(describing: type(of: error))
    }

    func bootstrap(
        candidateInspectionObserver: (@MainActor () -> Void)? = nil,
        opener: @escaping @MainActor (URL) throws -> ModelContainer = LocalStoreBootstrap.openStore
    ) -> LocalStoreBootstrap {
        let validator = LocalStorePathValidator(trustedDirectory: directory) { path in
            if URL(fileURLWithPath: path).lastPathComponent == "restored.store" {
                candidateInspectionObserver?()
            }
            return try FileManager.default.attributesOfItem(atPath: path)
        }
        return LocalStoreBootstrap(defaultStoreURL: defaultStoreURL, restoreDirectory: restoreDirectory,
            selectionURL: selectionURL, pathValidator: validator, opener: opener)
    }

    func sourceFiles() throws -> [String: Data] {
        try files(at: defaultStoreURL)
    }

    private func files(at storeURL: URL) throws -> [String: Data] {
        var result: [String: Data] = [:]
        for suffix in ["", "-wal", "-shm"] {
            let url = URL(fileURLWithPath: storeURL.path + suffix)
            if FileManager.default.fileExists(atPath: url.path) { result[suffix] = try Data(contentsOf: url) }
        }
        return result
    }

    func legacyDocument() throws -> LocalStoreBackupDocument {
        try LocalStoreBackupCodec.decode(LocalStoreBackupService.legacyArchive(from: defaultStoreURL, directory: restoreDirectory))
    }

    func version() throws -> GoalVersion {
        let day = try GoalDay(key: 20261011)
        let zone = try #require(TimeZone(identifier: "Europe/London"))
        let profile = try GoalProfile(effectiveFrom: day.start(in: zone.identifier), energyKcal: 2100,
            proteinGrams: 140, carbohydrateGrams: 200, fatGrams: 60,
            saturatedFatLimitGrams: 0, fibreGrams: nil)
        return try GoalVersion(profile: profile, effectiveDay: day, source: .selfSelected,
            sourceNote: nil, confirmedAt: Date(timeIntervalSince1970: 1791630000),
            timeZoneIdentifier: zone.identifier, commitSequence: 1)
    }

    func seedLegacyStore() throws {
        try autoreleasepool {
            // The production-like source is never attached to this fixture's producer. Closing
            // SwiftData may asynchronously checkpoint or unlink the producer's SQLite sidecars;
            // those operations must not race the protected source inspected by the tested code.
            let producerURL = directory.appendingPathComponent("producer.store")
            let container = try LocalStoreBackupRestoration.legacyContainer(at: producerURL)
            let context = container.mainContext
            context.autosaveEnabled = false
            let nutrients = try NutrientValues(energyKcal: 123, fatGrams: 4, saturatedFatGrams: 1,
                carbohydrateGrams: 9, sugarGrams: 2, proteinGrams: 8, saltGrams: 0.3, fibreGrams: nil)
            let food = try FoodItem(name: "synthetic food", category: .mixedMeal,
                nutrientsPer100Units: nutrients, source: "synthetic fixture")
            context.insert(PersistentFoodItem(domain: food))
            context.insert(PersistentGoalProfile(domain: try GoalProfile(energyKcal: 2000,
                proteinGrams: 140, carbohydrateGrams: 210, fatGrams: 60)))
            context.insert(PersistentContainerProfile(domain: try ContainerProfile(name: "bowl", tareWeightGrams: 42)))
            let first = try MealComponent(foodItemID: food.id, foodName: "first", consumedWeightGrams: 100, unit: "g", nutrients: nutrients)
            let second = try MealComponent(foodItemID: food.id, foodName: "second", consumedWeightGrams: 50, unit: "g", nutrients: nutrients)
            let meal = try MealLog(title: "synthetic meal", entryMethod: .weighed, coverageStatus: .complete, components: [first, second])
            let persistentMeal = PersistentMealLog(domain: meal)
            persistentMeal.components[0].sortIndex = 8
            persistentMeal.components[1].sortIndex = 17
            context.insert(persistentMeal)
            context.insert(PersistentMealComponent(domain: try MealComponent(foodItem: food, consumedWeightGrams: 10), sortIndex: 99))
            context.insert(PersistentReviewQueueItem(domain: ReviewQueueItem(sourceImageIdentifier: nil, missingFields: ["one", "two"])))
            context.insert(PersistentHealthKitSyncRecord(domain: HealthKitSyncRecord(mealID: meal.id, objectType: .energy,
                syncIdentifier: "synthetic.sync", syncVersion: 3, healthKitUUID: UUID(), isDeleted: true)))
            let component = try MealPhotoComponent(foodItemID: food.id, templateID: nil, freeTextName: "oil",
                cookingMethod: .stirFried, portionRange: PortionEstimateRange(lowGrams: 2, midpointGrams: 4, highGrams: 7),
                confidence: 0.7, isHiddenOilOrSauce: true)
            let photoID = UUID()
            let calibration = try PortionCalibration(photoEstimateID: photoID, componentID: component.id,
                estimatedWeightGrams: 4, actualWeightGrams: 5)
            let photo = try MealPhotoEstimate(id: photoID, mealTitle: "synthetic photo", imageReference: "sha256:synthetic-photo",
                providerName: "fixture", modelVersion: "fixture-1", outputSchemaVersion: "schema-1",
                confirmationStatus: .confirmed, consumedShareRatio: 0.5, components: [component], calibrations: [calibration])
            context.insert(PersistentMealPhotoEstimate(domain: photo))
            context.insert(PersistentMealTemplate(domain: try MealTemplate(meal: meal)))
            try context.save()
            try withExtendedLifetime(container) {
                let snapshot = try LocalStoreFileSnapshot.make(from: producerURL, in: directory)
                defer { snapshot.remove() }
                let snapshotFiles = try files(at: snapshot.storeURL)
                for suffix in snapshotFiles.keys.sorted() {
                    try FileManager.default.copyItem(
                        at: URL(fileURLWithPath: snapshot.storeURL.path + suffix),
                        to: URL(fileURLWithPath: defaultStoreURL.path + suffix)
                    )
                }
                try snapshot.verifySource(at: producerURL)
                guard try sourceFiles() == snapshotFiles else { throw Failure.fixtureCopyMismatch }
            }
        }
    }
}
