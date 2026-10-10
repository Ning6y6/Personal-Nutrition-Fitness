import SwiftUI

/// Keeps the dashboard geometry stable without evaluating a missing day's nutrition.
/// Deliberately separate from EnergyProgressRing: no budget status, colored arc or endpoint.
struct EmptyRecordedEnergyRing: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack {
            Circle()
                .stroke(.quaternary, lineWidth: DesignTokens.ringLineWidth)
                .overlay {
                    if !dynamicTypeSize.isAccessibilitySize {
                        EmptyRecordedEnergyValue()
                            .padding(DesignTokens.ringLineWidth)
                    }
                }
                .frame(maxWidth: DesignTokens.ringDiameter)
                .frame(height: DesignTokens.ringDiameter)
                .padding(DesignTokens.ringLineWidth / 2)

            if dynamicTypeSize.isAccessibilitySize {
                EmptyRecordedEnergyValue()
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("今日已记录热量")
        .accessibilityValue("0 千卡。今日尚未记录餐食，不代表实际摄入为零。")
        .accessibilityIdentifier("today.emptyRecordedEnergy")
    }
}
