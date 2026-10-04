import FoodDecisionCore
import Foundation
import SwiftData

@Model
final class PersistentMealTemplate {
    @Attribute(.unique) var id: UUID
    var name: String
    var createdAt: Date
    var updatedAt: Date
    var lastUsedAt: Date?
    var useCount: Int
    @Relationship(deleteRule: .cascade, inverse: \PersistentMealTemplateComponent.template)
    var components: [PersistentMealTemplateComponent]

    init(domain: MealTemplate) {
        id = domain.id
        name = domain.name
        createdAt = domain.createdAt
        updatedAt = domain.updatedAt
        lastUsedAt = domain.lastUsedAt
        useCount = domain.useCount
        components = domain.components.enumerated().map {
            PersistentMealTemplateComponent(domain: $0.element, sortIndex: $0.offset)
        }

        for component in components {
            component.template = self
        }
    }

    func domainModel() throws -> MealTemplate {
        try MealTemplate(
            id: id,
            name: name,
            createdAt: createdAt,
            updatedAt: updatedAt,
            lastUsedAt: lastUsedAt,
            useCount: useCount,
            components: try components
                .sorted { $0.sortIndex < $1.sortIndex }
                .map { try $0.domainModel() }
        )
    }

    func update(from domain: MealTemplate, in modelContext: ModelContext) {
        precondition(id == domain.id, "A persisted template can only be updated from the same template ID.")

        name = domain.name
        createdAt = domain.createdAt
        updatedAt = domain.updatedAt
        lastUsedAt = domain.lastUsedAt
        useCount = domain.useCount

        let previousComponents = components
        components = []
        for component in previousComponents {
            modelContext.delete(component)
        }

        components = domain.components.enumerated().map {
            let component = PersistentMealTemplateComponent(
                domain: $0.element,
                sortIndex: $0.offset
            )
            component.template = self
            modelContext.insert(component)
            return component
        }
    }

    func markUsed(at date: Date = .now) {
        lastUsedAt = date
        useCount += 1
    }
}

@Model
final class PersistentMealTemplateComponent {
    @Attribute(.unique) var id: UUID
    var foodItemID: UUID
    var foodName: String
    var defaultWeightGrams: Double
    var unit: String
    var sortIndex: Int
    var template: PersistentMealTemplate?

    init(domain: MealTemplateComponent, sortIndex: Int = 0) {
        id = domain.id
        foodItemID = domain.foodItemID
        foodName = domain.foodName
        defaultWeightGrams = domain.defaultWeightGrams
        unit = domain.unit
        self.sortIndex = sortIndex
    }

    func domainModel() throws -> MealTemplateComponent {
        try MealTemplateComponent(
            id: id,
            foodItemID: foodItemID,
            foodName: foodName,
            defaultWeightGrams: defaultWeightGrams,
            unit: unit
        )
    }
}
