import FoodDecisionCore
import Foundation
import QuartzCore
import SwiftData
import SwiftUI
import Testing
import UIKit

@testable import FoodDecisionAssistant

/// Selection/presentation contracts and native render artifacts. These do not tap rows,
/// exercise gestures, prove VoiceOver speech or substitute for the separate XCTest gate.
@MainActor
@Suite(.serialized)
struct InlineMealPresentationTests {
    @Test("Inline selection is one transient identity and toggling the same row collapses it")
    func singleExpansionIdentity() {
        let first = UUID()
        let second = UUID()
        var state = InlineMealExpansionState()
        #expect(state.expandedMealID == nil)
        state.toggle(first)
        #expect(state.expandedMealID == first)
        state.toggle(second)
        #expect(state.expandedMealID == second)
        state.toggle(second)
        #expect(state.expandedMealID == nil)
        state.toggle(first)
        state.collapse()
        #expect(state == InlineMealExpansionState())
    }

    @Test("Pruning deleted or moved identities removes ghost expansion without opening another row")
    func pruneVisibleIdentities() {
        let first = UUID()
        let second = UUID()
        var state = InlineMealExpansionState(expandedMealID: first)
        state.prune(visibleIDs: [second, first])
        #expect(state.expandedMealID == first)
        state.prune(visibleIDs: [second])
        #expect(state.expandedMealID == nil)
        state.toggle(second)
        state.prune(visibleIDs: [])
        #expect(state.expandedMealID == nil)
        state.prune(visibleIDs: [first])
        #expect(state.expandedMealID == nil)
    }

    @Test("Current catalog changes never replace saved names, component snapshots or meal totals")
    func historicalSnapshotsStayAuthoritative() throws {
        let fixture = try NativeInlineMealPreviewFixture.make(.confirmed)
        let before = try LocalStoreBackupService.records(from: fixture.container)
        let presentation = InlineMealPresentation(meal: fixture.meal)
        let displayed = try #require(presentation.validatedMeal)
        let component = try #require(displayed.components.first)
        let currentFood = try fixture.changedSourceFood.domainModel
        let recomputed = try MealComponent(foodItem: currentFood, consumedWeightGrams: component.consumedWeightGrams)
        #expect(presentation.status == .confirmed)
        #expect(presentation.canReuse)
        #expect(displayed == fixture.originalMeal)
        #expect(component.foodName != currentFood.name)
        #expect(component.nutrients.energyKcal != recomputed.nutrients.energyKcal)
        #expect(displayed.nutrients.energyKcal == fixture.originalMeal.nutrients.energyKcal)
        #expect(try LocalStoreBackupService.records(from: fixture.container) == before)
        #expect(fixture.container.mainContext.hasChanges == false)
    }

    @Test("D and invalid rows stay identifiable but cannot be reused as confirmed meals", arguments: [
        NativeInlineMealPreviewFixture.Scenario.draft, .invalid,
    ])
    func nonFormalRecordsRetainRawSnapshots(scenario: NativeInlineMealPreviewFixture.Scenario) throws {
        let fixture = try NativeInlineMealPreviewFixture.make(scenario)
        let before = try LocalStoreBackupService.records(from: fixture.container)
        let presentation = InlineMealPresentation(meal: fixture.meal)
        #expect(presentation.status == (scenario == .draft ? .draft : .invalid))
        #expect(presentation.canReuse == false)
        #expect(presentation.validatedMeal == nil)
        #expect(fixture.meal.components.count == fixture.originalMeal.components.count)
        if scenario == .draft {
            #expect(fixture.meal.estimateEvidenceGradeRawValue == "d")
            #expect(fixture.meal.energyKcal == fixture.originalMeal.nutrients.energyKcal)
        } else {
            #expect(fixture.meal.coverageStatusRawValue == "preview_unknown_coverage")
            #expect(fixture.meal.energyKcal == -10)
            #expect(presentation.energyText == "不可用")
        }
        #expect(try LocalStoreBackupService.records(from: fixture.container) == before)
        #expect(fixture.container.mainContext.hasChanges == false)
    }

    @Test("Different invalid snapshot failures do not receive a formal fallback", arguments: [
        "unknownEntry", "unknownCoverage", "unknownEvidence", "inconsistentTotal", "invalidChildWeight",
    ])
    func invalidRecordsDoNotBecomeValid(field: String) throws {
        let fixture = try NativeInlineMealPreviewFixture.make(.confirmed)
        switch field {
        case "unknownEntry": fixture.meal.entryMethodRawValue = "preview_unknown_entry"
        case "unknownCoverage": fixture.meal.coverageStatusRawValue = "preview_unknown_coverage"
        case "unknownEvidence": fixture.meal.estimateEvidenceGradeRawValue = "preview_unknown_evidence"
        case "inconsistentTotal": fixture.meal.energyKcal += 1
        default:
            let child = try #require(fixture.meal.components.first)
            child.consumedWeightGrams = -1
        }
        // Raw invalid history is an intentionally saved fixture; no-write checks start after it.
        try fixture.container.mainContext.save()
        let before = try LocalStoreBackupService.records(from: fixture.container)
        let presentation = InlineMealPresentation(meal: fixture.meal)
        #expect(presentation.status == .invalid)
        #expect(presentation.validatedMeal == nil)
        #expect(presentation.canReuse == false)
        #expect(try LocalStoreBackupService.records(from: fixture.container) == before)
        #expect(fixture.container.mainContext.hasChanges == false)
    }

    @Test("Unsafe raw numbers are labelled unavailable, never displayed as invented zero", arguments: [
        -1.0, Double.infinity, -Double.infinity, Double.nan,
    ])
    func unsafeSnapshotFormatting(value: Double) {
        #expect(InlineMealPresentation.formattedSnapshotValue(value, unit: "g") == "不可用")
    }

    @Test("Unknown fibre remains distinct from explicit zero in expanded historical components")
    func unknownFibreRetainsKnownSubtotal() throws {
        let fixture = try NativeInlineMealPreviewFixture.make(.longMixed)
        let presentation = InlineMealPresentation(meal: fixture.meal)
        let meal = try #require(presentation.validatedMeal)
        #expect(meal.components.count == 8)
        #expect(meal.components.contains { $0.nutrients.fibreGrams == nil })
        #expect(meal.components.contains { $0.nutrients.fibreGrams == 0 })
        let summary = try FibreIntakeSummary(snapshots: meal.components.map(\.nutrients))
        #expect(summary.unknownComponentCount > 0)
        #expect(summary.knownComponentCount > 0)
        #expect(summary.exactGrams == nil)
        #expect(summary.knownSubtotalGrams == meal.components.compactMap(\.nutrients.fibreGrams).reduce(0, +))
        let display = FibreSummaryPresentation(summary: summary)
        #expect(display.amountText.hasPrefix("至少 "))
        #expect(display.detailText?.contains("未知") == true)
        #expect(meal == fixture.originalMeal)
        #expect(fixture.container.mainContext.hasChanges == false)
    }

    @Test("Native expanded rows and real list roots render without changing all twelve entity types", arguments: [
        (NativeInlineMealPreviewFixture.Scenario.confirmed, "light", false, "row"),
        (.confirmed, "dark", false, "row"), (.confirmed, "light", true, "row"), (.confirmed, "dark", true, "row"),
        (.longMixed, "light", false, "row"), (.longMixed, "dark", false, "row"),
        (.longMixed, "light", true, "row"), (.longMixed, "dark", true, "row"),
        (.draft, "light", false, "row"), (.draft, "dark", false, "row"),
        (.draft, "light", true, "row"), (.draft, "dark", true, "row"),
        (.invalid, "light", false, "row"), (.invalid, "dark", false, "row"),
        (.invalid, "light", true, "row"), (.invalid, "dark", true, "row"),
        (.confirmed, "light", false, "today"), (.longMixed, "dark", false, "history"),
    ])
    func recordNativeInline(configuration: (NativeInlineMealPreviewFixture.Scenario, String, Bool, String)) async throws {
        let (scenario, appearance, largestType, page) = configuration
        let fixture = try NativeInlineMealPreviewFixture.make(scenario)
        let context = fixture.container.mainContext
        let before = try LocalStoreBackupService.records(from: fixture.container)
        let beforeInventory = inventory(before)
        try #require(VersionedSchemaV1.models.count == 12)
        try #require(fixture.container.schema.entities.count == 12)
        try #require(beforeInventory.count == LocalStoreBackupEntityKind.allCases.count)
        try #require(context.hasChanges == false)

        try await NativeInlinePNGRecorder.record(
            fixture: fixture, scenario: scenario, page: page,
            appearance: appearance, largestType: largestType
        )

        let after = try LocalStoreBackupService.records(from: fixture.container)
        #expect(after == before, "Rendering may not normalize, repair, recalculate, delete or save any raw business record.")
        #expect(inventory(after) == beforeInventory)
        #expect(context.hasChanges == false)
        #expect(try SeedFoodCatalog.importIfNeeded(into: context) == 0)
        #expect(context.hasChanges == false)
    }

    private func inventory(_ records: [LocalStoreBackupRecord]) -> [Int] {
        LocalStoreBackupEntityKind.allCases.map { kind in records.filter { $0.entity == kind }.count }
    }
}

/// UIKit is deliberate here: ImageRenderer cannot faithfully draw all native controls.
/// Rows use their measured full height so large text, buttons and footers are not cropped;
/// Today/History artifacts use the actual 430×932 viewport, not a fake whole-scroll screenshot.
@MainActor
private enum NativeInlinePNGRecorder {
    static func record(
        fixture: NativeInlineMealPreviewFixture,
        scenario: NativeInlineMealPreviewFixture.Scenario,
        page: String,
        appearance: String,
        largestType: Bool,
        sourceLocation: SourceLocation = #_sourceLocation
    ) async throws {
        let scene = try await waitForScene(sourceLocation: sourceLocation)
        let requestedType: DynamicTypeSize = largestType ? .accessibility5 : .large
        let category: UIContentSizeCategory = largestType ? .accessibilityExtraExtraExtraLarge : .large
        let scheme: ColorScheme = appearance == "dark" ? .dark : .light
        var observedType: DynamicTypeSize?
        var observedScheme: ColorScheme?
        let content = NativeInlineCaptureCanvas(fixture: fixture, page: page) { type, color in
            observedType = type
            observedScheme = color
        }
        .modelContainer(fixture.container)
        .environment(\.dynamicTypeSize, requestedType)
        .environment(\.colorScheme, scheme)
        .environment(\.locale, Locale(identifier: "zh_CN"))
        .tint(DesignTokens.accent)
        .frame(width: 430)

        let controller = UIHostingController(rootView: content)
        controller.overrideUserInterfaceStyle = appearance == "dark" ? .dark : .light
        controller.traitOverrides.preferredContentSizeCategory = category
        controller.loadViewIfNeeded()
        controller.view.backgroundColor = .systemGroupedBackground
        let window = UIWindow(windowScene: scene)
        window.overrideUserInterfaceStyle = controller.overrideUserInterfaceStyle
        window.traitOverrides.preferredContentSizeCategory = category
        window.backgroundColor = .systemGroupedBackground
        window.frame = CGRect(x: 0, y: 0, width: 430, height: 932)
        window.rootViewController = controller
        window.isHidden = false
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }
        try await waitUntil(
            { observedType != nil && observedScheme != nil },
            message: "The real native content must appear before capture.", sourceLocation: sourceLocation
        )
        try #require(observedType == requestedType, "SwiftUI content itself must inherit the requested text size.", sourceLocation: sourceLocation)
        try #require(observedScheme == scheme, sourceLocation: sourceLocation)
        try #require(controller.traitCollection.preferredContentSizeCategory == category, sourceLocation: sourceLocation)
        try #require(controller.view.traitCollection.preferredContentSizeCategory == category, sourceLocation: sourceLocation)
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()

        let canvas: CGSize
        if page == "row" {
            let measured = controller.sizeThatFits(in: CGSize(width: 430, height: CGFloat.greatestFiniteMagnitude))
            try #require(measured.width.isFinite && measured.height.isFinite, sourceLocation: sourceLocation)
            try #require(measured.width > 0 && measured.width <= 430.5 && measured.height > 0 && measured.height < 20_000, sourceLocation: sourceLocation)
            canvas = CGSize(width: 430, height: ceil(measured.height))
            if largestType {
                let baseline = UIHostingController(rootView: NativeInlineMealPreviewRow(fixture: fixture)
                    .modelContainer(fixture.container)
                    .environment(\.dynamicTypeSize, .large)
                    .environment(\.colorScheme, scheme)
                    .environment(\.locale, Locale(identifier: "zh_CN"))
                    .frame(width: 430))
                baseline.traitOverrides.preferredContentSizeCategory = .large
                let defaultSize = baseline.sizeThatFits(in: CGSize(width: 430, height: CGFloat.greatestFiniteMagnitude))
                #expect(canvas.height > defaultSize.height + 4, "Actual AX5 layout must grow, not merely have an AX5 attachment name.", sourceLocation: sourceLocation)
                Attachment.record(
                    "Native measured row: default height \(defaultSize.height) pt; AX5 height \(canvas.height) pt; category \(category.rawValue).",
                    named: "InlineMeal-\(scenario.rawValue)-\(appearance)-AX5-layout.txt", sourceLocation: sourceLocation
                )
            }
        } else {
            canvas = CGSize(width: 430, height: 932)
        }
        let image: UIImage
        if page == "row", canvas.height > 932 {
            // A 3473-pt hosting window failed drawHierarchy in the actual AX5 run.
            // Keep a real phone-sized window and capture every visible native segment,
            // rather than treating a partial/failed offscreen render as successful.
            image = try await captureLongRow(
                controller: controller, window: window, canvas: canvas,
                category: category, sourceLocation: sourceLocation
            )
        } else {
            window.frame.size = canvas
            controller.view.frame = CGRect(origin: .zero, size: canvas)
            controller.view.setNeedsLayout()
            controller.view.layoutIfNeeded()
            CATransaction.flush()
            image = try await captureHierarchy(
                controller.view, size: canvas, sourceLocation: sourceLocation
            )
        }
        let bitmap = try #require(image.cgImage, sourceLocation: sourceLocation)
        #expect(bitmap.width == 860, sourceLocation: sourceLocation)
        #expect(bitmap.height == Int(canvas.height * 2), sourceLocation: sourceLocation)
        let bytes = [UInt8](try #require(image.pngData(), sourceLocation: sourceLocation))
        try #require(bytes.count > 8, sourceLocation: sourceLocation)
        #expect(Array(bytes.prefix(8)) == [137, 80, 78, 71, 13, 10, 26, 10], sourceLocation: sourceLocation)
        Attachment.record(
            bytes, named: "NativeInlineMeal-\(page)-\(scenario.rawValue)-\(appearance)-\(largestType ? "AX5" : "default-type").png",
            sourceLocation: sourceLocation
        )
    }

    private static func captureLongRow<Content: View>(
        controller: UIHostingController<Content>, window: UIWindow, canvas: CGSize,
        category: UIContentSizeCategory, sourceLocation: SourceLocation
    ) async throws -> UIImage {
        let viewport = CGSize(width: canvas.width, height: 932)
        let host = UIViewController()
        host.overrideUserInterfaceStyle = controller.overrideUserInterfaceStyle
        host.traitOverrides.preferredContentSizeCategory = category
        host.loadViewIfNeeded()
        host.view.backgroundColor = .systemGroupedBackground
        host.view.clipsToBounds = true
        let scroll = UIScrollView(frame: CGRect(origin: .zero, size: viewport))
        scroll.contentInsetAdjustmentBehavior = .never
        scroll.showsHorizontalScrollIndicator = false
        scroll.showsVerticalScrollIndicator = false
        scroll.bounces = false
        // This is an artifact-only viewport, not an App scrolling surface. Automatic
        // iOS 26 edge blur would otherwise be baked into every stitched tile/seam.
        // Public UIScrollView.h declares UIScrollEdgeEffect.isHidden on all four edges.
        scroll.topEdgeEffect.isHidden = true
        scroll.bottomEdgeEffect.isHidden = true
        scroll.leftEdgeEffect.isHidden = true
        scroll.rightEdgeEffect.isHidden = true
        try #require(
            scroll.topEdgeEffect.isHidden && scroll.bottomEdgeEffect.isHidden
                && scroll.leftEdgeEffect.isHidden && scroll.rightEdgeEffect.isHidden,
            "The test capture viewport must not add its own automatic edge effects to the row artifact.",
            sourceLocation: sourceLocation
        )
        host.view.addSubview(scroll)

        // Preserve the actual SwiftUI controller/state; do not recreate the row for each tile.
        window.rootViewController = nil
        host.addChild(controller)
        scroll.addSubview(controller.view)
        controller.didMove(toParent: host)
        window.frame.size = viewport
        window.rootViewController = host
        host.view.frame = CGRect(origin: .zero, size: viewport)
        controller.view.frame = CGRect(origin: .zero, size: canvas)
        scroll.contentSize = canvas
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        CATransaction.flush()
        try #require(controller.view.traitCollection.preferredContentSizeCategory == category, sourceLocation: sourceLocation)

        var tiles: [(image: UIImage, start: CGFloat, sourceTop: CGFloat, height: CGFloat)] = []
        var start: CGFloat = 0
        while start < canvas.height {
            try Task.checkCancellation()
            let offset = min(start, canvas.height - viewport.height)
            scroll.setContentOffset(CGPoint(x: 0, y: offset), animated: false)
            try await waitUntil({
                scroll.window === window && controller.view.window === window
                    && abs(scroll.contentOffset.y - offset) < 0.1
            }, message: "Each actual native viewport must reach its requested content offset.", sourceLocation: sourceLocation)
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
            controller.view.layoutIfNeeded()
            CATransaction.flush()
            let tile = try await captureHierarchy(host.view, size: viewport, sourceLocation: sourceLocation)
            tiles.append((tile, start, start - offset, min(viewport.height, canvas.height - start)))
            start += viewport.height
        }
        try #require(tiles.isEmpty == false, sourceLocation: sourceLocation)
        #expect(tiles.reduce(CGFloat.zero) { $0 + $1.height } == canvas.height, sourceLocation: sourceLocation)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        format.opaque = true
        return UIGraphicsImageRenderer(size: canvas, format: format).image { output in
            for tile in tiles {
                output.cgContext.saveGState()
                output.cgContext.clip(to: CGRect(x: 0, y: tile.start, width: canvas.width, height: tile.height))
                tile.image.draw(in: CGRect(x: 0, y: tile.start - tile.sourceTop, width: viewport.width, height: viewport.height))
                output.cgContext.restoreGState()
            }
        }
    }

    private static func captureHierarchy(
        _ view: UIView, size: CGSize, sourceLocation: SourceLocation
    ) async throws -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        format.opaque = true
        var captured: UIImage?
        // Retry only an observable unsuccessful native draw, with a finite deadline.
        // No fixed delay is accepted as proof that the hierarchy rendered successfully.
        try await waitUntil({
            var rendered = false
            let image = UIGraphicsImageRenderer(size: size, format: format).image { output in
                UIColor.systemGroupedBackground.resolvedColor(with: view.traitCollection).setFill()
                output.fill(CGRect(origin: .zero, size: size))
                rendered = view.drawHierarchy(in: view.bounds, afterScreenUpdates: true)
            }
            if rendered { captured = image }
            return rendered
        }, message: "Capture must successfully draw the actual native UIView hierarchy.", sourceLocation: sourceLocation)
        return try #require(captured, sourceLocation: sourceLocation)
    }

    private static func waitForScene(sourceLocation: SourceLocation) async throws -> UIWindowScene {
        var scene: UIWindowScene?
        try await waitUntil({
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
            return scene != nil
        }, message: "An app-hosted public UIWindowScene must connect within ten seconds.", sourceLocation: sourceLocation)
        return try #require(scene, sourceLocation: sourceLocation)
    }

    private static func waitUntil(
        _ condition: () -> Bool, message: Comment, sourceLocation: SourceLocation
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

private struct NativeInlineCaptureCanvas: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorScheme) private var colorScheme
    let fixture: NativeInlineMealPreviewFixture
    let page: String
    let onContentAppeared: (DynamicTypeSize, ColorScheme) -> Void

    var body: some View {
        Group {
            switch page {
            case "today":
                NavigationStack { TodayView(initialExpandedMealID: fixture.meal.id) }
            case "history":
                MealHistoryView(initialExpandedMealID: fixture.meal.id)
            default:
                NativeInlineMealPreviewRow(fixture: fixture)
                    .fixedSize(horizontal: false, vertical: true)
                    .ignoresSafeArea(.container)
            }
        }
        .onAppear { onContentAppeared(dynamicTypeSize, colorScheme) }
    }
}
