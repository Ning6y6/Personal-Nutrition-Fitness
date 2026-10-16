import FoodDecisionCore
import Foundation
import QuartzCore
import SwiftUI
import Testing
import UIKit

@testable import FoodDecisionAssistant

/// Render-only acceptance artifacts made from fictitious, stateless fixtures.
/// UIKit hosts the real SwiftUI/system controls: ImageRenderer cannot capture ProgressView.
/// These checks do not prove interaction, clipping, animation, or VoiceOver behavior;
/// inspect the PNG attachments and perform the applicable device checks separately.
@MainActor
struct UI1NativePreviewTests {
    @Test("UI-1 native preview PNGs", .serialized, arguments: [
        ("empty", "light", false),
        ("empty", "dark", false),
        ("withinBudget", "light", false),
        ("withinBudget", "dark", false),
        ("atBudget", "light", false),
        ("atBudget", "dark", false),
        ("overflow", "light", false),
        ("overflow", "dark", false),
        ("multiple", "light", false),
        ("multiple", "dark", false),
        ("unknown", "light", false),
        ("unknown", "dark", false),
        ("multiple", "light", true),
        ("multiple", "dark", true),
    ])
    func recordNativePreview(configuration: (String, String, Bool)) async throws {
        let (scenarioName, appearance, usesLargestType) = configuration
        let scenario = try #require(UI1PreviewScenario(rawValue: scenarioName))
        let content = TodayStatusPreview(scenario: scenario)
            .environment(\.colorScheme, appearance == "dark" ? .dark : .light)
            .environment(\.dynamicTypeSize, usesLargestType ? .accessibility5 : .large)
            .environment(\.locale, Locale(identifier: "zh_CN"))
            .frame(width: 430, alignment: .topLeading)

        let typeSuffix = usesLargestType ? "-AX5" : "-default-type"
        try await recordPNG(
            content,
            named: "UI1-\(scenarioName)-\(appearance)\(typeSuffix).png",
            appearance: appearance
        )
    }

    @Test("UI-1 recorded intake without a target PNGs", arguments: ["light", "dark"])
    func recordNoTargetPreview(appearance: String) async throws {
        let nutrients = try UI1PreviewScenario.withinBudget.nutrients()
        let fibre = try FibreIntakeSummary(snapshots: [nutrients])
        let content = TodayStatusCard(
            goal: nil,
            nutrients: nutrients,
            mealCount: 2,
            fibreSummary: fibre,
            availability: .available
        )
        .padding()
        .background(DesignTokens.background)
        .tint(DesignTokens.accent)
        .environment(\.colorScheme, appearance == "dark" ? .dark : .light)
        .environment(\.dynamicTypeSize, .large)
        .environment(\.locale, Locale(identifier: "zh_CN"))
        .frame(width: 430, alignment: .topLeading)

        try await recordPNG(content, named: "UI1-no-target-\(appearance).png", appearance: appearance)
    }

    @Test("Empty recorded-zero ring with and without saved goals", .serialized, arguments: [
        ("light", false, false), ("dark", false, false),
        ("light", true, false), ("dark", true, false),
        ("light", false, true), ("dark", false, true),
        ("light", true, true), ("dark", true, true),
    ])
    func recordEmptyRing(configuration: (String, Bool, Bool)) async throws {
        let (appearance, largestType, hasGoal) = configuration
        let goal = hasGoal ? try UI1PreviewScenario.empty.goal() : nil
        let content = TodayStatusCard(
            goal: goal, nutrients: nil, mealCount: 0, fibreSummary: nil,
            availability: .noRecords
        )
        .padding()
        .background(DesignTokens.background)
        .tint(DesignTokens.accent)
        .environment(\.colorScheme, appearance == "dark" ? .dark : .light)
        .environment(\.dynamicTypeSize, largestType ? .accessibility5 : .large)
        .environment(\.locale, Locale(identifier: "zh_CN"))
        .frame(width: 430, alignment: .topLeading)

        let type = largestType ? "AX5" : "default"
        let budget = hasGoal ? "with-goal" : "no-goal"
        try await recordPNG(content, named: "EmptyEnergy-\(appearance)-\(type)-\(budget).png", appearance: appearance)
    }

    @Test("Nutrition spacing stress PNGs at narrow and wide native widths", .serialized, arguments: [
        (375, "light", false), (375, "dark", false),
        (375, "light", true), (375, "dark", true),
        (430, "light", false), (430, "dark", false),
        (430, "light", true), (430, "dark", true),
    ])
    func recordNutritionSpacingMatrix(configuration: (Int, String, Bool)) async throws {
        let (widthPoints, appearance, largestType) = configuration
        let width = CGFloat(widthPoints)
        let requestedType: DynamicTypeSize = largestType ? .accessibility5 : .large
        let category: UIContentSizeCategory = largestType ? .accessibilityExtraExtraExtraLarge : .large
        let scheme: ColorScheme = appearance == "dark" ? .dark : .light
        let goal = try UI1PreviewScenario.multiple.goal()
        // Synthetic amounts exercise wrapping budget and upper-limit labels
        // without an extreme render canvas. They never enter a ModelContainer.
        let known = try NutrientValues(
            energyKcal: 6_400, fatGrams: 162.8, saturatedFatGrams: 32.4,
            carbohydrateGrams: 765.4, sugarGrams: 20, proteinGrams: 96,
            saltGrams: 3, fibreGrams: 18
        )
        let unknown = try NutrientValues(
            energyKcal: 15, fatGrams: 0.3, saturatedFatGrams: 0.1,
            carbohydrateGrams: 2.6, sugarGrams: 2.4, proteinGrams: 0.8,
            saltGrams: 0.01, fibreGrams: nil
        )
        let nutrients = try NutrientValues.sum([known, unknown])
        let fibre = try FibreIntakeSummary(snapshots: [known, unknown])
        try #require(fibre.knownComponentCount == 1 && fibre.unknownComponentCount == 1)
        try #require(fibre.knownSubtotalGrams == 18 && fibre.exactGrams == nil)
        let saturatedFatLimit = try #require(goal.saturatedFatLimitGrams)
        try #require(nutrients.carbohydrateGrams > goal.carbohydrateGrams
                     && nutrients.fatGrams > goal.fatGrams
                     && nutrients.saturatedFatGrams > saturatedFatLimit)
        var observedType: DynamicTypeSize?
        var observedScheme: ColorScheme?
        let content = TodayStatusCard(
            goal: goal, nutrients: nutrients, mealCount: 2,
            fibreSummary: fibre, availability: .available
        )
        .padding()
        .background(DesignTokens.background)
        .tint(DesignTokens.accent)
        .background {
            UI1NativeEnvironmentProbe { type, color in
                observedType = type
                observedScheme = color
            }
        }
        .environment(\.colorScheme, scheme)
        .environment(\.dynamicTypeSize, requestedType)
        .environment(\.locale, Locale(identifier: "zh_CN"))
        .frame(width: width, alignment: .topLeading)

        let type = largestType ? "AX5" : "regular"
        // PNG and finite geometry checks support visual review of an isolated
        // real card. They do not prove full-screen interaction or VoiceOver.
        try await recordPNG(
            content, named: "NutritionSpacing-\(widthPoints)pt-\(appearance)-\(type).png",
            appearance: appearance, width: width, contentSizeCategory: category,
            scale: largestType ? 1 : 2,
            isContentReady: { observedType != nil && observedScheme != nil }
        )
        #expect(observedType == requestedType, "The rendered SwiftUI content must inherit the requested text size.")
        #expect(observedScheme == scheme, "The rendered SwiftUI content must inherit the requested appearance.")
    }

    private func recordPNG<Content: View>(
        _ content: Content,
        named name: String,
        appearance: String,
        width: CGFloat = 430,
        contentSizeCategory: UIContentSizeCategory? = nil,
        scale: CGFloat = 2,
        isContentReady: (() -> Bool)? = nil,
        sourceLocation: SourceLocation = #_sourceLocation
    ) async throws {
        let scene = try await waitForWindowScene(sourceLocation: sourceLocation)
        let controller = UIHostingController(rootView: content)
        // This artifact captures an isolated card, not the phone's navigation/status bars.
        // Public safeAreaRegions avoids adding the device's top/bottom bars to the card.
        controller.safeAreaRegions = []
        controller.overrideUserInterfaceStyle = appearance == "dark" ? .dark : .light
        if let contentSizeCategory {
            controller.traitOverrides.preferredContentSizeCategory = contentSizeCategory
        }
        controller.loadViewIfNeeded()
        controller.view.tintAdjustmentMode = .normal

        let window = UIWindow(windowScene: scene)
        window.tintAdjustmentMode = .normal
        window.overrideUserInterfaceStyle = controller.overrideUserInterfaceStyle
        if let contentSizeCategory {
            window.traitOverrides.preferredContentSizeCategory = contentSizeCategory
        }
        window.frame = CGRect(x: 0, y: 0, width: width, height: 1)
        window.rootViewController = controller
        window.isHidden = false
        // Do not make this window key or replace the application's existing root window.
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }

        if let isContentReady {
            let clock = ContinuousClock()
            let deadline = clock.now.advanced(by: .seconds(10))
            while !isContentReady(), clock.now < deadline {
                try Task.checkCancellation()
                let remaining = clock.now.duration(to: deadline)
                try await Task.sleep(for: min(.milliseconds(50), remaining))
            }
            try #require(isContentReady(), "The real SwiftUI environment must be observed before capture.", sourceLocation: sourceLocation)
        }
        if let contentSizeCategory {
            try #require(controller.traitCollection.preferredContentSizeCategory == contentSizeCategory, sourceLocation: sourceLocation)
            try #require(controller.view.traitCollection.preferredContentSizeCategory == contentSizeCategory, sourceLocation: sourceLocation)
        }

        let fitted = controller.sizeThatFits(in: CGSize(width: width, height: CGFloat.greatestFiniteMagnitude))
        try #require(fitted.width.isFinite && fitted.width > 0 && fitted.width <= width + 0.5,
                     sourceLocation: sourceLocation)
        try #require(fitted.height.isFinite && fitted.height > 0, sourceLocation: sourceLocation)
        let canvas = CGSize(width: width, height: ceil(fitted.height))
        if let contentSizeCategory {
            let geometry = "\(name): fitted=\(fitted), logicalCanvas=\(canvas), scale=\(scale), pixels=\(canvas.width * scale)×\(canvas.height * scale), category=\(contentSizeCategory.rawValue), nativeDisplayScale=\(controller.view.traitCollection.displayScale), hostingContentScale=\(controller.view.contentScaleFactor), windowContentScale=\(window.contentScaleFactor)"
            print("Native card capture: \(geometry)")
            Attachment.record(geometry, named: "\(name)-geometry.txt", sourceLocation: sourceLocation)
        }
        if let contentSizeCategory, contentSizeCategory.isAccessibilityCategory {
            // This new matrix uses equal native viewport segments at both widths.
            // The original entry points retain their existing whole-card capture.
            try await recordNativeSegments(
                controller: controller, window: window, canvas: canvas, name: name,
                category: contentSizeCategory, scale: scale, sourceLocation: sourceLocation
            )
            return
        }
        window.frame = CGRect(origin: .zero, size: canvas)
        controller.view.frame = CGRect(origin: .zero, size: canvas)
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        CATransaction.flush()

        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: canvas, format: format)
        var renderedHierarchy = false
        let image = renderer.image { _ in
            renderedHierarchy = controller.view.drawHierarchy(
                in: controller.view.bounds,
                afterScreenUpdates: true
            )
        }
        try #require(renderedHierarchy, "The native view hierarchy must finish rendering.", sourceLocation: sourceLocation)
        let bitmap = try #require(image.cgImage, sourceLocation: sourceLocation)
        #expect(bitmap.width == Int(width * format.scale), "The PNG must preserve the requested canvas width and scale.", sourceLocation: sourceLocation)
        #expect(bitmap.height == Int(canvas.height * format.scale), sourceLocation: sourceLocation)
        #expect(bitmap.height > 0, sourceLocation: sourceLocation)

        let data = try #require(image.pngData(), sourceLocation: sourceLocation)
        let bytes = [UInt8](data)
        #expect(bytes.count > 8, sourceLocation: sourceLocation)
        #expect(Array(bytes.prefix(8)) == [137, 80, 78, 71, 13, 10, 26, 10], sourceLocation: sourceLocation)
        Attachment.record(bytes, named: name, sourceLocation: sourceLocation)
    }

    private func recordNativeSegments<Content: View>(
        controller: UIHostingController<Content>, window: UIWindow, canvas: CGSize,
        name: String, category: UIContentSizeCategory, scale: CGFloat,
        sourceLocation: SourceLocation
    ) async throws {
        let viewport = CGSize(width: canvas.width, height: min(900, canvas.height))
        let overlap: CGFloat = min(64, viewport.height / 4)
        let host = UIViewController()
        host.overrideUserInterfaceStyle = controller.overrideUserInterfaceStyle
        host.traitOverrides.preferredContentSizeCategory = category
        host.loadViewIfNeeded()
        host.view.clipsToBounds = true
        host.view.backgroundColor = .systemGroupedBackground
        // Keep the same SwiftUI controller and complete logical content. Only
        // its position changes inside the clipped native capture viewport.
        window.rootViewController = nil
        host.addChild(controller)
        host.view.addSubview(controller.view)
        controller.didMove(toParent: host)
        window.frame = CGRect(origin: .zero, size: viewport)
        window.rootViewController = host
        host.view.frame = CGRect(origin: .zero, size: viewport)

        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = true
        var offset: CGFloat = 0
        var previousBottom: CGFloat = 0
        var segment = 1
        while true {
            try Task.checkCancellation()
            controller.view.frame = CGRect(x: 0, y: -offset, width: canvas.width, height: canvas.height)
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
            controller.view.setNeedsLayout()
            controller.view.layoutIfNeeded()
            await Task.yield()
            CATransaction.flush()
            try #require(controller.view.window === window, sourceLocation: sourceLocation)
            try #require(controller.view.traitCollection.preferredContentSizeCategory == category, sourceLocation: sourceLocation)
            let bottom = min(offset + viewport.height, canvas.height)
            let sharedHeight = segment == 1 ? 0 : max(0, previousBottom - offset)
            let stem = name.hasSuffix(".png") ? String(name.dropLast(4)) : name
            let segmentName = "\(stem)-segment\(segment)-top\(Int(offset))-bottom\(Int(bottom))"
            let geometry = "segment=\(segment), contentTop=\(offset), contentBottom=\(bottom), overlapPrevious=\(sharedHeight), logicalCanvas=\(canvas), viewport=\(viewport), hostingFrame=\(controller.view.frame), bitmapScale=\(scale)"
            print("Native card segment: \(geometry)")
            Attachment.record(geometry, named: "\(segmentName)-geometry.txt", sourceLocation: sourceLocation)
            var renderedHierarchy = false
            let image = UIGraphicsImageRenderer(size: viewport, format: format).image { _ in
                renderedHierarchy = window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            try #require(renderedHierarchy, "Every segment must successfully draw the real native window hierarchy.", sourceLocation: sourceLocation)
            let bitmap = try #require(image.cgImage, sourceLocation: sourceLocation)
            #expect(bitmap.width == Int(viewport.width * scale), sourceLocation: sourceLocation)
            #expect(bitmap.height == Int(viewport.height * scale), sourceLocation: sourceLocation)
            let bytes = [UInt8](try #require(image.pngData(), sourceLocation: sourceLocation))
            try #require(bytes.count > 8, sourceLocation: sourceLocation)
            #expect(Array(bytes.prefix(8)) == [137, 80, 78, 71, 13, 10, 26, 10], sourceLocation: sourceLocation)
            // Each overlapping segment is its own artifact, never a stitched image.
            Attachment.record(bytes, named: "\(segmentName).png", sourceLocation: sourceLocation)
            if bottom >= canvas.height { break }
            previousBottom = bottom
            offset = min(offset + viewport.height - overlap, canvas.height - viewport.height)
            segment += 1
        }
    }

    private func waitForWindowScene(
        sourceLocation: SourceLocation
    ) async throws -> UIWindowScene {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(10))
        var connectedScene: UIWindowScene?

        // App-hosted tests may start before UIKit connects the first scene. Poll actual
        // public readiness, yielding the main actor between attempts, not a fixed delay
        // that assumes launch succeeded. No app lifecycle or global preference is changed.
        while true {
            try Task.checkCancellation()
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            connectedScene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
            if connectedScene != nil || clock.now >= deadline { break }
            let remaining = clock.now.duration(to: deadline)
            try await Task.sleep(for: min(.milliseconds(50), remaining))
        }

        return try #require(
            connectedScene,
            "The app-hosted simulator render requires a connected UIWindowScene; none became available within 10 seconds.",
            sourceLocation: sourceLocation
        )
    }
}

private struct UI1NativeEnvironmentProbe: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorScheme) private var colorScheme

    let observe: (DynamicTypeSize, ColorScheme) -> Void

    var body: some View {
        Color.clear.onAppear { observe(dynamicTypeSize, colorScheme) }
    }
}
