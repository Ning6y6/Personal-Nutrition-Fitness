import FoodDecisionCore
import Foundation
import SwiftData
import Testing

@testable import FoodDecisionAssistant

@MainActor
struct GoalHistoryBackupTests {
    @Test("A format-one backup restores all original records into V2 with unknown past goals")
    func legacyBackupRestoresWithoutInventingHistory() throws {
        let fixture = try GoalHistoryStoreFixture()
        defer { fixture.remove() }
        try fixture.atPhase("seedV1") { try fixture.seedLegacyStore() }
        let original = try fixture.atPhase("exportV1Snapshot") { try fixture.legacyDocument() }
        #expect(original.formatVersion == 1)
        #expect(original.schemaVersion == "1.0.0")
        let restoredURL = try fixture.atPhase("restoreV1ArchiveToV2") {
            try LocalStoreBackupService.stageRestore(data: LocalStoreBackupCodec.encode(original), directory: fixture.restoreDirectory)
        }
        let reopened = try fixture.atPhase("reopenRestoredV2") { try LocalStoreBackupRestoration.container(at: restoredURL) }
        let recognized = try fixture.atPhase("inspectRestoredV2") { try StoreSchemaCompatibility.recognizedVersion(at: restoredURL) }
        #expect(recognized == .v2)
        #expect(try LocalStoreBackupService.records(from: reopened) == original.canonicalRecords)
        #expect(try reopened.mainContext.fetchCount(FetchDescriptor<PersistentGoalVersion>()) == 0)
    }

    @Test("Format-two backup preserves goal source, dates, sequence, nil and explicit zero after reopening")
    func versionedBackupRoundTrip() throws {
        let fixture = try GoalHistoryStoreFixture()
        defer { fixture.remove() }
        let current = try LocalStoreBootstrap.openStore(at: fixture.defaultStoreURL)
        let version = try fixture.version()
        current.mainContext.insert(PersistentGoalVersion(domain: version))
        try current.mainContext.save()
        let data = try LocalStoreBackupService.export(from: current)
        let document = try LocalStoreBackupCodec.decode(data)
        #expect(document.formatVersion == 2)
        #expect(document.schemaVersion == "2.0.0")
        let url = try LocalStoreBackupService.stageRestore(data: data, directory: fixture.restoreDirectory)
        let restored = try LocalStoreBackupRestoration.container(at: url)
        #expect(try LocalStoreBackupService.records(from: restored) == document.canonicalRecords)
        let row = try #require(restored.mainContext.fetch(FetchDescriptor<PersistentGoalVersion>()).first)
        #expect(try row.domainModel == version)
        #expect(row.fibreGrams == nil)
        #expect(row.saturatedFatLimitGrams == 0)
    }

    @Test("V1 cannot smuggle a goal-version entity and mixed version pairs are rejected")
    func archiveVersionPairsAreClosed() throws {
        let fixture = try GoalHistoryStoreFixture()
        defer { fixture.remove() }
        let current = try LocalStoreBootstrap.openStore(at: fixture.defaultStoreURL)
        current.mainContext.insert(PersistentGoalVersion(domain: try fixture.version()))
        try current.mainContext.save()
        var document = try LocalStoreBackupCodec.decode(LocalStoreBackupService.export(from: current))
        document.formatVersion = 1
        document.schemaVersion = "1.0.0"
        #expect(throws: LocalStoreBackupError.unsupportedVersion) { try document.validate() }
        document.records = []
        document.schemaVersion = "2.0.0"
        #expect(throws: LocalStoreBackupError.unsupportedVersion) { try document.validate() }
        document.formatVersion = 2
        document.schemaVersion = "1.0.0"
        #expect(throws: LocalStoreBackupError.unsupportedVersion) { try document.validate() }
    }

    @Test("A restored raw unknown source remains archived and is refused by formal goal reads")
    func unknownRawSourceIsPreserved() throws {
        let fixture = try GoalHistoryStoreFixture()
        defer { fixture.remove() }
        let current = try LocalStoreBootstrap.openStore(at: fixture.defaultStoreURL)
        let row = PersistentGoalVersion(domain: try fixture.version())
        row.sourceRawValue = "future_unknown_source"
        current.mainContext.insert(row)
        try current.mainContext.save()
        let data = try LocalStoreBackupService.export(from: current)
        let restored = try LocalStoreBackupRestoration.container(at: LocalStoreBackupService.stageRestore(data: data, directory: fixture.restoreDirectory))
        let raw = try #require(restored.mainContext.fetch(FetchDescriptor<PersistentGoalVersion>()).first)
        #expect(raw.sourceRawValue == "future_unknown_source")
        #expect(throws: PersistentDomainConversionError.unknownEnum(entity: .goalVersion, id: row.id, field: "sourceRawValue")) { _ = try raw.domainModel }
        #expect(try LocalStoreBackupService.records(from: restored) == LocalStoreBackupCodec.decode(data).canonicalRecords)
    }
}
