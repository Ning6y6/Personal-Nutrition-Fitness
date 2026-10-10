import Darwin
import Foundation
import Observation
import SwiftData

enum LocalStoreBootstrapError: Error, Equatable, LocalizedError {
    case invalidConfiguration
    case invalidSelection
    case unsupportedSelectionVersion
    case missingSelectedStore
    case orphanedStoreSidecars
    case unsafeStorePath
    case storePathUnreadable
    case openFailed
    case backupUnavailable
    case invalidBackup
    case restoredStoreMismatch
    case unsavedChanges
    case selectionWriteFailed
    case fileProtectionFailed

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration: "本地数据库位置配置无效，未打开其他数据库。"
        case .invalidSelection: "数据库选择文件损坏或内容无效，未忽略该文件或新建空库。"
        case .unsupportedSelectionVersion: "数据库选择文件版本不受支持，原选择保留。"
        case .missingSelectedStore: "曾使用的数据库文件已丢失，未自动建立空数据库。请重试或使用备份。"
        case .orphanedStoreSidecars: "主数据库缺失但日志文件仍存在；未新建或覆盖数据库。"
        case .unsafeStorePath: "数据库路径不安全：不接受 App 数据目录之外的路径、符号链接或路径跳转。原数据保留。"
        case .storePathUnreadable: "无法读取 App 数据目录或文件属性，可能是权限或文件访问状态问题。原数据保留，请解锁设备后重试；不会自动新建空库。"
        case .openFailed: "数据库打开失败，原数据库和原选择均保留。"
        case .backupUnavailable: "恢复库缺少对应的原始备份文件，无法再次核对。"
        case .invalidBackup: "对应的原始备份无法通过结构校验，未切换数据库。"
        case .restoredStoreMismatch: "恢复库记录与原始备份不一致，未切换数据库。"
        case .unsavedChanges: "当前数据库有尚未保存的修改，请先保存或取消修改再切换。"
        case .selectionWriteFailed: "无法原子保存数据库选择，仍使用原数据库。"
        case .fileProtectionFailed: "无法设置本地文件保护，未切换数据库。"
        }
    }
}

/// A small selection record is not a data backup. It contains no paths, meal values or secrets.
struct LocalStoreSelection: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Equatable, Sendable { case defaultStore, restoredStore }
    var version = 1
    var kind: Kind
    var restoreDirectoryID: String?

    func validate() throws {
        guard version == 1 else { throw LocalStoreBootstrapError.unsupportedSelectionVersion }
        switch kind {
        case .defaultStore:
            guard restoreDirectoryID == nil else { throw LocalStoreBootstrapError.invalidSelection }
        case .restoredStore:
            guard let restoreDirectoryID, let id = UUID(uuidString: restoreDirectoryID),
                  id.uuidString == restoreDirectoryID else {
                throw LocalStoreBootstrapError.invalidSelection
            }
        }
    }
}

/// No ModelContext or @Model object crosses an actor boundary. Failure never manufactures a
/// fallback container; successful activation rebuilds the view tree through `generation`.
@MainActor
@Observable
final class LocalStoreBootstrap {
    private(set) var container: ModelContainer?
    private(set) var failure: (any Error)?
    private(set) var generation = UUID()
    private(set) var activeStoreURL: URL?
    let restoreDirectory: URL

    @ObservationIgnored private let defaultStoreURL: URL
    @ObservationIgnored private let selectionURL: URL
    @ObservationIgnored private let pathValidator: LocalStorePathValidator
    @ObservationIgnored private let opener: @MainActor (URL) throws -> ModelContainer

    init(
        defaultStoreURL: URL? = nil,
        restoreDirectory: URL? = nil,
        selectionURL: URL? = nil,
        pathValidator: LocalStorePathValidator = LocalStorePathValidator(),
        opener: @escaping @MainActor (URL) throws -> ModelContainer = LocalStoreBootstrap.openStore
    ) {
        // Keep precisely the default location used before startup protection was introduced.
        let schema = Schema(versionedSchema: VersionedSchemaV2.self)
        self.defaultStoreURL = defaultStoreURL ?? ModelConfiguration(schema: schema, cloudKitDatabase: .none).url
        self.restoreDirectory = restoreDirectory ?? URL.applicationSupportDirectory.appendingPathComponent("BackupVerification", isDirectory: true)
        self.selectionURL = selectionURL ?? URL.applicationSupportDirectory.appendingPathComponent("active-store.json")
        self.pathValidator = pathValidator
        self.opener = opener
        retry()
    }

    static func openStore(at storeURL: URL) throws -> ModelContainer {
        let schema = Schema(versionedSchema: VersionedSchemaV2.self)
        let configuration = ModelConfiguration(schema: schema, url: storeURL, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, migrationPlan: ShiHengMigrationPlan.self, configurations: configuration)
    }

    func retry() {
        do {
            try ensureNoUnsavedChanges()
            let selection = try readSelection()
            let url: URL
            switch selection?.kind {
            case .restoredStore:
                guard let directoryID = selection?.restoreDirectoryID else { throw LocalStoreBootstrapError.invalidSelection }
                url = restoreDirectory.appendingPathComponent(directoryID, isDirectory: true).appendingPathComponent("restored.store")
                try validateRestoredPath(url, requireBackup: false)
                guard FileManager.default.fileExists(atPath: url.path) else { throw LocalStoreBootstrapError.missingSelectedStore }
            case .defaultStore, .none:
                url = defaultStoreURL
                try validateStoreFiles(url)
                if !FileManager.default.fileExists(atPath: url.path) {
                    if selection != nil { throw LocalStoreBootstrapError.missingSelectedStore }
                    if sidecarURLs(for: url).contains(where: { FileManager.default.fileExists(atPath: $0.path) }) {
                        throw LocalStoreBootstrapError.orphanedStoreSidecars
                    }
                }
            }
            if FileManager.default.fileExists(atPath: url.path),
               try StoreSchemaCompatibility.recognizedVersion(at: url) == .v1 {
                // Upgrade only a newly reconstructed candidate. Even the V1 logical reader opens
                // a protected snapshot, because a read-only SQLite reader can change sidecars.
                try upgradeLegacyStore(at: url)
                return
            }
            let candidate = try openCheckedStore(at: url)
            try protectStoreFiles(at: url)
            // Mark even the default store as seen. Its later loss must not look like first install.
            if selection == nil {
                try writeSelection(LocalStoreSelection(kind: .defaultStore))
            }
            container = candidate
            activeStoreURL = url
            failure = nil
            generation = UUID()
        } catch {
            failure = safeError(error)
        }
    }

    func activateRestoredStore(at storeURL: URL) throws {
        try activateVerifiedStore(at: storeURL, allowLegacyMigration: false)
    }

    /// The same verification and atomic publication protect both user-requested recovery and
    /// automatic schema upgrades. A schema upgrade is not a user confirmation of nutrition goals.
    private func activateVerifiedStore(at storeURL: URL, allowLegacyMigration: Bool) throws {
        do {
            try ensureNoUnsavedChanges()
            try validateRestoredPath(storeURL, requireBackup: true)
            guard FileManager.default.fileExists(atPath: storeURL.path) else { throw LocalStoreBootstrapError.missingSelectedStore }
            let backupURL = storeURL.deletingLastPathComponent().appendingPathComponent("source-backup.shihengbackup")
            let document = try readSourceBackup(at: backupURL)
            if allowLegacyMigration, document.formatVersion != 1 {
                throw LocalStoreBootstrapError.invalidBackup
            }
            if allowLegacyMigration {
                // Migration and its first comparison use a temporary container. Release it before
                // reopening with V2 only; no selection is published until disk reopen also agrees.
                try autoreleasepool {
                    let migrated = try openCheckedStore(at: storeURL, allowLegacyMigration: true)
                    guard try LocalStoreBackupService.records(from: migrated) == document.canonicalRecords else {
                        throw LocalStoreBootstrapError.restoredStoreMismatch
                    }
                }
            }
            let candidate = try openCheckedStore(at: storeURL)
            guard try LocalStoreBackupService.records(from: candidate) == document.canonicalRecords else {
                throw LocalStoreBootstrapError.restoredStoreMismatch
            }
            try protectStoreFiles(at: storeURL)
            try protect(backupURL, directory: false)
            let directoryID = storeURL.deletingLastPathComponent().lastPathComponent
            try writeSelection(LocalStoreSelection(kind: .restoredStore, restoreDirectoryID: directoryID))
            // Atomic pointer publication is the final throwable operation. Do not add work here
            // that could fail and leave a new persisted pointer with an old in-memory container.
            container = candidate
            activeStoreURL = storeURL
            failure = nil
            generation = UUID()
        } catch {
            // A failed activation must leave the prior container, pointer and generation intact.
            throw safeError(error)
        }
    }

    private func upgradeLegacyStore(at sourceURL: URL) throws {
        try protectStoreFiles(at: sourceURL)
        try validateNoSymbolicLinks(restoreDirectory)
        let archive: Data
        do {
            archive = try LocalStoreBackupService.legacyArchive(from: sourceURL, directory: restoreDirectory)
        } catch { throw LocalStoreBootstrapError.openFailed }
        let candidateURL: URL
        do {
            candidateURL = try LocalStoreBackupService.stageLegacyUpgrade(data: archive, directory: restoreDirectory)
        } catch { throw LocalStoreBootstrapError.openFailed }
        // Failure leaves the source and prior selection untouched. Retain this protected
        // candidate's original archive for recovery; never clean up the selected source here.
        try activateVerifiedStore(at: candidateURL, allowLegacyMigration: true)
    }

    private func ensureNoUnsavedChanges() throws {
        guard container?.mainContext.hasChanges != true else { throw LocalStoreBootstrapError.unsavedChanges }
    }

    private func openCheckedStore(at url: URL, allowLegacyMigration: Bool = false) throws -> ModelContainer {
        if FileManager.default.fileExists(atPath: url.path) {
            let version = try StoreSchemaCompatibility.recognizedVersion(at: url)
            guard version == .v2 || allowLegacyMigration else {
                throw StoreSchemaCompatibilityError.unrecognizedModelHashes
            }
            try protectStoreFiles(at: url)
        } else {
            // Parent protection is set before SQLite creates any sensitive file.
            let directory = url.deletingLastPathComponent()
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            } catch { throw LocalStoreBootstrapError.fileProtectionFailed }
            try protect(directory, directory: true)
        }
        let opened: ModelContainer
        do { opened = try opener(url) }
        catch { throw LocalStoreBootstrapError.openFailed }
        // Both a newly created store and a migrated candidate must match the exact V2 manifest.
        try StoreSchemaCompatibility.validateLatestStore(at: url)
        return opened
    }

    private func readSelection() throws -> LocalStoreSelection? {
        try validateNoSymbolicLinks(selectionURL)
        guard FileManager.default.fileExists(atPath: selectionURL.path) else { return nil }
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: selectionURL.path)
            guard attributes[.type] as? FileAttributeType == .typeRegular,
                  let size = attributes[.size] as? NSNumber, size.intValue <= 4_096 else {
                throw LocalStoreBootstrapError.invalidSelection
            }
            let selection = try JSONDecoder().decode(LocalStoreSelection.self, from: Data(contentsOf: selectionURL))
            try selection.validate()
            return selection
        } catch let error as LocalStoreBootstrapError { throw error }
        catch { throw LocalStoreBootstrapError.invalidSelection }
    }

    private func readSourceBackup(at url: URL) throws -> LocalStoreBackupDocument {
        guard FileManager.default.fileExists(atPath: url.path) else { throw LocalStoreBootstrapError.backupUnavailable }
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            guard attributes[.type] as? FileAttributeType == .typeRegular,
                  let size = attributes[.size] as? NSNumber, size.intValue <= 64 * 1_024 * 1_024 else {
                throw LocalStoreBootstrapError.invalidBackup
            }
            let data = try Data(contentsOf: url)
            _ = try LocalStoreBackupService.inspect(data: data)
            let document = try LocalStoreBackupCodec.decode(data)
            try document.validateSQLiteRestoreValues()
            return document
        } catch let error as LocalStoreBootstrapError { throw error }
        catch { throw LocalStoreBootstrapError.invalidBackup }
    }

    private func validateRestoredPath(_ url: URL, requireBackup: Bool) throws {
        guard url.isFileURL, restoreDirectory.isFileURL,
              url.lastPathComponent == "restored.store" else { throw LocalStoreBootstrapError.unsafeStorePath }
        let directory = url.deletingLastPathComponent()
        let directoryID = directory.lastPathComponent
        let relativeStore = try pathValidator.relativeComponents(for: url)
        let relativeRestoreRoot = try pathValidator.relativeComponents(for: restoreDirectory)
        guard let id = UUID(uuidString: directoryID), id.uuidString == directoryID,
              relativeStore.count == relativeRestoreRoot.count + 2,
              relativeStore.starts(with: relativeRestoreRoot) else {
            throw LocalStoreBootstrapError.unsafeStorePath
        }
        try validateNoSymbolicLinks(restoreDirectory)
        try validateStoreFiles(url)
        if requireBackup {
            try validateNoSymbolicLinks(directory.appendingPathComponent("source-backup.shihengbackup"))
        }
    }

    private func validateStoreFiles(_ url: URL) throws {
        guard url.isFileURL else { throw LocalStoreBootstrapError.invalidConfiguration }
        for file in [url] + sidecarURLs(for: url) {
            try validateNoSymbolicLinks(file)
            if FileManager.default.fileExists(atPath: file.path),
               try FileManager.default.attributesOfItem(atPath: file.path)[.type] as? FileAttributeType != .typeRegular {
                throw LocalStoreBootstrapError.unsafeStorePath
            }
        }
    }

    private func validateNoSymbolicLinks(_ url: URL) throws {
        try pathValidator.validate(url)
    }

    private func sidecarURLs(for url: URL) -> [URL] {
        [URL(fileURLWithPath: url.path + "-wal"), URL(fileURLWithPath: url.path + "-shm")]
    }

    private func protectStoreFiles(at url: URL) throws {
        try validateStoreFiles(url)
        try protect(url.deletingLastPathComponent(), directory: true)
        for file in [url] + sidecarURLs(for: url) where FileManager.default.fileExists(atPath: file.path) {
            try protect(file, directory: false)
        }
    }

    private func protect(_ url: URL, directory: Bool) throws {
        var attributes: [FileAttributeKey: Any] = [.posixPermissions: directory ? 0o700 : 0o600]
        #if os(iOS)
        attributes[.protectionKey] = FileProtectionType.completeUntilFirstUserAuthentication
        #endif
        do { try FileManager.default.setAttributes(attributes, ofItemAtPath: url.path) }
        catch { throw LocalStoreBootstrapError.fileProtectionFailed }
    }

    private func writeSelection(_ selection: LocalStoreSelection) throws {
        try selection.validate()
        try validateNoSymbolicLinks(selectionURL)
        let directory = selectionURL.deletingLastPathComponent()
        let temporaryURL = directory.appendingPathComponent(".active-store-\(UUID().uuidString).tmp")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try protect(directory, directory: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            try encoder.encode(selection).write(to: temporaryURL, options: .atomic)
            defer { try? FileManager.default.removeItem(at: temporaryURL) }
            try protect(temporaryURL, directory: false)
            let handle = try FileHandle(forWritingTo: temporaryURL)
            do { try handle.synchronize(); try handle.close() }
            catch { try? handle.close(); throw error }
            // POSIX rename is an atomic replacement on the same filesystem. After it succeeds,
            // neither a chmod nor any other throwing operation may precede the state assignment.
            guard Darwin.rename(temporaryURL.path, selectionURL.path) == 0 else {
                throw LocalStoreBootstrapError.selectionWriteFailed
            }
        } catch {
            throw LocalStoreBootstrapError.selectionWriteFailed
        }
    }

    private func safeError(_ error: any Error) -> any Error {
        if let error = error as? LocalStoreBootstrapError { return error }
        if let error = error as? StoreSchemaCompatibilityError { return error }
        return LocalStoreBootstrapError.openFailed
    }
}
