import CryptoKit
import Foundation

struct LocalStoreSnapshotFileChange: Equatable, Sendable {
    enum File: String, Sendable { case main, wal, shm }
    enum Kind: String, Sendable { case created, removed, contentChanged }
    let file: File
    let kind: Kind
}

enum LocalStoreFileSnapshotError: Error, Equatable {
    case sourceChanged([LocalStoreSnapshotFileChange])
    case copiedFilesMismatch
}

/// Frameworks can update SQLite shared-memory files even during read-only inspection. Only a
/// protected, unique copy is passed to those readers. Raw source files are never opened by SQLite.
enum LocalStoreFileSnapshot {
    struct Snapshot: Sendable {
        let directory: URL
        let storeURL: URL
        private let originalFingerprints: [String: Data]

        fileprivate init(directory: URL, storeURL: URL, originalFingerprints: [String: Data]) {
            self.directory = directory
            self.storeURL = storeURL
            self.originalFingerprints = originalFingerprints
        }

        func verifySource(at sourceURL: URL) throws {
            let current = try LocalStoreFileSnapshot.fingerprints(at: sourceURL)
            let changes = LocalStoreFileSnapshot.changes(from: originalFingerprints, to: current)
            guard changes.isEmpty else { throw LocalStoreFileSnapshotError.sourceChanged(changes) }
        }

        func remove() { try? FileManager.default.removeItem(at: directory) }
    }

    static func make(from sourceURL: URL, in parentDirectory: URL) throws -> Snapshot {
        guard sourceURL.isFileURL, parentDirectory.isFileURL else { throw LocalStoreBackupError.invalidDirectory }
        let initial = try fingerprints(at: sourceURL)
        guard initial[""] != nil else { throw StoreSchemaCompatibilityError.storeMissing }
        let directory = parentDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let storeURL = directory.appendingPathComponent("snapshot.store")
        var directoryAttributes: [FileAttributeKey: Any] = [.posixPermissions: 0o700]
        #if os(iOS)
        directoryAttributes[.protectionKey] = FileProtectionType.completeUntilFirstUserAuthentication
        #endif
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: directoryAttributes)
        do {
            for suffix in initial.keys.sorted() {
                let source = URL(fileURLWithPath: sourceURL.path + suffix)
                let target = URL(fileURLWithPath: storeURL.path + suffix)
                try FileManager.default.copyItem(at: source, to: target)
                var attributes: [FileAttributeKey: Any] = [.posixPermissions: 0o600]
                #if os(iOS)
                attributes[.protectionKey] = FileProtectionType.completeUntilFirstUserAuthentication
                #endif
                try FileManager.default.setAttributes(attributes, ofItemAtPath: target.path)
            }
            let sourceChanges = changes(from: initial, to: try fingerprints(at: sourceURL))
            guard sourceChanges.isEmpty else { throw LocalStoreFileSnapshotError.sourceChanged(sourceChanges) }
            guard try fingerprints(at: storeURL) == initial else { throw LocalStoreFileSnapshotError.copiedFilesMismatch }
            return Snapshot(directory: directory, storeURL: storeURL, originalFingerprints: initial)
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    private static func changes(from before: [String: Data], to after: [String: Data]) -> [LocalStoreSnapshotFileChange] {
        let files: [(String, LocalStoreSnapshotFileChange.File)] = [("", .main), ("-wal", .wal), ("-shm", .shm)]
        return files.compactMap { suffix, file in
            switch (before[suffix], after[suffix]) {
            case (nil, .some): return LocalStoreSnapshotFileChange(file: file, kind: .created)
            case (.some, nil): return LocalStoreSnapshotFileChange(file: file, kind: .removed)
            case let (.some(old), .some(new)) where old != new:
                return LocalStoreSnapshotFileChange(file: file, kind: .contentChanged)
            default: return nil
            }
        }
    }

    private static func fingerprints(at storeURL: URL) throws -> [String: Data] {
        var result: [String: Data] = [:]
        for suffix in ["", "-wal", "-shm"] {
            let url = URL(fileURLWithPath: storeURL.path + suffix)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            guard try FileManager.default.attributesOfItem(atPath: url.path)[.type] as? FileAttributeType == .typeRegular else {
                throw LocalStoreBootstrapError.unsafeStorePath
            }
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            var hash = SHA256()
            while let chunk = try handle.read(upToCount: 64 * 1_024), !chunk.isEmpty {
                hash.update(data: chunk)
            }
            result[suffix] = Data(hash.finalize())
        }
        return result
    }
}
