import CoreData
import Foundation

enum StoreSchemaCompatibilityError: Error, Equatable, LocalizedError {
    case storeMissing
    case metadataUnreadable
    case unrecognizedModelHashes
    case storeChangedDuringInspection([LocalStoreSnapshotFileChange])
    case snapshotMismatch
    case snapshotUnavailable

    var errorDescription: String? {
        switch self {
        case .storeMissing: "数据库文件不存在，未新建替代数据库。"
        case .metadataUnreadable: "无法只读检查数据库结构；原文件保留。"
        case .unrecognizedModelHashes: "数据库结构不属于已验证的版本；未执行自动迁移。"
        case .storeChangedDuringInspection: "检查期间数据库文件发生变化，未继续迁移；原数据保留，请重试。"
        case .snapshotMismatch: "数据库检查副本与原件不一致，未继续迁移；原数据保留。"
        case .snapshotUnavailable: "无法建立受保护的数据库检查副本，可能是权限或文件访问状态问题；原数据保留。"
        }
    }
}

/// Core Data is used only for its public, read-only metadata API on a protected snapshot: SwiftData
/// does not expose persisted entity hashes. Never attach a source store to a coordinator. Even this
/// read-only metadata API can modify SQLite SHM bytes, so it never receives the source URL.
enum StoreSchemaCompatibility {
    enum RecognizedVersion: Equatable, Sendable { case v1, v2 }

    static let frozenModelHashes: [String: String] = [
        "PersistentContainerProfile": "BfHLX6cnsZn9e4tl2HW3cTRDa5urr1FzOXt1gcJkrac=",
        "PersistentFoodItem": "QLnH1IH3Y02xwA9jcDz0YeOX4G9hN8mIoF1NQ2zWhvI=",
        "PersistentGoalProfile": "cL/DXd/jVMnafFzTd98RmszsDqtFHEVTQDvQjZT86KY=",
        "PersistentHealthKitSyncRecord": "iplz9NTbO6mhyCi7G2Uy48fqAm3yKh2L50U7pk7Z23c=",
        "PersistentMealComponent": "skugt85oCrrmZX48dZ4KodKC/GJ0ESWi1wH5Zc+E3fA=",
        "PersistentMealLog": "O/NoWUM0A2Ybiy1cAN/jSekDlc7KOc4rvQzVu0RqVXM=",
        "PersistentMealPhotoComponent": "fIjzmKSqJyrW8JKYTBgWZP/eOK6wgNF7d/p6vJzfNAc=",
        "PersistentMealPhotoEstimate": "EqtNsOcwWPzAR+FND8aQZdQ6c0jhyDsTZbhgFXwyNWA=",
        "PersistentMealTemplate": "P8f2adWsC6nokCt12aoCdRWmoFIRw0/pdYPxtCU4p6w=",
        "PersistentMealTemplateComponent": "wMXtwOd+NshwvOOAbSpVuchpT9P9P4f9BCnVH33l6jQ=",
        "PersistentPortionCalibration": "gEAl0eUIHKDbV8gwHgSAJfbAN04GSrYYdfbU/cGENOk=",
        "PersistentReviewQueueItem": "31wjqtjn5wUj8ChWA9yoDBytZQmRxcbzV6+Nl4zTWtw=",
    ]

    /// Never replace the V1 compatibility manifest with the latest schema's hashes.
    static let latestModelHashes: [String: String] = frozenModelHashes.merging([
        "PersistentGoalVersion": "Y7DiMrEHfjPK27JllwoOXitq/gVrUUZFo4NtMl96v4A=",
    ]) { _, new in new }

    static func modelHashes(at storeURL: URL) throws -> [String: String] {
        guard storeURL.isFileURL, FileManager.default.fileExists(atPath: storeURL.path) else {
            throw StoreSchemaCompatibilityError.storeMissing
        }
        do {
            let snapshot: LocalStoreFileSnapshot.Snapshot
            do {
                snapshot = try LocalStoreFileSnapshot.make(from: storeURL, in: FileManager.default.temporaryDirectory)
            } catch let error as LocalStoreFileSnapshotError {
                throw safeSnapshotError(error)
            } catch {
                throw StoreSchemaCompatibilityError.snapshotUnavailable
            }
            defer { snapshot.remove() }
            let metadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(
                ofType: NSSQLiteStoreType, at: snapshot.storeURL,
                options: [NSReadOnlyPersistentStoreOption: true]
            )
            guard let hashes = metadata[NSStoreModelVersionHashesKey] as? [String: Data] else {
                throw StoreSchemaCompatibilityError.metadataUnreadable
            }
            do { try snapshot.verifySource(at: storeURL) }
            catch let error as LocalStoreFileSnapshotError { throw safeSnapshotError(error) }
            catch { throw StoreSchemaCompatibilityError.snapshotUnavailable }
            return hashes.mapValues { $0.base64EncodedString() }
        } catch let error as StoreSchemaCompatibilityError {
            throw error
        } catch {
            // Framework error text can contain file paths and stored values; expose a safe diagnosis.
            throw StoreSchemaCompatibilityError.metadataUnreadable
        }
    }

    private static func safeSnapshotError(_ error: LocalStoreFileSnapshotError) -> StoreSchemaCompatibilityError {
        switch error {
        case let .sourceChanged(changes): .storeChangedDuringInspection(changes)
        case .copiedFilesMismatch: .snapshotMismatch
        }
    }

    static func validateExistingStore(at storeURL: URL) throws {
        _ = try recognizedVersion(at: storeURL)
    }

    static func recognizedVersion(at storeURL: URL) throws -> RecognizedVersion {
        let hashes = try modelHashes(at: storeURL)
        if hashes == frozenModelHashes { return .v1 }
        if hashes == latestModelHashes { return .v2 }
        throw StoreSchemaCompatibilityError.unrecognizedModelHashes
    }

    static func validateLatestStore(at storeURL: URL) throws {
        guard try recognizedVersion(at: storeURL) == .v2 else {
            throw StoreSchemaCompatibilityError.unrecognizedModelHashes
        }
    }
}
