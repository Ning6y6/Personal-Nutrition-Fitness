import FoodDecisionCore
import SwiftData
import SwiftUI

// These fixtures own isolated in-memory stores. They never read the production
// database, and their fictitious numbers are not suggested user targets.
@MainActor
private func mealEntryPreviewContainer(scenario: UI1PreviewScenario) throws -> ModelContainer {
    let schema = Schema(versionedSchema: VersionedSchemaV1.self)
    let configuration = ModelConfiguration(
        schema: schema,
        isStoredInMemoryOnly: true,
        cloudKitDatabase: .none
    )
    let container = try ModelContainer(for: schema, configurations: configuration)
    let context = container.mainContext
    context.autosaveEnabled = false
    try SeedFoodCatalog.importIfNeeded(into: context)

    if scenario != .empty {
        context.insert(PersistentGoalProfile(domain: try scenario.goal()))
        if let food = try SeedFoodCatalog.loadFoods().first, scenario.energyKcal > 0 {
            let component = try MealComponent(
                foodItem: food,
                consumedWeightGrams: scenario.energyKcal * 100 / food.nutrientsPer100Units.energyKcal
            )
            let meal = try MealLog(
                eatenAt: .now,
                title: "[预览] 模拟餐食",
                entryMethod: .weighed,
                coverageStatus: .complete,
                components: [component]
            )
            context.insert(PersistentMealLog(domain: meal))
        }
        try context.save()
    }
    return container
}

#Preview("B 底部入口 · 无记录未设预算 · 浅色") {
    if let container = try? mealEntryPreviewContainer(scenario: .empty) {
        ContentView(mealEntryPlacement: .bottom)
            .modelContainer(container)
            .preferredColorScheme(.light)
    } else {
        ContentUnavailableView("预览不可用", systemImage: "exclamationmark.triangle")
    }
}

#Preview("B 底部入口 · 已记录 · 深色") {
    if let container = try? mealEntryPreviewContainer(scenario: .withinBudget) {
        ContentView(mealEntryPlacement: .bottom)
            .modelContainer(container)
            .preferredColorScheme(.dark)
    } else {
        ContentUnavailableView("预览不可用", systemImage: "exclamationmark.triangle")
    }
}

#Preview("B 底部入口 · 超出预算 · 浅色") {
    if let container = try? mealEntryPreviewContainer(scenario: .overflow) {
        ContentView(mealEntryPlacement: .bottom)
            .modelContainer(container)
            .preferredColorScheme(.light)
    } else {
        ContentUnavailableView("预览不可用", systemImage: "exclamationmark.triangle")
    }
}

#Preview("B 底部入口 · 最大辅助字体") {
    if let container = try? mealEntryPreviewContainer(scenario: .withinBudget) {
        ContentView(mealEntryPlacement: .bottom)
            .modelContainer(container)
            .environment(\.dynamicTypeSize, .accessibility5)
    } else {
        ContentUnavailableView("预览不可用", systemImage: "exclamationmark.triangle")
    }
}

// These accessibility environment values are read-only. Enable the respective
// system settings in Simulator for a real material/motion check; do not inject
// a fake app setting or claim this ordinary preview tested those modes.
#Preview("B 底部入口 · 辅助功能跟随系统") {
    if let container = try? mealEntryPreviewContainer(scenario: .withinBudget) {
        ContentView(mealEntryPlacement: .bottom)
            .modelContainer(container)
    } else {
        ContentUnavailableView("预览不可用", systemImage: "exclamationmark.triangle")
    }
}

#Preview("A 工具栏对照 · 已记录 · 浅色") {
    if let container = try? mealEntryPreviewContainer(scenario: .withinBudget) {
        ContentView(mealEntryPlacement: .toolbar)
            .modelContainer(container)
            .preferredColorScheme(.light)
    } else {
        ContentUnavailableView("预览不可用", systemImage: "exclamationmark.triangle")
    }
}

#Preview("A 工具栏对照 · 深色最大辅助字体") {
    if let container = try? mealEntryPreviewContainer(scenario: .withinBudget) {
        ContentView(mealEntryPlacement: .toolbar)
            .modelContainer(container)
            .preferredColorScheme(.dark)
            .environment(\.dynamicTypeSize, .accessibility5)
    } else {
        ContentUnavailableView("预览不可用", systemImage: "exclamationmark.triangle")
    }
}

#Preview("记录表单 · 浅色") {
    if let container = try? mealEntryPreviewContainer(scenario: .empty) {
        MealEntryView()
            .modelContainer(container)
            .preferredColorScheme(.light)
    } else {
        ContentUnavailableView("预览不可用", systemImage: "exclamationmark.triangle")
    }
}

#Preview("记录表单 · 深色") {
    if let container = try? mealEntryPreviewContainer(scenario: .empty) {
        MealEntryView()
            .modelContainer(container)
            .preferredColorScheme(.dark)
    } else {
        ContentUnavailableView("预览不可用", systemImage: "exclamationmark.triangle")
    }
}

#Preview("记录表单 · 最大辅助字体") {
    if let container = try? mealEntryPreviewContainer(scenario: .empty) {
        MealEntryView()
            .modelContainer(container)
            .environment(\.dynamicTypeSize, .accessibility5)
    } else {
        ContentUnavailableView("预览不可用", systemImage: "exclamationmark.triangle")
    }
}

#Preview("记录选择 · 最大辅助字体") {
    if let container = try? mealEntryPreviewContainer(scenario: .empty) {
        MealStartView()
            .modelContainer(container)
            .environment(\.dynamicTypeSize, .accessibility5)
    } else {
        ContentUnavailableView("预览不可用", systemImage: "exclamationmark.triangle")
    }
}

#Preview("目标表单 · 最大辅助字体") {
    if let container = try? mealEntryPreviewContainer(scenario: .empty) {
        GoalSettingsView(onSaved: {})
            .modelContainer(container)
            .environment(\.dynamicTypeSize, .accessibility5)
    } else {
        ContentUnavailableView("预览不可用", systemImage: "exclamationmark.triangle")
    }
}

#Preview("模板表单 · 最大辅助字体") {
    if let container = try? mealEntryPreviewContainer(scenario: .empty) {
        MealTemplateEditorView()
            .modelContainer(container)
            .environment(\.dynamicTypeSize, .accessibility5)
    } else {
        ContentUnavailableView("预览不可用", systemImage: "exclamationmark.triangle")
    }
}
