// Developer-only OPT-07 probe. Compile with the app persistence files and Core package.
// Never include this file in the app target. Only operate on a disposable working copy.
import CoreData
import Foundation
import SwiftData

@main
@MainActor
struct StoreProtectionProbe {
    static func main() {
        do {
            try verify()
        } catch {
            // Do not let thrown record errors expose personal UUIDs/field contents in logs.
            let message = "Protected-store verification failed (\(type(of: error))); private contents omitted.\n"
            FileHandle.standardError.write(Data(message.utf8))
            exit(1)
        }
    }

    private static func verify() throws {
        guard CommandLine.arguments.count == 3 else {
            throw ProbeError.arguments
        }
        let source = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let output = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
        let files = FileManager.default
        guard !files.fileExists(atPath: output.path) else { throw ProbeError.outputExists }
        try files.createDirectory(at: output, withIntermediateDirectories: true)
        try files.setAttributes([.posixPermissions: 0o700], ofItemAtPath: output.path)

        // Copy first: never let SwiftData migrate, checkpoint or mutate the protection sample.
        let working = output.appending(path: "working", directoryHint: .isDirectory)
        try files.copyItem(at: source, to: working)
        try files.setAttributes([.posixPermissions: 0o700], ofItemAtPath: working.path)
        for file in try files.contentsOfDirectory(at: working, includingPropertiesForKeys: nil) {
            try files.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        }
        let oldURL = working.appending(path: "default.store")
        let oldHashes = try hashes(at: oldURL)
        let currentURL = output.appending(path: "current-schema.store")
        try createCurrentStore(at: currentURL)
        let currentHashes = try hashes(at: currentURL)
        guard oldHashes == currentHashes else { throw ProbeError.unidentifiedSchema }
        print("Schema hashes match current V1: \(oldHashes.count) entities")

        let originalData = try exportStore(at: oldURL)
        let backupURL = output.appending(path: "protected-backup.json")
        try originalData.write(to: backupURL, options: .atomic)
        try files.setAttributes([.posixPermissions: 0o600], ofItemAtPath: backupURL.path)
        let restoredURL = try LocalStoreBackupService.stageRestore(data: originalData, directory: output)
        let restoredData = try exportStore(at: restoredURL)
        let original = try LocalStoreBackupCodec.decode(originalData)
        let restored = try LocalStoreBackupCodec.decode(restoredData)
        guard original.records == restored.records else { throw ProbeError.recordMismatch }
        print("Protected sample export/restore/reopen: identical records and relationships")
        print("Record count: \(original.records.count); record contents intentionally omitted")
    }

    private static func hashes(at url: URL) throws -> [String: Data] {
        // SwiftData exposes no equivalent public read-only on-disk model-hash inspection.
        let metadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(
            ofType: NSSQLiteStoreType, at: url,
            options: [NSReadOnlyPersistentStoreOption: true]
        )
        guard let hashes = metadata["NSStoreModelVersionHashes"] as? [String: Data] else {
            throw ProbeError.unidentifiedSchema
        }
        return hashes
    }

    private static func createCurrentStore(at url: URL) throws {
        let schema = Schema(versionedSchema: VersionedSchemaV1.self)
        let configuration = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        try container.mainContext.save()
    }

    private static func exportStore(at url: URL) throws -> Data {
        let schema = Schema(versionedSchema: VersionedSchemaV1.self)
        let configuration = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        return try LocalStoreBackupService.export(from: container)
    }

    enum ProbeError: Error {
        case arguments, outputExists, unidentifiedSchema, recordMismatch
    }
}
