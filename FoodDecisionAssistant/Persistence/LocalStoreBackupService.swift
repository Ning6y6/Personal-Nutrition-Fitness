import Foundation
import SwiftData

/// All SwiftData access stays on the main actor. Only value records and URLs leave this service.
@MainActor
enum LocalStoreBackupService {
    private static let maximumArchiveBytes = 64 * 1_024 * 1_024
    /// Exports committed records through a fresh read context; never saves the shared UI context.
    static func export(from container: ModelContainer) throws -> Data {
        let hasHistory = includesGoalHistory(container)
        let document = LocalStoreBackupDocument(formatVersion: hasHistory ? 2 : 1,
            schemaVersion: hasHistory ? "2.0.0" : "1.0.0", createdAt: .now,
            records: try records(from: container))
        try document.validate()
        let data = try LocalStoreBackupCodec.encode(document)
        try validateSize(data)
        return data
    }

    static func inspect(data: Data) throws -> LocalStoreBackupSummary {
        try validateSize(data)
        let document = try LocalStoreBackupCodec.decode(data)
        try document.validate()
        let counts = Dictionary(uniqueKeysWithValues: LocalStoreBackupEntityKind.allCases.map { kind in
            (kind, document.records.filter { $0.entity == kind }.count)
        })
        // The archive includes references, never image bytes or files addressed by those references.
        // Do not dereference arbitrary paths from an imported archive.
        let references = Set(document.records.compactMap { record -> String? in
            let field: String
            switch record.entity {
            case .mealPhotoEstimate: field = "imageReference"
            case .reviewQueueItem: field = "sourceImageIdentifier"
            default: return nil
            }
            guard case let .string(reference) = record.fields[field], !reference.isEmpty else { return nil }
            return reference
        })
        return LocalStoreBackupSummary(
            totalRecords: document.records.count,
            counts: counts,
            imageWarnings: references.sorted().map { LocalStoreBackupImageWarning(reference: $0) }
        )
    }

    /// Restores only into a newly-created UUID directory. The current app container is not an input.
    /// The returned store has been closed, reopened and compared against every archived record.
    static func stageRestore(data: Data, directory: URL) throws -> URL {
        try stageRestore(data: data, directory: directory, legacyCandidate: false)
    }

    /// Only startup's protected upgrade uses a V1 candidate. The V1 source is never migrated.
    static func stageLegacyUpgrade(data: Data, directory: URL) throws -> URL {
        try stageRestore(data: data, directory: directory, legacyCandidate: true)
    }

    /// SwiftData read-only configurations can still change SQLite shared-memory sidecars.
    /// Copy all source files before any V1 reader opens them, then prove both the source and its
    /// snapshot match the initial fingerprints. Startup has no writer attached to this V1 source.
    /// The temporary reader never becomes an active store and its raw values are never logged.
    static func legacyArchive(from storeURL: URL, directory: URL) throws -> Data {
        guard storeURL.isFileURL, directory.isFileURL else { throw LocalStoreBackupError.invalidDirectory }
        guard try StoreSchemaCompatibility.recognizedVersion(at: storeURL) == .v1 else {
            throw StoreSchemaCompatibilityError.unrecognizedModelHashes
        }
        let snapshot = try LocalStoreFileSnapshot.make(from: storeURL, in: directory)
        defer { snapshot.remove() }
        let data = try autoreleasepool {
            let reader = try LocalStoreBackupRestoration.legacyContainer(at: snapshot.storeURL, allowsSave: false)
            return try export(from: reader)
        }
        try snapshot.verifySource(at: storeURL)
        return data
    }

    private static func stageRestore(data: Data, directory: URL, legacyCandidate: Bool) throws -> URL {
        try validateSize(data)
        let document = try LocalStoreBackupCodec.decode(data)
        try document.validate()
        try document.validateSQLiteRestoreValues()
        if legacyCandidate, document.formatVersion != 1 {
            throw LocalStoreBackupError.unsupportedVersion
        }
        guard directory.isFileURL else { throw LocalStoreBackupError.invalidDirectory }
        let stageDirectory = directory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let storeURL = stageDirectory.appendingPathComponent("restored.store")
        var directoryAttributes: [FileAttributeKey: Any] = [.posixPermissions: 0o700]
        #if os(iOS)
        directoryAttributes[.protectionKey] = FileProtectionType.completeUntilFirstUserAuthentication
        #endif
        try FileManager.default.createDirectory(
            at: stageDirectory, withIntermediateDirectories: true,
            attributes: directoryAttributes
        )

        do {
            let sourceURL = stageDirectory.appendingPathComponent("source-backup.shihengbackup")
            #if os(iOS)
            try data.write(to: sourceURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            #else
            try data.write(to: sourceURL, options: .atomic)
            #endif
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: sourceURL.path)
            try autoreleasepool {
                try LocalStoreBackupRestoration.write(document: document, storeURL: storeURL, legacyCandidate: legacyCandidate)
            }
            let restoredRecords = try autoreleasepool {
                let container = try legacyCandidate
                    ? LocalStoreBackupRestoration.legacyContainer(at: storeURL)
                    : LocalStoreBackupRestoration.container(at: storeURL)
                return try records(from: container)
            }
            guard restoredRecords == document.canonicalRecords else {
                throw LocalStoreBackupError.restoreVerificationFailed
            }
            for fileURL in try FileManager.default.contentsOfDirectory(
                at: stageDirectory, includingPropertiesForKeys: [.isRegularFileKey]
            ) where try fileURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true {
                var attributes: [FileAttributeKey: Any] = [.posixPermissions: 0o600]
                #if os(iOS)
                attributes[.protectionKey] = FileProtectionType.completeUntilFirstUserAuthentication
                #endif
                try FileManager.default.setAttributes(attributes, ofItemAtPath: fileURL.path)
            }
            return storeURL
        } catch {
            // This is only the unique staging directory created by this invocation, never a live store.
            try? FileManager.default.removeItem(at: stageDirectory)
            throw error
        }
    }

    private static func validateSize(_ data: Data) throws {
        guard data.count <= maximumArchiveBytes else { throw LocalStoreBackupError.backupTooLarge }
    }

    static func records(from container: ModelContainer) throws -> [LocalStoreBackupRecord] {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        var result: [LocalStoreBackupRecord] = []

        for row in try context.fetch(FetchDescriptor<PersistentGoalProfile>()) {
            result.append(.init(entity: .goalProfile, id: row.id, fields: [
                "effectiveFrom": .date(row.effectiveFrom.timeIntervalSinceReferenceDate),
                "energyKcal": .number(row.energyKcal), "proteinGrams": .number(row.proteinGrams),
                "carbohydrateGrams": .number(row.carbohydrateGrams), "fatGrams": .number(row.fatGrams),
                "saturatedFatLimitGrams": .optionalNumber(row.saturatedFatLimitGrams),
                "fibreGrams": .optionalNumber(row.fibreGrams),
            ]))
        }
        if includesGoalHistory(container) {
            for row in try context.fetch(FetchDescriptor<PersistentGoalVersion>()) {
                result.append(.init(entity: .goalVersion, id: row.id, fields: [
                    "effectiveDayKey": .integer(row.effectiveDayKey),
                    "effectiveFrom": .date(row.effectiveFrom.timeIntervalSinceReferenceDate),
                    "energyKcal": .number(row.energyKcal), "proteinGrams": .number(row.proteinGrams),
                    "carbohydrateGrams": .number(row.carbohydrateGrams), "fatGrams": .number(row.fatGrams),
                    "saturatedFatLimitGrams": .optionalNumber(row.saturatedFatLimitGrams),
                    "fibreGrams": .optionalNumber(row.fibreGrams), "sourceRawValue": .string(row.sourceRawValue),
                    "sourceNote": .optionalString(row.sourceNote),
                    "confirmedAt": .date(row.confirmedAt.timeIntervalSinceReferenceDate),
                    "timeZoneIdentifier": .string(row.timeZoneIdentifier),
                    "commitSequence": .integer(row.commitSequence), "policyVersion": .integer(row.policyVersion),
                ]))
            }
        }
        for row in try context.fetch(FetchDescriptor<PersistentFoodItem>()) {
            result.append(.init(entity: .foodItem, id: row.id, fields: [
                "name": .string(row.name), "categoryRawValue": .string(row.categoryRawValue),
                "energyKcalPer100Units": .number(row.energyKcalPer100Units),
                "fatGramsPer100Units": .number(row.fatGramsPer100Units),
                "saturatedFatGramsPer100Units": .number(row.saturatedFatGramsPer100Units),
                "carbohydrateGramsPer100Units": .number(row.carbohydrateGramsPer100Units),
                "sugarGramsPer100Units": .number(row.sugarGramsPer100Units),
                "proteinGramsPer100Units": .number(row.proteinGramsPer100Units),
                "saltGramsPer100Units": .number(row.saltGramsPer100Units),
                "fibreGramsPer100Units": .optionalNumber(row.fibreGramsPer100Units),
                "unit": .string(row.unit), "source": .string(row.source),
            ]))
        }
        for row in try context.fetch(FetchDescriptor<PersistentContainerProfile>()) {
            result.append(.init(entity: .containerProfile, id: row.id, fields: [
                "name": .string(row.name), "tareWeightGrams": .number(row.tareWeightGrams),
            ]))
        }
        for row in try context.fetch(FetchDescriptor<PersistentMealLog>()) {
            result.append(.init(entity: .mealLog, id: row.id, fields: [
                "eatenAt": .date(row.eatenAt.timeIntervalSinceReferenceDate), "title": .string(row.title),
                "consumedWeightGrams": .number(row.consumedWeightGrams),
                "energyKcal": .number(row.energyKcal), "fatGrams": .number(row.fatGrams),
                "saturatedFatGrams": .number(row.saturatedFatGrams),
                "carbohydrateGrams": .number(row.carbohydrateGrams), "sugarGrams": .number(row.sugarGrams),
                "proteinGrams": .number(row.proteinGrams), "saltGrams": .number(row.saltGrams),
                "fibreGrams": .optionalNumber(row.fibreGrams), "entryMethodRawValue": .string(row.entryMethodRawValue),
                "coverageStatusRawValue": .string(row.coverageStatusRawValue),
                "estimateEvidenceGradeRawValue": .string(row.estimateEvidenceGradeRawValue),
                "healthKitSyncVersion": .integer(row.healthKitSyncVersion),
            ], relationships: ["components": .toMany(row.components.map(\.id))]))
        }
        for row in try context.fetch(FetchDescriptor<PersistentMealComponent>()) {
            result.append(.init(entity: .mealComponent, id: row.id, fields: [
                "foodItemID": .uuid(row.foodItemID), "foodName": .string(row.foodName),
                "consumedWeightGrams": .number(row.consumedWeightGrams), "unit": .string(row.unit),
                "energyKcal": .number(row.energyKcal), "fatGrams": .number(row.fatGrams),
                "saturatedFatGrams": .number(row.saturatedFatGrams),
                "carbohydrateGrams": .number(row.carbohydrateGrams), "sugarGrams": .number(row.sugarGrams),
                "proteinGrams": .number(row.proteinGrams), "saltGrams": .number(row.saltGrams),
                "fibreGrams": .optionalNumber(row.fibreGrams), "sortIndex": .integer(row.sortIndex),
            ], relationships: ["meal": .toOne(row.meal?.id)]))
        }
        for row in try context.fetch(FetchDescriptor<PersistentReviewQueueItem>()) {
            result.append(.init(entity: .reviewQueueItem, id: row.id, fields: [
                "createdAt": .date(row.createdAt.timeIntervalSinceReferenceDate),
                "sourceImageIdentifier": .optionalString(row.sourceImageIdentifier),
                "missingFields": .stringArray(row.missingFields), "statusRawValue": .string(row.statusRawValue),
            ]))
        }
        for row in try context.fetch(FetchDescriptor<PersistentHealthKitSyncRecord>()) {
            result.append(.init(entity: .healthKitSyncRecord, id: row.id, fields: [
                "mealID": .uuid(row.mealID), "objectTypeRawValue": .string(row.objectTypeRawValue),
                "syncIdentifier": .string(row.syncIdentifier), "syncVersion": .integer(row.syncVersion),
                "healthKitUUID": .optionalUUID(row.healthKitUUID), "isDeleted": .bool(row.isDeleted),
            ]))
        }
        for row in try context.fetch(FetchDescriptor<PersistentMealPhotoEstimate>()) {
            result.append(.init(entity: .mealPhotoEstimate, id: row.id, fields: [
                "createdAt": .date(row.createdAt.timeIntervalSinceReferenceDate), "mealTitle": .string(row.mealTitle),
                "imageReference": .string(row.imageReference), "providerName": .string(row.providerName),
                "modelVersion": .string(row.modelVersion), "outputSchemaVersion": .string(row.outputSchemaVersion),
                "confirmationStatusRawValue": .string(row.confirmationStatusRawValue),
                "consumedShareRatio": .number(row.consumedShareRatio),
            ], relationships: [
                "components": .toMany(row.components.map(\.id)), "calibrations": .toMany(row.calibrations.map(\.id)),
            ]))
        }
        for row in try context.fetch(FetchDescriptor<PersistentMealPhotoComponent>()) {
            result.append(.init(entity: .mealPhotoComponent, id: row.id, fields: [
                "foodItemID": .optionalUUID(row.foodItemID), "templateID": .optionalString(row.templateID),
                "freeTextName": .string(row.freeTextName), "cookingMethodRawValue": .string(row.cookingMethodRawValue),
                "lowGrams": .number(row.lowGrams), "midpointGrams": .number(row.midpointGrams),
                "highGrams": .number(row.highGrams), "confidence": .number(row.confidence),
                "isHiddenOilOrSauce": .bool(row.isHiddenOilOrSauce),
                "userCorrectedWeightGrams": .optionalNumber(row.userCorrectedWeightGrams),
                "sortIndex": .integer(row.sortIndex),
            ], relationships: ["estimate": .toOne(row.estimate?.id)]))
        }
        for row in try context.fetch(FetchDescriptor<PersistentPortionCalibration>()) {
            result.append(.init(entity: .portionCalibration, id: row.id, fields: [
                "createdAt": .date(row.createdAt.timeIntervalSinceReferenceDate), "photoEstimateID": .uuid(row.photoEstimateID),
                "componentID": .optionalUUID(row.componentID), "estimatedWeightGrams": .number(row.estimatedWeightGrams),
                "actualWeightGrams": .number(row.actualWeightGrams), "sortIndex": .integer(row.sortIndex),
            ], relationships: ["estimate": .toOne(row.estimate?.id)]))
        }
        for row in try context.fetch(FetchDescriptor<PersistentMealTemplate>()) {
            result.append(.init(entity: .mealTemplate, id: row.id, fields: [
                "name": .string(row.name), "createdAt": .date(row.createdAt.timeIntervalSinceReferenceDate),
                "updatedAt": .date(row.updatedAt.timeIntervalSinceReferenceDate),
                "lastUsedAt": .optionalDate(row.lastUsedAt), "useCount": .integer(row.useCount),
            ], relationships: ["components": .toMany(row.components.map(\.id))]))
        }
        for row in try context.fetch(FetchDescriptor<PersistentMealTemplateComponent>()) {
            result.append(.init(entity: .mealTemplateComponent, id: row.id, fields: [
                "foodItemID": .uuid(row.foodItemID), "foodName": .string(row.foodName),
                "defaultWeightGrams": .number(row.defaultWeightGrams), "unit": .string(row.unit),
                "sortIndex": .integer(row.sortIndex),
            ], relationships: ["template": .toOne(row.template?.id)]))
        }
        return LocalStoreBackupDocument(createdAt: .now, records: result).canonicalRecords
    }

    private static func includesGoalHistory(_ container: ModelContainer) -> Bool {
        container.schema.entities.contains { $0.name == "PersistentGoalVersion" }
    }
}

private extension LocalStoreBackupValue {
    static func optionalNumber(_ value: Double?) -> Self { value.map(Self.number) ?? .null }
    static func optionalString(_ value: String?) -> Self { value.map(Self.string) ?? .null }
    static func optionalUUID(_ value: UUID?) -> Self { value.map(Self.uuid) ?? .null }
    static func optionalDate(_ value: Date?) -> Self { value.map { .date($0.timeIntervalSinceReferenceDate) } ?? .null }
}
