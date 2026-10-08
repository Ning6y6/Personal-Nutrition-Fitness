import FoodDecisionCore
import Foundation
import QuartzCore
import SwiftData
import SwiftUI
import Testing
import UIKit

@testable import FoodDecisionAssistant

/// Stable navigation contracts and render artifacts, not automated tap/gesture tests.
/// Every rendered root uses a fresh in-memory V1 container, public seed foods and fictitious
/// goals/meals. Real Tab interaction, navigation retention and VoiceOver require separate QA.
@MainActor
@Suite(.serialized)
struct NativeNavigationTests {
    @Test("The native shell exposes four stable tab identities and titles")
    func tabIdentityContract() {
        #expect(AppTab.allCases == [.today, .scan, .calendar, .settings])
        #expect(AppTab.allCases.map(\.rawValue) == ["today", "scan", "calendar", "settings"])
        #expect(AppTab.allCases.map(\.title) == ["今日", "扫描", "日历", "设置"])
        #expect(Set(AppTab.allCases.map(\.rawValue)).count == 4)
        #expect(AppTab.allCases.allSatisfy { $0.systemImage.isEmpty == false })
    }

    @Test("Navigation fixtures retain the frozen twelve-entity schema and idempotent seed catalog")
    func inMemorySchemaContract() throws {
        let container = try makeContainer()
        let context = container.mainContext
        #expect(VersionedSchemaV1.models.count == 12)
        #expect(container.schema.entities.count == 12)
        #expect(try inventory(in: context) == [1, 12, 0, 1, 1, 0, 0, 0, 0, 0, 0, 0])
        #expect(try SeedFoodCatalog.importIfNeeded(into: context) == 0)
        #expect(try context.fetchCount(FetchDescriptor<PersistentFoodItem>()) == 12)
        #expect(context.hasChanges == false)
    }

    @Test("Native tab roots render without changing their business records", arguments: [
        (AppTab.today, "light", false),
        (AppTab.today, "dark", false),
        (AppTab.scan, "light", false),
        (AppTab.scan, "dark", false),
        (AppTab.calendar, "light", false),
        (AppTab.calendar, "dark", false),
        (AppTab.settings, "light", false),
        (AppTab.settings, "dark", false),
        (AppTab.today, "light", true),
        (AppTab.today, "dark", true),
    ])
    func recordNativeTab(configuration: (AppTab, String, Bool)) async throws {
        let (tab, appearance, usesLargestType) = configuration
        let container = try makeContainer()
        let context = container.mainContext
        let originalInventory = try inventory(in: context)
        let originalFoods = try foodSnapshots(in: context)
        let originalGoals = try goalSnapshots(in: context)
        let originalMeals = try mealSnapshots(in: context)

        try await recordRootPNG(
            tab: tab,
            appearance: appearance,
            usesLargestType: usesLargestType,
            container: container
        )

        // Mounting an initially selected root is not the same as tapping between tabs.
        // These assertions cover observable persistence effects of the real view lifecycle.
        #expect(try inventory(in: context) == originalInventory)
        #expect(try foodSnapshots(in: context) == originalFoods)
        #expect(try goalSnapshots(in: context) == originalGoals)
        #expect(try mealSnapshots(in: context) == originalMeals)
        #expect(context.hasChanges == false)
        #expect(try SeedFoodCatalog.importIfNeeded(into: context) == 0)
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema(versionedSchema: VersionedSchemaV1.self)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: configuration)
        let context = container.mainContext
        context.autosaveEnabled = false
        try SeedFoodCatalog.importIfNeeded(into: context)

        let goal = try GoalProfile(
            effectiveFrom: Date(timeIntervalSince1970: 1_704_067_200),
            energyKcal: 2_000,
            proteinGrams: 140,
            carbohydrateGrams: 210,
            fatGrams: 60,
            saturatedFatLimitGrams: 15,
            fibreGrams: 30
        )
        context.insert(PersistentGoalProfile(domain: goal))
        let food = try #require(SeedFoodCatalog.loadFoods().first)
        let meal = try MealLog(
            eatenAt: .now,
            title: "[预览] 模拟午餐",
            entryMethod: .weighed,
            coverageStatus: .complete,
            components: [try MealComponent(foodItem: food, consumedWeightGrams: 200)]
        )
        context.insert(PersistentMealLog(domain: meal))
        try context.save()
        return container
    }

    private func inventory(in context: ModelContext) throws -> [Int] {
        try [
            context.fetchCount(FetchDescriptor<PersistentGoalProfile>()),
            context.fetchCount(FetchDescriptor<PersistentFoodItem>()),
            context.fetchCount(FetchDescriptor<PersistentContainerProfile>()),
            context.fetchCount(FetchDescriptor<PersistentMealLog>()),
            context.fetchCount(FetchDescriptor<PersistentMealComponent>()),
            context.fetchCount(FetchDescriptor<PersistentReviewQueueItem>()),
            context.fetchCount(FetchDescriptor<PersistentHealthKitSyncRecord>()),
            context.fetchCount(FetchDescriptor<PersistentMealPhotoEstimate>()),
            context.fetchCount(FetchDescriptor<PersistentMealPhotoComponent>()),
            context.fetchCount(FetchDescriptor<PersistentPortionCalibration>()),
            context.fetchCount(FetchDescriptor<PersistentMealTemplate>()),
            context.fetchCount(FetchDescriptor<PersistentMealTemplateComponent>()),
        ]
    }

    private func foodSnapshots(in context: ModelContext) throws -> [FoodItem] {
        try context.fetch(FetchDescriptor<PersistentFoodItem>())
            .map { try $0.domainModel }
            .sorted { $0.id.uuidString < $1.id.uuidString }
    }

    private func goalSnapshots(in context: ModelContext) throws -> [GoalProfile] {
        try context.fetch(FetchDescriptor<PersistentGoalProfile>())
            .map { try $0.domainModel }
            .sorted { $0.id.uuidString < $1.id.uuidString }
    }

    private func mealSnapshots(in context: ModelContext) throws -> [MealLog] {
        try context.fetch(FetchDescriptor<PersistentMealLog>())
            .map { try $0.domainModel() }
            .sorted { $0.id.uuidString < $1.id.uuidString }
    }

    private func recordRootPNG(
        tab: AppTab,
        appearance: String,
        usesLargestType: Bool,
        container: ModelContainer,
        sourceLocation: SourceLocation = #_sourceLocation
    ) async throws {
        let scene = try await waitForScene(sourceLocation: sourceLocation)
        var hasAppeared = false
        let canvas = CGSize(width: 430, height: 932)
        let content = ContentView(initialTab: tab)
            .modelContainer(container)
            .environment(\.colorScheme, appearance == "dark" ? .dark : .light)
            .environment(\.dynamicTypeSize, usesLargestType ? .accessibility5 : .large)
            .environment(\.locale, Locale(identifier: "zh_CN"))
            .frame(width: canvas.width, height: canvas.height)
            .onAppear { hasAppeared = true }

        let controller = UIHostingController(rootView: content)
        controller.overrideUserInterfaceStyle = appearance == "dark" ? .dark : .light
        controller.loadViewIfNeeded()
        controller.view.tintAdjustmentMode = .normal
        controller.view.backgroundColor = .systemGroupedBackground
        let window = UIWindow(windowScene: scene)
        window.overrideUserInterfaceStyle = controller.overrideUserInterfaceStyle
        window.tintAdjustmentMode = .normal
        window.backgroundColor = .systemGroupedBackground
        window.frame = CGRect(origin: .zero, size: canvas)
        window.rootViewController = controller
        window.isHidden = false
        // This independent window never becomes key and never replaces the app's root.
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }

        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(10))
        while hasAppeared == false && clock.now < deadline {
            try Task.checkCancellation()
            let remaining = clock.now.duration(to: deadline)
            try await Task.sleep(for: min(.milliseconds(50), remaining))
        }
        try #require(hasAppeared, "The native tab root must actually appear before capture.", sourceLocation: sourceLocation)
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        CATransaction.flush()

        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: canvas, format: format)
        var rendered = false
        let image = renderer.image { output in
            UIColor.systemGroupedBackground.resolvedColor(with: controller.traitCollection).setFill()
            output.fill(CGRect(origin: .zero, size: canvas))
            rendered = controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
        }
        try #require(rendered, "The real native hierarchy must render, not a substitute image.", sourceLocation: sourceLocation)
        let bitmap = try #require(image.cgImage, sourceLocation: sourceLocation)
        #expect(bitmap.width == 860, sourceLocation: sourceLocation)
        #expect(bitmap.height == 1_864, sourceLocation: sourceLocation)
        let data = try #require(image.pngData(), sourceLocation: sourceLocation)
        let bytes = [UInt8](data)
        #expect(bytes.count > 8, sourceLocation: sourceLocation)
        #expect(Array(bytes.prefix(8)) == [137, 80, 78, 71, 13, 10, 26, 10], sourceLocation: sourceLocation)
        let typeSuffix = usesLargestType ? "-AX5" : "-default-type"
        Attachment.record(bytes, named: "NativeNavigation-\(tab.rawValue)-\(appearance)\(typeSuffix).png", sourceLocation: sourceLocation)
    }

    private func waitForScene(sourceLocation: SourceLocation) async throws -> UIWindowScene {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(10))
        var scene: UIWindowScene?
        while true {
            try Task.checkCancellation()
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
            if scene != nil || clock.now >= deadline { break }
            let remaining = clock.now.duration(to: deadline)
            try await Task.sleep(for: min(.milliseconds(50), remaining))
        }
        return try #require(scene, "No app-hosted UIWindowScene connected within ten seconds.", sourceLocation: sourceLocation)
    }
}
