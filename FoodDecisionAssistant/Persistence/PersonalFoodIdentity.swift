import FoodDecisionCore
import Foundation

enum PersonalFoodIdentityError: Error, Equatable, LocalizedError {
    case catalogUnavailable

    var errorDescription: String? {
        "无法核对内置食品目录，暂时不能编辑个人食物。已有食品和本次输入仍保留，请重试。"
    }
}

/// A source envelope is a local protocol, not proof of an official data source.
/// The complete bundled/legacy ID set always takes precedence over its marker.
struct PersonalFoodIdentity: Sendable {
    private let reservedIDs: Set<UUID>

    init(catalogLoader: () throws -> [FoodItem] = { try FoodCatalog.bundled().entries.map(\.food) }) throws {
        do {
            let bundled = try catalogLoader()
            let seeds = try SeedFoodCatalog.loadFoods()
            // SeedFoodCatalog deliberately retires this ID during bootstrap. Never
            // allocate it to a personal card, even if it is absent from today's catalog.
            guard let retired = UUID(uuidString: "20000000-0000-4000-8000-000000018521") else {
                throw PersonalFoodIdentityError.catalogUnavailable
            }
            reservedIDs = Set(bundled.map(\.id) + seeds.map(\.id) + [retired])
        } catch {
            // A load error must not turn the protected ID set into an empty set.
            throw PersonalFoodIdentityError.catalogUnavailable
        }
    }

    func isReserved(_ id: UUID) -> Bool { reservedIDs.contains(id) }

    func verifiedSource(for food: FoodItem) -> PersonalFoodSource? {
        guard !isReserved(food.id), food.unit == "g" else { return nil }
        guard let source = PersonalFoodSource.decode(source: food.source, foodID: food.id) else { return nil }
        do {
            let draft = try PersonalFoodDraft(food: food)
            guard try draft.validFood(id: food.id) == food else { return nil }
            return source
        } catch {
            return nil
        }
    }

    func isEditable(_ food: FoodItem) -> Bool { verifiedSource(for: food) != nil }
}
