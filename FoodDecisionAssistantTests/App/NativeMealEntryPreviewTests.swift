import FoodDecisionCore
import Foundation
import QuartzCore
import SwiftData
import SwiftUI
import Testing
import UIKit

@testable import FoodDecisionAssistant

/// Native whole-viewport artifacts for UI-2B, not tap, keyboard, gesture or VoiceOver tests.
/// Each render has a fresh memory-only V1 store and public food/fictitious goal/meal/template.
@MainActor
@Suite(.serialized)
struct NativeMealEntryPreviewTests {
    @Test("Native entry candidates and forms render without saving their fixtures", arguments: [
        ("today-bottom", "light", false), ("today-bottom", "dark", false),
        ("today-bottom", "light", true), ("today-bottom", "dark", true),
        ("today-toolbar", "light", false), ("today-toolbar", "dark", false),
        ("today-toolbar", "light", true), ("today-toolbar", "dark", true),
        ("meal", "light", false), ("meal", "dark", false),
        ("meal", "light", true), ("meal", "dark", true),
        ("goal", "light", false), ("goal", "dark", false),
        ("goal", "light", true), ("goal", "dark", true),
        ("template", "light", false), ("template", "dark", false),
        ("template", "light", true), ("template", "dark", true),
        ("start", "light", false), ("start", "dark", false),
    ])
    func recordNativeEntry(configuration: (String, String, Bool)) async throws {
        let (page, appearance, largestType) = configuration
        let fixture = try makeFixture()
        let context = fixture.container.mainContext
        let originalCounts = try counts(in: context)
        let originalMeal = try fixture.meal.domainModel()
        let originalTemplate = try fixture.template.domainModel()

        try await NativeEntryPNGRecorder.record(
            page: page, appearance: appearance, largestType: largestType, fixture: fixture
        )

        #expect(try counts(in: context) == originalCounts)
        #expect(try fixture.meal.domainModel() == originalMeal)
        #expect(try fixture.template.domainModel() == originalTemplate)
        #expect(context.hasChanges == false)
    }

    private func makeFixture() throws -> NativeEntryPreviewFixture {
        let schema = Schema(versionedSchema: VersionedSchemaV1.self)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: configuration)
        let context = container.mainContext
        context.autosaveEnabled = false
        try SeedFoodCatalog.importIfNeeded(into: context)
        let rice = try #require(SeedFoodCatalog.loadFoods().first { $0.name == "熟长粒白米饭（无盐）" })
        let meal = try MealLog(
            eatenAt: .now, title: "[预览] 熟米饭午餐",
            entryMethod: .weighed, coverageStatus: .complete,
            components: [try MealComponent(foodItem: rice, consumedWeightGrams: 200)]
        )
        let persistentMeal = PersistentMealLog(domain: meal)
        let persistentTemplate = PersistentMealTemplate(domain: try MealTemplate(meal: meal))
        context.insert(persistentMeal)
        context.insert(persistentTemplate)
        context.insert(PersistentGoalProfile(domain: try GoalProfile(
            effectiveFrom: Date(timeIntervalSince1970: 1_704_067_200), energyKcal: 2_000,
            proteinGrams: 140, carbohydrateGrams: 210, fatGrams: 60,
            saturatedFatLimitGrams: 15, fibreGrams: 30
        )))
        try context.save()
        return NativeEntryPreviewFixture(container: container, meal: persistentMeal, template: persistentTemplate, domainMeal: meal)
    }

    private func counts(in context: ModelContext) throws -> [Int] {
        try [
            context.fetchCount(FetchDescriptor<PersistentFoodItem>()),
            context.fetchCount(FetchDescriptor<PersistentGoalProfile>()),
            context.fetchCount(FetchDescriptor<PersistentMealLog>()),
            context.fetchCount(FetchDescriptor<PersistentMealComponent>()),
            context.fetchCount(FetchDescriptor<PersistentMealTemplate>()),
            context.fetchCount(FetchDescriptor<PersistentMealTemplateComponent>()),
        ]
    }
}

@MainActor
private struct NativeEntryPreviewFixture {
    let container: ModelContainer
    let meal: PersistentMealLog
    let template: PersistentMealTemplate
    let domainMeal: MealLog
}

/// A public UIKit window renders real SwiftUI/system-sheet descendants. ImageRenderer is
/// deliberately not used: it cannot faithfully capture the native ProgressView/materials.
@MainActor
private enum NativeEntryPNGRecorder {
    static func record(
        page: String,
        appearance: String,
        largestType: Bool,
        fixture: NativeEntryPreviewFixture,
        sourceLocation: SourceLocation = #_sourceLocation
    ) async throws {
        let scene = try await waitForScene(sourceLocation: sourceLocation)
        var contentAppeared = false
        let canvas = CGSize(width: 430, height: 932)
        let content = NativeEntryPreviewCanvas(
            page: page, appearance: appearance, largestType: largestType, fixture: fixture
        ) { contentAppeared = true }
            .modelContainer(fixture.container)
            .environment(\.colorScheme, appearance == "dark" ? .dark : .light)
            .environment(\.dynamicTypeSize, largestType ? .accessibility5 : .large)
            .environment(\.locale, Locale(identifier: "zh_CN"))
            .frame(width: canvas.width, height: canvas.height)
        let controller = UIHostingController(rootView: content)
        controller.overrideUserInterfaceStyle = appearance == "dark" ? .dark : .light
        let contentSize: UIContentSizeCategory = largestType ? .accessibilityExtraExtraExtraLarge : .large
        controller.traitOverrides.preferredContentSizeCategory = contentSize
        controller.loadViewIfNeeded()
        controller.view.backgroundColor = .systemGroupedBackground
        let window = UIWindow(windowScene: scene)
        window.overrideUserInterfaceStyle = controller.overrideUserInterfaceStyle
        window.traitOverrides.preferredContentSizeCategory = contentSize
        window.frame = CGRect(origin: .zero, size: canvas)
        window.backgroundColor = .systemGroupedBackground
        window.rootViewController = controller
        // Keep the app's key window/lifecycle intact. No private API or simulator preferences.
        window.isHidden = false
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }
        try await waitUntil(
            { contentAppeared },
            message: "The actual page or presented form must appear before capture.",
            sourceLocation: sourceLocation
        )
        if page != "today-bottom" && page != "today-toolbar" {
            try await waitForPresentation(in: controller, sourceLocation: sourceLocation)
        }
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        window.layoutIfNeeded()
        CATransaction.flush()
        if page != "today-bottom" && page != "today-toolbar" {
            try verifyPresentedFormType(
                in: controller, category: contentSize, expectsTextFields: page != "start", sourceLocation: sourceLocation
            )
        }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        format.opaque = true
        var rendered = false
        let image = UIGraphicsImageRenderer(size: canvas, format: format).image { output in
            UIColor.systemGroupedBackground.resolvedColor(with: controller.traitCollection).setFill()
            output.fill(CGRect(origin: .zero, size: canvas))
            rendered = window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        try #require(rendered, "The real native window must render successfully.", sourceLocation: sourceLocation)
        let bitmap = try #require(image.cgImage, sourceLocation: sourceLocation)
        #expect(bitmap.width == 860, sourceLocation: sourceLocation)
        #expect(bitmap.height == 1_864, sourceLocation: sourceLocation)
        let data = try #require(image.pngData(), sourceLocation: sourceLocation)
        let bytes = [UInt8](data)
        #expect(bytes.count > 8, sourceLocation: sourceLocation)
        #expect(Array(bytes.prefix(8)) == [137, 80, 78, 71, 13, 10, 26, 10], sourceLocation: sourceLocation)
        let typeSuffix = largestType ? "AX5" : "default-type"
        Attachment.record(bytes, named: "NativeMealEntry-\(page)-\(appearance)-\(typeSuffix).png", sourceLocation: sourceLocation)
    }

    private static func waitForScene(sourceLocation: SourceLocation) async throws -> UIWindowScene {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(10))
        while true {
            try Task.checkCancellation()
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            if let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first {
                return scene
            }
            try #require(clock.now < deadline, "No app-hosted scene connected within ten seconds.", sourceLocation: sourceLocation)
            try await Task.sleep(for: min(.milliseconds(50), clock.now.duration(to: deadline)))
        }
    }

    private static func waitForPresentation(
        in controller: UIViewController, sourceLocation: SourceLocation
    ) async throws {
        // SwiftUI onAppear can fire at the beginning of a real system sheet transition.
        // Observe UIKit's public completion rather than capturing an intermediate frame.
        let presented = try #require(
            controller.presentedViewController,
            "A form artifact must contain the actual presented system sheet.",
            sourceLocation: sourceLocation
        )
        if let coordinator = presented.transitionCoordinator ?? controller.transitionCoordinator {
            var transitionCompleted = false
            let registered = coordinator.animate(alongsideTransition: nil) { _ in
                transitionCompleted = true
            }
            if registered {
                try await waitUntil(
                    { transitionCompleted },
                    message: "The real sheet transition must finish before capture.",
                    sourceLocation: sourceLocation
                )
            }
        }
        // A completed/nonanimated presentation may no longer have a coordinator. The
        // observable controller state must still be settled and attached to this window.
        try await waitUntil(
            { presented.isBeingPresented == false && presented.viewIfLoaded?.window != nil },
            message: "The presented sheet must be settled in the native window.",
            sourceLocation: sourceLocation
        )
    }

    private static func verifyPresentedFormType(
        in controller: UIViewController,
        category: UIContentSizeCategory,
        expectsTextFields: Bool,
        sourceLocation: SourceLocation
    ) throws {
        let presented = try #require(controller.presentedViewController, sourceLocation: sourceLocation)
        try #require(
            presented.traitCollection.preferredContentSizeCategory == category,
            "The presented form itself, not just its underlying root, must use the requested text-size category.",
            sourceLocation: sourceLocation
        )
        // Inspect public native controls rather than trusting the attachment's AX5 filename.
        // Meal/Goal/Template must really scale their rendered text fields. MealStart has no fields.
        let fields = textFields(in: presented.view)
        if expectsTextFields {
            try #require(fields.isEmpty == false, "The actual form must expose native text fields for font inspection.", sourceLocation: sourceLocation)
            let expectedBodySize = UIFont.preferredFont(
                forTextStyle: .body,
                compatibleWith: UITraitCollection(preferredContentSizeCategory: category)
            ).pointSize
            let fontSizes = fields.compactMap { $0.font?.pointSize }
            try #require(fontSizes.isEmpty == false, "Native form field fonts must be inspectable.", sourceLocation: sourceLocation)
            #expect(
                fontSizes.contains { $0 >= expectedBodySize - 0.5 },
                "At least one actual form field must use the requested Dynamic Type body size.",
                sourceLocation: sourceLocation
            )
        }
    }

    private static func textFields(in view: UIView) -> [UITextField] {
        let current = (view as? UITextField).map { [$0] } ?? []
        return current + view.subviews.flatMap { textFields(in: $0) }
    }

    private static func waitUntil(
        _ condition: () -> Bool,
        message: Comment,
        sourceLocation: SourceLocation
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(10))
        while condition() == false && clock.now < deadline {
            try Task.checkCancellation()
            try await Task.sleep(for: min(.milliseconds(50), clock.now.duration(to: deadline)))
        }
        try #require(condition(), message, sourceLocation: sourceLocation)
    }
}

@MainActor
private struct NativeEntryPreviewCanvas: View {
    let page: String
    let appearance: String
    let largestType: Bool
    let fixture: NativeEntryPreviewFixture
    let onContentAppeared: () -> Void
    @State private var isPresented = true

    var body: some View {
        if page == "today-bottom" || page == "today-toolbar" {
            ContentView(initialTab: .today, mealEntryPlacement: page == "today-toolbar" ? .toolbar : .bottom)
                .onAppear(perform: onContentAppeared)
        } else {
            ContentView(initialTab: .today)
                .sheet(isPresented: $isPresented) {
                    form
                        // Sheet content must receive these directly; the root's environment
                        // alone did not scale the earlier AX5 form artifacts.
                        .environment(\.dynamicTypeSize, largestType ? .accessibility5 : .large)
                        .environment(\.colorScheme, appearance == "dark" ? .dark : .light)
                        .environment(\.locale, Locale(identifier: "zh_CN"))
                        .tint(DesignTokens.accent)
                        .onAppear(perform: onContentAppeared)
                }
        }
    }

    @ViewBuilder
    private var form: some View {
        switch page {
        case "meal":
            MealEntryView(draft: MealEntryDraft(reusing: fixture.domainMeal))
        case "goal":
            GoalSettingsView(onSaved: {})
        case "template":
            MealTemplateEditorView(template: fixture.template)
        default:
            MealStartView()
        }
    }
}
