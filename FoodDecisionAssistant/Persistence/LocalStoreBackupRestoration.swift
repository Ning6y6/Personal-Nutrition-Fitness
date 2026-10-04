import FoodDecisionCore
import Foundation
import SwiftData

@MainActor
enum LocalStoreBackupRestoration {
    static func container(at storeURL: URL) throws -> ModelContainer {
        let schema = Schema(versionedSchema: VersionedSchemaV1.self)
        let configuration = ModelConfiguration(schema: schema, url: storeURL, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: configuration)
    }

    static func write(document: LocalStoreBackupDocument, storeURL: URL) throws {
        try document.validate()
        let container = try container(at: storeURL)
        let context = ModelContext(container)
        context.autosaveEnabled = false
        var meals: [UUID: PersistentMealLog] = [:]
        var mealComponents: [UUID: PersistentMealComponent] = [:]
        var photos: [UUID: PersistentMealPhotoEstimate] = [:]
        var photoComponents: [UUID: PersistentMealPhotoComponent] = [:]
        var calibrations: [UUID: PersistentPortionCalibration] = [:]
        var templates: [UUID: PersistentMealTemplate] = [:]
        var templateComponents: [UUID: PersistentMealTemplateComponent] = [:]

        // Initialized, valid constructor shells establish SwiftData's backing values and inverse
        // relationships. Never pass archived data through a domain constructor: assign every stored
        // scalar directly, including raw enum strings and values rejected by current business rules.
        for record in document.records {
            let value = LocalStoreBackupRecordReader(record: record)
            switch record.entity {
            case .goalProfile:
                let row = PersistentGoalProfile(domain: GoalProfile(energyKcal: 1, proteinGrams: 0, carbohydrateGrams: 0, fatGrams: 0))
                row.id = record.id
                row.effectiveFrom = try value.date("effectiveFrom")
                row.energyKcal = try value.number("energyKcal")
                row.proteinGrams = try value.number("proteinGrams")
                row.carbohydrateGrams = try value.number("carbohydrateGrams")
                row.fatGrams = try value.number("fatGrams")
                row.saturatedFatLimitGrams = try value.optionalNumber("saturatedFatLimitGrams")
                row.fibreGrams = try value.optionalNumber("fibreGrams")
                context.insert(row)
            case .foodItem:
                let row = PersistentFoodItem(domain: FoodItem(name: "restore", category: .mixedMeal, nutrientsPer100Units: emptyNutrients, source: "restore"))
                row.id = record.id
                row.name = try value.string("name")
                row.categoryRawValue = try value.string("categoryRawValue")
                row.energyKcalPer100Units = try value.number("energyKcalPer100Units")
                row.fatGramsPer100Units = try value.number("fatGramsPer100Units")
                row.saturatedFatGramsPer100Units = try value.number("saturatedFatGramsPer100Units")
                row.carbohydrateGramsPer100Units = try value.number("carbohydrateGramsPer100Units")
                row.sugarGramsPer100Units = try value.number("sugarGramsPer100Units")
                row.proteinGramsPer100Units = try value.number("proteinGramsPer100Units")
                row.saltGramsPer100Units = try value.number("saltGramsPer100Units")
                row.fibreGramsPer100Units = try value.optionalNumber("fibreGramsPer100Units")
                row.unit = try value.string("unit")
                row.source = try value.string("source")
                context.insert(row)
            case .containerProfile:
                let row = PersistentContainerProfile(domain: ContainerProfile(name: "restore", tareWeightGrams: 0))
                row.id = record.id
                row.name = try value.string("name")
                row.tareWeightGrams = try value.number("tareWeightGrams")
                context.insert(row)
            case .mealLog:
                let row = PersistentMealLog(domain: MealLog(title: "restore", consumedWeightGrams: 0, nutrients: emptyNutrients, coverageStatus: .incomplete, estimateEvidenceGrade: .d))
                row.id = record.id
                row.eatenAt = try value.date("eatenAt")
                row.title = try value.string("title")
                row.consumedWeightGrams = try value.number("consumedWeightGrams")
                row.energyKcal = try value.number("energyKcal")
                row.fatGrams = try value.number("fatGrams")
                row.saturatedFatGrams = try value.number("saturatedFatGrams")
                row.carbohydrateGrams = try value.number("carbohydrateGrams")
                row.sugarGrams = try value.number("sugarGrams")
                row.proteinGrams = try value.number("proteinGrams")
                row.saltGrams = try value.number("saltGrams")
                row.fibreGrams = try value.optionalNumber("fibreGrams")
                row.entryMethodRawValue = try value.string("entryMethodRawValue")
                row.coverageStatusRawValue = try value.string("coverageStatusRawValue")
                row.estimateEvidenceGradeRawValue = try value.string("estimateEvidenceGradeRawValue")
                row.healthKitSyncVersion = try value.integer("healthKitSyncVersion")
                row.components = []
                context.insert(row)
                meals[record.id] = row
            case .mealComponent:
                let shell = try MealComponent(foodItemID: UUID(), foodName: "restore", consumedWeightGrams: 1, unit: "g", nutrients: emptyNutrients)
                let row = PersistentMealComponent(domain: shell)
                row.id = record.id
                row.foodItemID = try value.uuid("foodItemID")
                row.foodName = try value.string("foodName")
                row.consumedWeightGrams = try value.number("consumedWeightGrams")
                row.unit = try value.string("unit")
                row.energyKcal = try value.number("energyKcal")
                row.fatGrams = try value.number("fatGrams")
                row.saturatedFatGrams = try value.number("saturatedFatGrams")
                row.carbohydrateGrams = try value.number("carbohydrateGrams")
                row.sugarGrams = try value.number("sugarGrams")
                row.proteinGrams = try value.number("proteinGrams")
                row.saltGrams = try value.number("saltGrams")
                row.fibreGrams = try value.optionalNumber("fibreGrams")
                row.sortIndex = try value.integer("sortIndex")
                row.meal = nil
                context.insert(row)
                mealComponents[record.id] = row
            case .reviewQueueItem:
                let row = PersistentReviewQueueItem(domain: ReviewQueueItem(missingFields: []))
                row.id = record.id
                row.createdAt = try value.date("createdAt")
                row.sourceImageIdentifier = try value.optionalString("sourceImageIdentifier")
                row.missingFields = try value.strings("missingFields")
                row.statusRawValue = try value.string("statusRawValue")
                context.insert(row)
            case .healthKitSyncRecord:
                let row = PersistentHealthKitSyncRecord(domain: HealthKitSyncRecord(mealID: UUID(), objectType: .energy, syncIdentifier: "restore", syncVersion: 1))
                row.id = record.id
                row.mealID = try value.uuid("mealID")
                row.objectTypeRawValue = try value.string("objectTypeRawValue")
                row.syncIdentifier = try value.string("syncIdentifier")
                row.syncVersion = try value.integer("syncVersion")
                row.healthKitUUID = try value.optionalUUID("healthKitUUID")
                row.isDeleted = try value.bool("isDeleted")
                context.insert(row)
            case .mealPhotoEstimate:
                let shell = try MealPhotoEstimate(mealTitle: "restore", imageReference: "", providerName: "restore", modelVersion: "restore", outputSchemaVersion: "restore", confirmationStatus: .draft, consumedShareRatio: 1, components: [])
                let row = PersistentMealPhotoEstimate(domain: shell)
                row.id = record.id
                row.createdAt = try value.date("createdAt")
                row.mealTitle = try value.string("mealTitle")
                row.imageReference = try value.string("imageReference")
                row.providerName = try value.string("providerName")
                row.modelVersion = try value.string("modelVersion")
                row.outputSchemaVersion = try value.string("outputSchemaVersion")
                row.confirmationStatusRawValue = try value.string("confirmationStatusRawValue")
                row.consumedShareRatio = try value.number("consumedShareRatio")
                row.components = []
                row.calibrations = []
                context.insert(row)
                photos[record.id] = row
            case .mealPhotoComponent:
                let shell = try MealPhotoComponent(freeTextName: "restore", cookingMethod: .unknown, portionRange: PortionEstimateRange(lowGrams: 0, midpointGrams: 0, highGrams: 0), confidence: 0)
                let row = PersistentMealPhotoComponent(domain: shell)
                row.id = record.id
                row.foodItemID = try value.optionalUUID("foodItemID")
                row.templateID = try value.optionalString("templateID")
                row.freeTextName = try value.string("freeTextName")
                row.cookingMethodRawValue = try value.string("cookingMethodRawValue")
                row.lowGrams = try value.number("lowGrams")
                row.midpointGrams = try value.number("midpointGrams")
                row.highGrams = try value.number("highGrams")
                row.confidence = try value.number("confidence")
                row.isHiddenOilOrSauce = try value.bool("isHiddenOilOrSauce")
                row.userCorrectedWeightGrams = try value.optionalNumber("userCorrectedWeightGrams")
                row.sortIndex = try value.integer("sortIndex")
                row.estimate = nil
                context.insert(row)
                photoComponents[record.id] = row
            case .portionCalibration:
                let shell = try PortionCalibration(photoEstimateID: UUID(), estimatedWeightGrams: 0, actualWeightGrams: 0)
                let row = PersistentPortionCalibration(domain: shell)
                row.id = record.id
                row.createdAt = try value.date("createdAt")
                row.photoEstimateID = try value.uuid("photoEstimateID")
                row.componentID = try value.optionalUUID("componentID")
                row.estimatedWeightGrams = try value.number("estimatedWeightGrams")
                row.actualWeightGrams = try value.number("actualWeightGrams")
                row.sortIndex = try value.integer("sortIndex")
                row.estimate = nil
                context.insert(row)
                calibrations[record.id] = row
            case .mealTemplate:
                let placeholder = try MealTemplateComponent(foodItemID: UUID(), foodName: "restore", defaultWeightGrams: 1)
                let row = PersistentMealTemplate(domain: try MealTemplate(name: "restore", components: [placeholder]))
                for child in row.components { child.template = nil }
                row.components = []
                row.id = record.id
                row.name = try value.string("name")
                row.createdAt = try value.date("createdAt")
                row.updatedAt = try value.date("updatedAt")
                row.lastUsedAt = try value.optionalDate("lastUsedAt")
                row.useCount = try value.integer("useCount")
                context.insert(row)
                templates[record.id] = row
            case .mealTemplateComponent:
                let shell = try MealTemplateComponent(foodItemID: UUID(), foodName: "restore", defaultWeightGrams: 1)
                let row = PersistentMealTemplateComponent(domain: shell)
                row.id = record.id
                row.foodItemID = try value.uuid("foodItemID")
                row.foodName = try value.string("foodName")
                row.defaultWeightGrams = try value.number("defaultWeightGrams")
                row.unit = try value.string("unit")
                row.sortIndex = try value.integer("sortIndex")
                row.template = nil
                context.insert(row)
                templateComponents[record.id] = row
            }
        }

        // Resolve only actual SwiftData relationships. Scalar IDs can legitimately refer to removed
        // foods, old HealthKit rows or external templates and must remain byte-for-byte values.
        for record in document.canonicalRecords {
            switch record.entity {
            case .mealLog:
                if case let .toMany(ids) = record.relationships["components"] {
                    meals[record.id]?.components = ids.compactMap { mealComponents[$0] }
                }
            case .mealPhotoEstimate:
                if case let .toMany(ids) = record.relationships["components"] {
                    photos[record.id]?.components = ids.compactMap { photoComponents[$0] }
                }
                if case let .toMany(ids) = record.relationships["calibrations"] {
                    photos[record.id]?.calibrations = ids.compactMap { calibrations[$0] }
                }
            case .mealTemplate:
                if case let .toMany(ids) = record.relationships["components"] {
                    templates[record.id]?.components = ids.compactMap { templateComponents[$0] }
                }
            default: break
            }
        }
        try context.save()
    }

    private static var emptyNutrients: NutrientValues {
        NutrientValues(energyKcal: 0, fatGrams: 0, saturatedFatGrams: 0, carbohydrateGrams: 0, sugarGrams: 0, proteinGrams: 0, saltGrams: 0)
    }
}

private struct LocalStoreBackupRecordReader {
    let record: LocalStoreBackupRecord

    func string(_ key: String) throws -> String {
        guard case let .string(value) = record.fields[key] else { throw invalid(key) }
        return value
    }
    func integer(_ key: String) throws -> Int {
        guard case let .integer(value) = record.fields[key] else { throw invalid(key) }
        return value
    }
    func number(_ key: String) throws -> Double {
        guard case let .number(value) = record.fields[key] else { throw invalid(key) }
        return value
    }
    func uuid(_ key: String) throws -> UUID {
        guard case let .uuid(value) = record.fields[key] else { throw invalid(key) }
        return value
    }
    func bool(_ key: String) throws -> Bool {
        guard case let .bool(value) = record.fields[key] else { throw invalid(key) }
        return value
    }
    func strings(_ key: String) throws -> [String] {
        guard case let .stringArray(value) = record.fields[key] else { throw invalid(key) }
        return value
    }
    func date(_ key: String) throws -> Date {
        guard case let .date(value) = record.fields[key] else { throw invalid(key) }
        return Date(timeIntervalSinceReferenceDate: value)
    }
    func optionalNumber(_ key: String) throws -> Double? {
        if case .null = record.fields[key] { return nil }
        return try number(key)
    }
    func optionalString(_ key: String) throws -> String? {
        if case .null = record.fields[key] { return nil }
        return try string(key)
    }
    func optionalUUID(_ key: String) throws -> UUID? {
        if case .null = record.fields[key] { return nil }
        return try uuid(key)
    }
    func optionalDate(_ key: String) throws -> Date? {
        if case .null = record.fields[key] { return nil }
        return try date(key)
    }
    private func invalid(_ key: String) -> LocalStoreBackupError {
        .invalidRecord(entity: record.entity, id: record.id, field: key)
    }
}
