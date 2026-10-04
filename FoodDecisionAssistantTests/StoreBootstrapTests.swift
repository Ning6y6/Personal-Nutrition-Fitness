import CoreData
import FoodDecisionCore
import Foundation
import SwiftData
import Testing

@testable import FoodDecisionAssistant

@MainActor
struct StoreBootstrapTests {
    @Test("Explicit local configuration retains the legacy default store URL without opening it")
    func defaultLocationDoesNotChange() {
        let schema = Schema(versionedSchema: VersionedSchemaV1.self)
        #expect(ModelConfiguration(schema: schema).url == ModelConfiguration(schema: schema, cloudKitDatabase: .none).url)
    }

    @Test("A file-backed twelve-entity schema exactly matches the frozen metadata hashes")
    func diskSchemaHashesAreFrozen() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try autoreleasepool { _ = try LocalStoreBootstrap.openStore(at: fixture.defaultStoreURL) }
        #expect(try StoreSchemaCompatibility.modelHashes(at: fixture.defaultStoreURL) == StoreSchemaCompatibility.frozenModelHashes)
        #expect(StoreSchemaCompatibility.frozenModelHashes.count == 12)
        #expect(ShiHengMigrationPlan.schemas.count == 1)
        #expect(ShiHengMigrationPlan.stages.isEmpty)
    }

    @Test("Corrupt startup files are preserved and never replaced with an empty database")
    func corruptStartupPreservesFile() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let original = Data("not a SQLite database: synthetic fixture".utf8)
        try original.write(to: fixture.defaultStoreURL)
        var openAttempts = 0
        let bootstrap = fixture.bootstrap { url in
            openAttempts += 1
            return try LocalStoreBootstrap.openStore(at: url)
        }
        #expect(bootstrap.container == nil)
        #expect(bootstrap.failure as? StoreSchemaCompatibilityError == .metadataUnreadable)
        #expect(openAttempts == 0)
        #expect(try Data(contentsOf: fixture.defaultStoreURL) == original)
        #expect(FileManager.default.fileExists(atPath: fixture.selectionURL.path) == false)
    }

    @Test("An unsupported on-disk schema is rejected before any SwiftData opener runs")
    func unknownSchemaCannotAutoMigrate() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try createUnsupportedStore(at: fixture.defaultStoreURL)
        let before = try Data(contentsOf: fixture.defaultStoreURL)
        var openAttempts = 0
        let bootstrap = fixture.bootstrap { url in
            openAttempts += 1
            return try LocalStoreBootstrap.openStore(at: url)
        }
        #expect(bootstrap.failure as? StoreSchemaCompatibilityError == .unrecognizedModelHashes)
        #expect(bootstrap.container == nil)
        #expect(openAttempts == 0)
        #expect(try Data(contentsOf: fixture.defaultStoreURL) == before)
    }

    @Test("An opener failure is safely diagnosed and retry can open the same preserved store")
    func failedOpenCanRetry() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.createDefaultStore()
        var attempts = 0
        let bootstrap = fixture.bootstrap { url in
            attempts += 1
            if attempts == 1 { throw FixtureError.simulatedOpenFailure }
            return try LocalStoreBootstrap.openStore(at: url)
        }
        #expect(bootstrap.container == nil)
        #expect(bootstrap.failure as? LocalStoreBootstrapError == .openFailed)
        bootstrap.retry()
        #expect(bootstrap.container != nil)
        #expect(bootstrap.failure == nil)
        #expect(bootstrap.activeStoreURL == fixture.defaultStoreURL)
        #expect(attempts == 2)
    }

    @Test("Verified activation atomically changes the selection, and restart preserves subsequent meals")
    func activationAndRestartPersistSelection() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let bootstrap = fixture.bootstrap()
        let oldContainer = try #require(bootstrap.container)
        let oldRecords = try LocalStoreBackupService.records(from: oldContainer)
        let oldGeneration = bootstrap.generation
        let archive = try makeArchive()
        let candidate = try LocalStoreBackupService.stageRestore(data: archive, directory: fixture.restoreDirectory)
        try bootstrap.activateRestoredStore(at: candidate)
        #expect(bootstrap.activeStoreURL == candidate)
        #expect(bootstrap.generation != oldGeneration)
        #expect(bootstrap.failure == nil)
        #expect(try LocalStoreBackupService.records(from: oldContainer) == oldRecords)
        #expect(FileManager.default.fileExists(atPath: fixture.defaultStoreURL.path))
        let pointer = try Data(contentsOf: fixture.selectionURL)
        let selection = try JSONDecoder().decode(LocalStoreSelection.self, from: pointer)
        #expect(selection.kind == .restoredStore)
        #expect(selection.restoreDirectoryID == candidate.deletingLastPathComponent().lastPathComponent)
        #expect(String(decoding: pointer, as: UTF8.self).contains(fixture.directory.path) == false)

        let current = try #require(bootstrap.container)
        current.mainContext.insert(meal(title: "new meal after restoration"))
        try current.mainContext.save()
        let restart = fixture.bootstrap()
        let reopened = try #require(restart.container)
        #expect(restart.activeStoreURL == candidate)
        #expect(try reopened.mainContext.fetch(FetchDescriptor<PersistentMealLog>()).count == 2)
        // Startup must not compare an actively-used restored store to its original historical backup.
        #expect(restart.failure == nil)
    }

    @Test("A candidate differing from its source backup leaves selection, container and generation intact")
    func mismatchedRestoreCannotActivate() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let bootstrap = fixture.bootstrap()
        let original = try #require(bootstrap.container)
        let pointer = try Data(contentsOf: fixture.selectionURL)
        let generation = bootstrap.generation
        let candidate = try LocalStoreBackupService.stageRestore(data: makeArchive(), directory: fixture.restoreDirectory)
        try autoreleasepool {
            let changed = try LocalStoreBootstrap.openStore(at: candidate)
            let row = try #require(changed.mainContext.fetch(FetchDescriptor<PersistentMealLog>()).first)
            row.title = "tampered synthetic meal"
            try changed.mainContext.save()
        }
        #expect(throws: LocalStoreBootstrapError.restoredStoreMismatch) { try bootstrap.activateRestoredStore(at: candidate) }
        #expect(bootstrap.container === original)
        #expect(bootstrap.generation == generation)
        #expect(bootstrap.activeStoreURL == fixture.defaultStoreURL)
        #expect(try Data(contentsOf: fixture.selectionURL) == pointer)
    }

    @Test("Unsaved edits block both activation and retry without implicit saving or rollback")
    func unsavedContextCannotSwitch() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let bootstrap = fixture.bootstrap()
        let original = try #require(bootstrap.container)
        original.mainContext.autosaveEnabled = false
        original.mainContext.insert(meal(title: "unsaved synthetic meal"))
        let pointer = try Data(contentsOf: fixture.selectionURL)
        let generation = bootstrap.generation
        let candidate = try LocalStoreBackupService.stageRestore(data: makeArchive(), directory: fixture.restoreDirectory)
        #expect(throws: LocalStoreBootstrapError.unsavedChanges) { try bootstrap.activateRestoredStore(at: candidate) }
        bootstrap.retry()
        #expect(bootstrap.failure as? LocalStoreBootstrapError == .unsavedChanges)
        #expect(bootstrap.container === original)
        #expect(bootstrap.generation == generation)
        #expect(original.mainContext.hasChanges)
        #expect(try Data(contentsOf: fixture.selectionURL) == pointer)
        #expect(try LocalStoreBackupService.records(from: original).isEmpty)
        original.mainContext.rollback()
    }

    @Test("Invalid backup bytes cannot switch a live database")
    func invalidBackupCannotActivate() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let bootstrap = fixture.bootstrap()
        let original = try #require(bootstrap.container)
        let pointer = try Data(contentsOf: fixture.selectionURL)
        let candidate = try LocalStoreBackupService.stageRestore(data: makeArchive(), directory: fixture.restoreDirectory)
        let backup = candidate.deletingLastPathComponent().appendingPathComponent("source-backup.shihengbackup")
        try Data("{malformed synthetic backup".utf8).write(to: backup)
        #expect(throws: LocalStoreBootstrapError.invalidBackup) { try bootstrap.activateRestoredStore(at: candidate) }
        #expect(bootstrap.container === original)
        #expect(try Data(contentsOf: fixture.selectionURL) == pointer)
    }

    @Test("A missing source backup is distinguished from invalid backup content")
    func missingBackupCannotActivate() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let bootstrap = fixture.bootstrap()
        let candidate = try LocalStoreBackupService.stageRestore(data: makeArchive(), directory: fixture.restoreDirectory)
        try FileManager.default.removeItem(at: candidate.deletingLastPathComponent().appendingPathComponent("source-backup.shihengbackup"))
        #expect(throws: LocalStoreBootstrapError.backupUnavailable) { try bootstrap.activateRestoredStore(at: candidate) }
        #expect(bootstrap.activeStoreURL == fixture.defaultStoreURL)
    }

    @Test("A previously selected restored store missing at restart never creates a replacement")
    func missingChosenRestoreCannotBecomeEmptyStore() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let candidate = try LocalStoreBackupService.stageRestore(data: makeArchive(), directory: fixture.restoreDirectory)
        try autoreleasepool {
            let bootstrap = fixture.bootstrap()
            try bootstrap.activateRestoredStore(at: candidate)
        }
        let pointer = try Data(contentsOf: fixture.selectionURL)
        try removeFixtureStore(at: candidate)
        let restart = fixture.bootstrap()
        #expect(restart.failure as? LocalStoreBootstrapError == .missingSelectedStore)
        #expect(restart.container == nil)
        #expect(FileManager.default.fileExists(atPath: candidate.path) == false)
        #expect(try Data(contentsOf: fixture.selectionURL) == pointer)
    }

    @Test("A seen default store missing at restart also cannot be mistaken for first installation")
    func missingSeenDefaultCannotBecomeEmptyStore() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.createDefaultStore()
        try autoreleasepool {
            let bootstrap = fixture.bootstrap()
            try #require(bootstrap.container != nil)
        }
        let pointer = try Data(contentsOf: fixture.selectionURL)
        let selection = try JSONDecoder().decode(LocalStoreSelection.self, from: pointer)
        #expect(selection.kind == .defaultStore)
        try removeFixtureStore(at: fixture.defaultStoreURL)
        let restart = fixture.bootstrap()
        #expect(restart.failure as? LocalStoreBootstrapError == .missingSelectedStore)
        #expect(restart.container == nil)
        #expect(FileManager.default.fileExists(atPath: fixture.defaultStoreURL.path) == false)
        #expect(try Data(contentsOf: fixture.selectionURL) == pointer)
    }

    @Test("Orphaned SQLite sidecars with no selection block first-install database creation")
    func sidecarsWithoutMainStoreArePreserved() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let wal = URL(fileURLWithPath: fixture.defaultStoreURL.path + "-wal")
        let original = Data("synthetic orphaned write-ahead log".utf8)
        try original.write(to: wal)
        let bootstrap = fixture.bootstrap()
        #expect(bootstrap.failure as? LocalStoreBootstrapError == .orphanedStoreSidecars)
        #expect(bootstrap.container == nil)
        #expect(FileManager.default.fileExists(atPath: fixture.defaultStoreURL.path) == false)
        #expect(try Data(contentsOf: wal) == original)
    }

    @Test("Malformed selection is not ignored", arguments: [
        "{broken", "{}", "{\"version\":1,\"kind\":\"unknown\"}",
        "{\"version\":1,\"kind\":\"restoredStore\",\"restoreDirectoryID\":\"../outside\"}",
        "{\"version\":1,\"kind\":\"defaultStore\",\"restoreDirectoryID\":\"unexpected\"}",
    ])
    func malformedSelectionCannotCreateStore(json: String) throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let data = Data(json.utf8)
        try data.write(to: fixture.selectionURL)
        let bootstrap = fixture.bootstrap()
        #expect(bootstrap.failure as? LocalStoreBootstrapError == .invalidSelection)
        #expect(bootstrap.container == nil)
        #expect(FileManager.default.fileExists(atPath: fixture.defaultStoreURL.path) == false)
        #expect(try Data(contentsOf: fixture.selectionURL) == data)
    }

    @Test("Unsupported selection version is explicitly diagnosed")
    func unsupportedSelectionVersionCannotCreateStore() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        var selection = LocalStoreSelection(kind: .defaultStore)
        selection.version = 99
        try JSONEncoder().encode(selection).write(to: fixture.selectionURL)
        let bootstrap = fixture.bootstrap()
        #expect(bootstrap.failure as? LocalStoreBootstrapError == .unsupportedSelectionVersion)
        #expect(bootstrap.container == nil)
        #expect(FileManager.default.fileExists(atPath: fixture.defaultStoreURL.path) == false)
    }

    @Test("Any user-controlled symbolic link in a candidate path is rejected", arguments: ["root", "directory", "store", "backup", "wal"])
    func symbolicLinksCannotActivate(location: String) throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let bootstrap = fixture.bootstrap()
        let pointer = try Data(contentsOf: fixture.selectionURL)
        let candidate = try LocalStoreBackupService.stageRestore(data: makeArchive(), directory: fixture.restoreDirectory)
        let item: URL
        switch location {
        case "root": item = fixture.restoreDirectory
        case "directory": item = candidate.deletingLastPathComponent()
        case "backup": item = candidate.deletingLastPathComponent().appendingPathComponent("source-backup.shihengbackup")
        case "wal": item = URL(fileURLWithPath: candidate.path + "-wal")
        default: item = candidate
        }
        let actual = fixture.directory.appendingPathComponent("symlink-target-\(location)")
        if FileManager.default.fileExists(atPath: item.path) {
            try FileManager.default.moveItem(at: item, to: actual)
        } else {
            try Data("synthetic target".utf8).write(to: actual)
        }
        try FileManager.default.createSymbolicLink(at: item, withDestinationURL: actual)
        #expect(throws: LocalStoreBootstrapError.unsafeStorePath) { try bootstrap.activateRestoredStore(at: candidate) }
        #expect(bootstrap.activeStoreURL == fixture.defaultStoreURL)
        #expect(try Data(contentsOf: fixture.selectionURL) == pointer)
    }

    @Test("A linked selection file is rejected before opening or creating a store")
    func symbolicSelectionCannotOpenStore() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let actual = fixture.directory.appendingPathComponent("actual-selection.json")
        try JSONEncoder().encode(LocalStoreSelection(kind: .defaultStore)).write(to: actual)
        try FileManager.default.createSymbolicLink(at: fixture.selectionURL, withDestinationURL: actual)
        let bootstrap = fixture.bootstrap()
        #expect(bootstrap.failure as? LocalStoreBootstrapError == .unsafeStorePath)
        #expect(bootstrap.container == nil)
        #expect(FileManager.default.fileExists(atPath: fixture.defaultStoreURL.path) == false)
    }

    @Test("Stores outside the fixed UUID/restored.store layout cannot activate")
    func outsideCandidateCannotActivate() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let bootstrap = fixture.bootstrap()
        #expect(throws: LocalStoreBootstrapError.unsafeStorePath) {
            try bootstrap.activateRestoredStore(at: fixture.directory.appendingPathComponent("restored.store"))
        }
        #expect(throws: LocalStoreBootstrapError.unsafeStorePath) {
            try bootstrap.activateRestoredStore(at: fixture.restoreDirectory.appendingPathComponent("not-a-uuid/restored.store"))
        }
    }

    @Test("Atomic pointer publication failure cannot switch the in-memory container")
    func pointerPublicationFailureKeepsContainer() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let bootstrap = fixture.bootstrap()
        let original = try #require(bootstrap.container)
        let generation = bootstrap.generation
        let candidate = try LocalStoreBackupService.stageRestore(data: makeArchive(), directory: fixture.restoreDirectory)
        // An unexpected directory at the marker path forces atomic rename to fail. All targets
        // belong to this temporary fixture; no real selection or database is deleted.
        try FileManager.default.removeItem(at: fixture.selectionURL)
        try FileManager.default.createDirectory(at: fixture.selectionURL, withIntermediateDirectories: false)
        let sentinel = fixture.selectionURL.appendingPathComponent("must-remain")
        let bytes = Data("preserve existing marker target".utf8)
        try bytes.write(to: sentinel)
        #expect(throws: LocalStoreBootstrapError.selectionWriteFailed) { try bootstrap.activateRestoredStore(at: candidate) }
        #expect(bootstrap.container === original)
        #expect(bootstrap.generation == generation)
        #expect(bootstrap.activeStoreURL == fixture.defaultStoreURL)
        #expect(try Data(contentsOf: sentinel) == bytes)
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.directory.path).contains { $0.hasPrefix(".active-store-") } == false)
    }

    @Test("Selection files are private and diagnostics do not expose injected error details")
    func markerPermissionsAndSafeDiagnostics() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let bootstrap = fixture.bootstrap()
        try #require(bootstrap.container != nil)
        let attributes = try FileManager.default.attributesOfItem(atPath: fixture.selectionURL.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        // Simulator does not report Data Protection attributes; verify the protection class on a
        // physical device. POSIX permission checks above still run on every test environment.
        #if os(iOS) && !targetEnvironment(simulator)
        #expect(attributes[.protectionKey] as? String == FileProtectionType.completeUntilFirstUserAuthentication.rawValue)
        #endif
        let failed = fixture.bootstrap { _ in throw NSError(domain: "private fixture meal details", code: 123) }
        #expect(failed.failure as? LocalStoreBootstrapError == .openFailed)
        #expect(failed.failure?.localizedDescription.contains("private fixture meal") == false)
    }

    private enum FixtureError: Error { case simulatedOpenFailure }

    private struct Fixture {
        let directory: URL
        var defaultStoreURL: URL { directory.appendingPathComponent("default.store") }
        var restoreDirectory: URL { directory.appendingPathComponent("BackupVerification", isDirectory: true) }
        var selectionURL: URL { directory.appendingPathComponent("active-store.json") }

        init() throws {
            directory = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("store-bootstrap-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        }

        @MainActor
        func bootstrap(opener: @escaping @MainActor (URL) throws -> ModelContainer = LocalStoreBootstrap.openStore) -> LocalStoreBootstrap {
            LocalStoreBootstrap(defaultStoreURL: defaultStoreURL, restoreDirectory: restoreDirectory, selectionURL: selectionURL, opener: opener)
        }

        @MainActor
        func createDefaultStore() throws {
            try autoreleasepool { _ = try LocalStoreBootstrap.openStore(at: defaultStoreURL) }
        }

        func remove() { try? FileManager.default.removeItem(at: directory) }
    }

    private func meal(title: String) -> PersistentMealLog {
        PersistentMealLog(domain: MealLog(
            title: title, consumedWeightGrams: 100,
            nutrients: NutrientValues(energyKcal: 100, fatGrams: 1, saturatedFatGrams: 0, carbohydrateGrams: 10, sugarGrams: 0, proteinGrams: 10, saltGrams: 0, fibreGrams: nil),
            coverageStatus: .complete, estimateEvidenceGrade: .a
        ))
    }

    private func makeArchive() throws -> Data {
        let schema = Schema(versionedSchema: VersionedSchemaV1.self)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, migrationPlan: ShiHengMigrationPlan.self, configurations: configuration)
        container.mainContext.insert(meal(title: "synthetic restored meal"))
        try container.mainContext.save()
        return try LocalStoreBackupService.export(from: container)
    }

    private func removeFixtureStore(at url: URL) throws {
        // Called only for UUID-scoped temporary test databases after their containers are released.
        for target in [url, URL(fileURLWithPath: url.path + "-wal"), URL(fileURLWithPath: url.path + "-shm")] {
            if FileManager.default.fileExists(atPath: target.path) { try FileManager.default.removeItem(at: target) }
        }
    }

    private func createUnsupportedStore(at url: URL) throws {
        try autoreleasepool {
            let model = NSManagedObjectModel()
            let entity = NSEntityDescription()
            entity.name = "UnrecognizedSyntheticFixture"
            entity.managedObjectClassName = "NSManagedObject"
            let field = NSAttributeDescription()
            field.name = "value"
            field.attributeType = .stringAttributeType
            field.isOptional = true
            entity.properties = [field]
            model.entities = [entity]
            let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
            let store = try coordinator.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil, at: url, options: nil)
            try coordinator.remove(store)
        }
    }
}
