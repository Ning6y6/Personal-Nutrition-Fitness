import FoodDecisionCore
import Foundation

/// Validates saved snapshots without mutating, repairing, or deleting historical records.
/// Rejected and draft rows remain available in history; callers must show the counts.
@MainActor
struct MealReadValidation {
    static func records(in window: MealDayWindow, from records: [PersistentMealLog]) -> [PersistentMealLog] {
        records.filter { window.contains($0.eatenAt) }
    }

    let meals: [MealLog]
    let invalidRecordIDs: [UUID]
    let draftRecordIDs: [UUID]
    let nutrients: NutrientValues?
    let fibreSummary: FibreIntakeSummary?
    let availability: MealIntakeAvailability

    init(_ records: [PersistentMealLog]) {
        var meals: [MealLog] = []
        var invalid: [UUID] = []
        var drafts: [UUID] = []
        for record in records {
            if record.estimateEvidenceGradeRawValue == EstimateEvidenceGrade.d.rawValue {
                drafts.append(record.id)
                continue
            }
            do {
                meals.append(try record.domainModel())
            } catch {
                invalid.append(record.id)
            }
        }
        self.meals = meals
        invalidRecordIDs = invalid
        draftRecordIDs = drafts
        // A finite input may still overflow when summed. Do not turn that failure into zero.
        let recordedNutrients = try? NutrientValues.sum(meals.map(\.nutrients))
        nutrients = recordedNutrients
        // A meal-level nil would lose its known component subtotal. Use saved snapshots,
        // not current source foods, and do not silently replace overflow with zero.
        fibreSummary = try? FibreIntakeSummary(snapshots: meals.flatMap(\.components).map(\.nutrients))
        if records.isEmpty {
            availability = .noRecords
        } else if meals.isEmpty {
            availability = .noConfirmedRecords
        } else if recordedNutrients == nil {
            availability = .unavailable
        } else {
            availability = .available
        }
    }
}

@MainActor
enum MealDraftValidation {
    static func components(
        from rows: [MealEntryDraftComponent], foods: [PersistentFoodItem]
    ) throws -> [MealComponent] {
        guard !rows.isEmpty else { throw MealLoggingError.emptyComponents }
        return try rows.map { row in
            guard let food = foods.first(where: { $0.id == row.foodItemID }) else {
                throw MealDraftValidationError.unavailableFood
            }
            guard let weight = row.weightGrams else { throw MealLoggingError.invalidWeight }
            return try MealComponent(id: row.id, foodItem: food.domainModel, consumedWeightGrams: weight)
        }
    }
}

enum MealDraftValidationError: Error, LocalizedError, Equatable, Sendable {
    case unavailableFood

    var errorDescription: String? {
        "有食物尚未选择或已不可用，请检查每个分项。"
    }
}
