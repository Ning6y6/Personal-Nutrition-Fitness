import SwiftUI

/// The entry stays in today's safe area, separate from dashboard values and the
/// system tab bar. The alternate placement is preview-only, never persisted.
struct TodayMealEntryButton: View {
    enum Placement: CaseIterable, Equatable, Sendable {
        case bottom
        case toolbar
    }

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme

    let action: () -> Void

    var body: some View {
        if reduceTransparency {
            entryButton
                .buttonStyle(.borderedProminent)
        } else {
            entryButton
                .buttonStyle(.glassProminent)
        }
    }

    private var entryButton: some View {
        Button(action: action) {
            Label("记录一餐", systemImage: "plus")
                .font(.headline)
                // The approved dark accent is bright jade; system white prominent
                // text would lose contrast. Keep the native style, adapt this label.
                .foregroundStyle(colorScheme == .dark ? .black : .white)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .controlSize(.large)
        .tint(DesignTokens.accent)
        .accessibilityIdentifier("today.recordMeal")
    }
}
