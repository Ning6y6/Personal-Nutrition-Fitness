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

    private func recordPNG<Content: View>(
        _ content: Content,
        named name: String,
        appearance: String,
        sourceLocation: SourceLocation = #_sourceLocation
    ) async throws {
        let scene = try await waitForWindowScene(sourceLocation: sourceLocation)
        let controller = UIHostingController(rootView: content)
        // This artifact captures an isolated card, not the phone's navigation/status bars.
        // Public safeAreaRegions avoids adding the device's top/bottom bars to the card.
        controller.safeAreaRegions = []
        controller.overrideUserInterfaceStyle = appearance == "dark" ? .dark : .light
        controller.loadViewIfNeeded()
        controller.view.tintAdjustmentMode = .normal

        let window = UIWindow(windowScene: scene)
        window.tintAdjustmentMode = .normal
        window.overrideUserInterfaceStyle = controller.overrideUserInterfaceStyle
        window.frame = CGRect(x: 0, y: 0, width: 430, height: 1)
        window.rootViewController = controller
        window.isHidden = false
        // Do not make this window key or replace the application's existing root window.
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }

        let fitted = controller.sizeThatFits(in: CGSize(width: 430, height: CGFloat.greatestFiniteMagnitude))
        try #require(fitted.height.isFinite && fitted.height > 0, sourceLocation: sourceLocation)
        let canvas = CGSize(width: 430, height: ceil(fitted.height))
        window.frame = CGRect(origin: .zero, size: canvas)
        controller.view.frame = CGRect(origin: .zero, size: canvas)
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        CATransaction.flush()

        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
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
        #expect(bitmap.width == 860, "430 pt at 2x must preserve the intended canvas width.", sourceLocation: sourceLocation)
        #expect(bitmap.height == Int(canvas.height * 2), sourceLocation: sourceLocation)
        #expect(bitmap.height > 0, sourceLocation: sourceLocation)

        let data = try #require(image.pngData(), sourceLocation: sourceLocation)
        let bytes = [UInt8](data)
        #expect(bytes.count > 8, sourceLocation: sourceLocation)
        #expect(Array(bytes.prefix(8)) == [137, 80, 78, 71, 13, 10, 26, 10], sourceLocation: sourceLocation)
        Attachment.record(bytes, named: name, sourceLocation: sourceLocation)
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
