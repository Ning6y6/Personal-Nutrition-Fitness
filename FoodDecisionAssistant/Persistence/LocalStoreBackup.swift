import Foundation

/// A closed, versioned archive of stored values, rather than reconstructed domain models.
struct LocalStoreBackupDocument: Codable, Equatable, Sendable {
    var formatVersion = 1
    var schemaVersion = "1.0.0"
    var createdAt: Date
    var records: [LocalStoreBackupRecord]
}

enum LocalStoreBackupEntityKind: String, Codable, CaseIterable, Sendable {
    case goalProfile, foodItem, containerProfile, mealLog, mealComponent
    case reviewQueueItem, healthKitSyncRecord, mealPhotoEstimate, mealPhotoComponent
    case portionCalibration, mealTemplate, mealTemplateComponent

    var displayName: String {
        switch self {
        case .goalProfile: "营养目标"
        case .foodItem: "食物"
        case .containerProfile: "容器"
        case .mealLog: "餐食"
        case .mealComponent: "餐食分项"
        case .reviewQueueItem: "待核对记录"
        case .healthKitSyncRecord: "健康同步记录"
        case .mealPhotoEstimate: "照片估算"
        case .mealPhotoComponent: "照片估算分项"
        case .portionCalibration: "份量校准"
        case .mealTemplate: "常用模板"
        case .mealTemplateComponent: "模板分项"
        }
    }
}

struct LocalStoreBackupRecord: Codable, Equatable, Sendable {
    var entity: LocalStoreBackupEntityKind
    var id: UUID
    var fields: [String: LocalStoreBackupValue]
    var relationships: [String: LocalStoreBackupRelationship] = [:]
}

/// Numeric NaN and infinities use explicit JSON markers. Historical invalid values are not
/// normalized, so the archive remains useful even when the current domain initializer rejects them.
enum LocalStoreBackupValue: Codable, Sendable, Equatable {
    case string(String)
    case integer(Int)
    case number(Double)
    case date(Double) // Date.timeIntervalSinceReferenceDate, without precision-changing conversions.
    case uuid(UUID)
    case bool(Bool)
    case stringArray([String])
    case null

    static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case let (.string(a), .string(b)): a == b
        case let (.integer(a), .integer(b)): a == b
        case let (.number(a), .number(b)), let (.date(a), .date(b)): a == b || (a.isNaN && b.isNaN)
        case let (.uuid(a), .uuid(b)): a == b
        case let (.bool(a), .bool(b)): a == b
        case let (.stringArray(a), .stringArray(b)): a == b
        case (.null, .null): true
        default: false
        }
    }
}

enum LocalStoreBackupRelationship: Codable, Equatable, Sendable {
    case toOne(UUID?)
    case toMany([UUID])
}

struct LocalStoreBackupImageWarning: Equatable, Sendable {
    let reference: String
}

struct LocalStoreBackupSummary: Equatable, Sendable {
    let totalRecords: Int
    let counts: [LocalStoreBackupEntityKind: Int]
    let imageWarnings: [LocalStoreBackupImageWarning]
}

enum LocalStoreBackupError: Error, Equatable, LocalizedError {
    case malformedBackup
    case backupTooLarge
    case unsupportedVersion
    case duplicateID(entity: LocalStoreBackupEntityKind, id: UUID)
    case conflictingID(entity: LocalStoreBackupEntityKind, id: UUID)
    case invalidRecord(entity: LocalStoreBackupEntityKind, id: UUID, field: String)
    case invalidRelationship(entity: LocalStoreBackupEntityKind, id: UUID, relationship: String)
    case nonFiniteValueCannotBeRestored(entity: LocalStoreBackupEntityKind, id: UUID, field: String)
    case invalidDirectory
    case restoreVerificationFailed

    var errorDescription: String? {
        switch self {
        case .malformedBackup: "备份文件已损坏，或不是食衡全量备份。"
        case .backupTooLarge: "备份文件超过当前支持的 64 MB，请保留原文件。"
        case .unsupportedVersion: "此备份的格式或数据库版本暂不支持。"
        case let .duplicateID(entity, id): "备份内的\(entity.displayName) UUID 重复：\(id)。"
        case let .conflictingID(entity, id): "备份内相同的\(entity.displayName) UUID 有不同内容：\(id)。"
        case let .invalidRecord(entity, _, field): "备份的\(entity.displayName)字段结构不正确：\(field)。"
        case let .invalidRelationship(entity, _, relationship): "备份的\(entity.displayName)关联不一致：\(relationship)。"
        case let .nonFiniteValueCannotBeRestored(entity, _, field): "\(entity.displayName)的\(field)含 NaN 或无穷值。原始备份已保留，暂不能安全恢复到数据库。"
        case .invalidDirectory: "恢复位置必须是本地目录。"
        case .restoreVerificationFailed: "恢复库重新打开后的数据与备份不一致，未切换现用数据库。"
        }
    }
}

enum LocalStoreBackupCodec {
    static func encode(_ document: LocalStoreBackupDocument) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.nonConformingFloatEncodingStrategy = .convertToString(
            positiveInfinity: "+Infinity", negativeInfinity: "-Infinity", nan: "NaN"
        )
        return try encoder.encode(document)
    }

    static func decode(_ data: Data) throws -> LocalStoreBackupDocument {
        let decoder = JSONDecoder()
        decoder.nonConformingFloatDecodingStrategy = .convertFromString(
            positiveInfinity: "+Infinity", negativeInfinity: "-Infinity", nan: "NaN"
        )
        do {
            return try decoder.decode(LocalStoreBackupDocument.self, from: data)
        } catch {
            throw LocalStoreBackupError.malformedBackup
        }
    }
}

extension LocalStoreBackupDocument {
    /// To-many membership has no stable store order. Preserve sortIndex values and use them for
    /// canonical relationship ordering, with UUID as a deterministic tie breaker.
    var canonicalRecords: [LocalStoreBackupRecord] {
        var orderByEntity: [LocalStoreBackupEntityKind: [UUID: Int]] = [:]
        for child in records {
            if case let .integer(index) = child.fields["sortIndex"] {
                orderByEntity[child.entity, default: [:]][child.id] = index
            }
        }
        return records.map { record in
            var normalized = record
            for (name, relation) in record.relationships {
                if case let .toMany(ids) = relation,
                   let childKind = record.entity.relationshipSpecifications[name]?.target {
                    let order = orderByEntity[childKind] ?? [:]
                    normalized.relationships[name] = .toMany(ids.sorted {
                        if order[$0] != order[$1] { return (order[$0] ?? 0) < (order[$1] ?? 0) }
                        return $0.uuidString < $1.uuidString
                    })
                }
            }
            return normalized
        }.sorted {
            if $0.entity != $1.entity { return $0.entity.rawValue < $1.entity.rawValue }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    /// SQLite cannot safely represent every IEEE non-finite value in a required stored property.
    /// Keep such values in the JSON archive, but reject staging before opening or writing any store.
    func validateSQLiteRestoreValues() throws {
        for record in canonicalRecords {
            for key in record.fields.keys.sorted() {
                switch record.fields[key] {
                case let .number(value), let .date(value):
                    guard value.isFinite else {
                        throw LocalStoreBackupError.nonFiniteValueCannotBeRestored(
                            entity: record.entity, id: record.id, field: key
                        )
                    }
                default: break
                }
            }
        }
    }

    /// Archive validation is structural only. It deliberately does not call current business rules.
    func validate() throws {
        guard formatVersion == 1, schemaVersion == "1.0.0" else {
            throw LocalStoreBackupError.unsupportedVersion
        }
        guard createdAt.timeIntervalSinceReferenceDate.isFinite else {
            throw LocalStoreBackupError.malformedBackup
        }
        var recordsByEntity: [LocalStoreBackupEntityKind: [UUID: LocalStoreBackupRecord]] = [:]
        for record in records {
            if let previous = recordsByEntity[record.entity]?[record.id] {
                throw previous == record
                    ? LocalStoreBackupError.duplicateID(entity: record.entity, id: record.id)
                    : LocalStoreBackupError.conflictingID(entity: record.entity, id: record.id)
            }
            recordsByEntity[record.entity, default: [:]][record.id] = record
        }

        for record in records {
            let fieldTypes = record.entity.fieldTypes
            guard Set(record.fields.keys) == Set(fieldTypes.keys) else {
                throw LocalStoreBackupError.invalidRecord(entity: record.entity, id: record.id, field: "field names")
            }
            for (key, value) in record.fields {
                guard fieldTypes[key]?.accepts(value) == true else {
                    throw LocalStoreBackupError.invalidRecord(entity: record.entity, id: record.id, field: key)
                }
            }
            let specifications = record.entity.relationshipSpecifications
            guard Set(record.relationships.keys) == Set(specifications.keys) else {
                throw LocalStoreBackupError.invalidRelationship(entity: record.entity, id: record.id, relationship: "relationship names")
            }
            for (name, relation) in record.relationships {
                guard let specification = specifications[name] else { continue }
                let targetIDs: [UUID]
                switch (relation, specification.isToMany) {
                case let (.toMany(ids), true):
                    guard Set(ids).count == ids.count else {
                        throw LocalStoreBackupError.invalidRelationship(entity: record.entity, id: record.id, relationship: name)
                    }
                    targetIDs = ids
                case let (.toOne(id), false): targetIDs = id.map { [$0] } ?? []
                default:
                    throw LocalStoreBackupError.invalidRelationship(entity: record.entity, id: record.id, relationship: name)
                }
                for targetID in targetIDs {
                    guard
                        let target = recordsByEntity[specification.target]?[targetID],
                        let inverse = target.relationships[specification.inverse]
                    else {
                        throw LocalStoreBackupError.invalidRelationship(entity: record.entity, id: record.id, relationship: name)
                    }
                    let matches: Bool
                    switch inverse {
                    case let .toOne(id): matches = id == record.id
                    case let .toMany(ids): matches = ids.contains(record.id)
                    }
                    guard matches else {
                        throw LocalStoreBackupError.invalidRelationship(entity: record.entity, id: record.id, relationship: name)
                    }
                }
            }
        }
    }
}

private enum LocalStoreBackupFieldType {
    case string, integer, number, date, uuid, bool, stringArray
    case optionalString, optionalNumber, optionalDate, optionalUUID

    func accepts(_ value: LocalStoreBackupValue) -> Bool {
        switch (self, value) {
        case (.string, .string), (.integer, .integer), (.number, .number), (.date, .date),
             (.uuid, .uuid), (.bool, .bool), (.stringArray, .stringArray),
             (.optionalString, .string), (.optionalNumber, .number),
             (.optionalDate, .date), (.optionalUUID, .uuid),
             (.optionalString, .null), (.optionalNumber, .null),
             (.optionalDate, .null), (.optionalUUID, .null): true
        default: false
        }
    }
}

private struct LocalStoreBackupRelationshipSpecification {
    let target: LocalStoreBackupEntityKind
    let inverse: String
    let isToMany: Bool
}

private extension LocalStoreBackupEntityKind {
    var fieldTypes: [String: LocalStoreBackupFieldType] {
        switch self {
        case .goalProfile:
            ["effectiveFrom": .date, "energyKcal": .number, "proteinGrams": .number,
             "carbohydrateGrams": .number, "fatGrams": .number,
             "saturatedFatLimitGrams": .optionalNumber, "fibreGrams": .optionalNumber]
        case .foodItem:
            ["name": .string, "categoryRawValue": .string, "unit": .string, "source": .string,
             "energyKcalPer100Units": .number, "fatGramsPer100Units": .number,
             "saturatedFatGramsPer100Units": .number, "carbohydrateGramsPer100Units": .number,
             "sugarGramsPer100Units": .number, "proteinGramsPer100Units": .number,
             "saltGramsPer100Units": .number, "fibreGramsPer100Units": .optionalNumber]
        case .containerProfile: ["name": .string, "tareWeightGrams": .number]
        case .mealLog:
            nutritionTypes.merging(["eatenAt": .date, "title": .string,
                "consumedWeightGrams": .number, "entryMethodRawValue": .string,
                "coverageStatusRawValue": .string, "estimateEvidenceGradeRawValue": .string,
                "healthKitSyncVersion": .integer]) { _, new in new }
        case .mealComponent:
            nutritionTypes.merging(["foodItemID": .uuid, "foodName": .string,
                "consumedWeightGrams": .number, "unit": .string, "sortIndex": .integer]) { _, new in new }
        case .reviewQueueItem:
            ["createdAt": .date, "sourceImageIdentifier": .optionalString,
             "missingFields": .stringArray, "statusRawValue": .string]
        case .healthKitSyncRecord:
            ["mealID": .uuid, "objectTypeRawValue": .string, "syncIdentifier": .string,
             "syncVersion": .integer, "healthKitUUID": .optionalUUID, "isDeleted": .bool]
        case .mealPhotoEstimate:
            ["createdAt": .date, "mealTitle": .string, "imageReference": .string,
             "providerName": .string, "modelVersion": .string, "outputSchemaVersion": .string,
             "confirmationStatusRawValue": .string, "consumedShareRatio": .number]
        case .mealPhotoComponent:
            ["foodItemID": .optionalUUID, "templateID": .optionalString, "freeTextName": .string,
             "cookingMethodRawValue": .string, "lowGrams": .number, "midpointGrams": .number,
             "highGrams": .number, "confidence": .number, "isHiddenOilOrSauce": .bool,
             "userCorrectedWeightGrams": .optionalNumber, "sortIndex": .integer]
        case .portionCalibration:
            ["createdAt": .date, "photoEstimateID": .uuid, "componentID": .optionalUUID,
             "estimatedWeightGrams": .number, "actualWeightGrams": .number, "sortIndex": .integer]
        case .mealTemplate:
            ["name": .string, "createdAt": .date, "updatedAt": .date,
             "lastUsedAt": .optionalDate, "useCount": .integer]
        case .mealTemplateComponent:
            ["foodItemID": .uuid, "foodName": .string, "defaultWeightGrams": .number,
             "unit": .string, "sortIndex": .integer]
        }
    }

    var nutritionTypes: [String: LocalStoreBackupFieldType] {
        ["energyKcal": .number, "fatGrams": .number, "saturatedFatGrams": .number,
         "carbohydrateGrams": .number, "sugarGrams": .number, "proteinGrams": .number,
         "saltGrams": .number, "fibreGrams": .optionalNumber]
    }

    var relationshipSpecifications: [String: LocalStoreBackupRelationshipSpecification] {
        switch self {
        case .mealLog: ["components": .init(target: .mealComponent, inverse: "meal", isToMany: true)]
        case .mealComponent: ["meal": .init(target: .mealLog, inverse: "components", isToMany: false)]
        case .mealPhotoEstimate:
            ["components": .init(target: .mealPhotoComponent, inverse: "estimate", isToMany: true),
             "calibrations": .init(target: .portionCalibration, inverse: "estimate", isToMany: true)]
        case .mealPhotoComponent: ["estimate": .init(target: .mealPhotoEstimate, inverse: "components", isToMany: false)]
        case .portionCalibration: ["estimate": .init(target: .mealPhotoEstimate, inverse: "calibrations", isToMany: false)]
        case .mealTemplate: ["components": .init(target: .mealTemplateComponent, inverse: "template", isToMany: true)]
        case .mealTemplateComponent: ["template": .init(target: .mealTemplate, inverse: "components", isToMany: false)]
        default: [:]
        }
    }
}
