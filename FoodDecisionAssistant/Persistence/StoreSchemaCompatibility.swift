import CoreData
import Foundation

enum StoreSchemaCompatibilityError: Error, Equatable, LocalizedError {
    case storeMissing
    case metadataUnreadable
    case unrecognizedModelHashes

    var errorDescription: String? {
        switch self {
        case .storeMissing: "数据库文件不存在，未新建替代数据库。"
        case .metadataUnreadable: "无法只读检查数据库结构；原文件保留。"
        case .unrecognizedModelHashes: "数据库结构不属于已验证的十二实体版本；未执行自动迁移。"
        }
    }
}

/// Core Data is used only for its public, read-only SQLite metadata API: SwiftData does not expose
/// persisted entity hashes. Never attach this store to a Core Data coordinator or modify metadata.
enum StoreSchemaCompatibility {
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

    static func modelHashes(at storeURL: URL) throws -> [String: String] {
        guard storeURL.isFileURL, FileManager.default.fileExists(atPath: storeURL.path) else {
            throw StoreSchemaCompatibilityError.storeMissing
        }
        do {
            let metadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(
                ofType: NSSQLiteStoreType, at: storeURL,
                options: [NSReadOnlyPersistentStoreOption: true]
            )
            guard let hashes = metadata[NSStoreModelVersionHashesKey] as? [String: Data] else {
                throw StoreSchemaCompatibilityError.metadataUnreadable
            }
            return hashes.mapValues { $0.base64EncodedString() }
        } catch let error as StoreSchemaCompatibilityError {
            throw error
        } catch {
            // Framework error text can contain file paths and stored values; expose a safe diagnosis.
            throw StoreSchemaCompatibilityError.metadataUnreadable
        }
    }

    static func validateExistingStore(at storeURL: URL) throws {
        guard try modelHashes(at: storeURL) == frozenModelHashes else {
            throw StoreSchemaCompatibilityError.unrecognizedModelHashes
        }
    }
}
