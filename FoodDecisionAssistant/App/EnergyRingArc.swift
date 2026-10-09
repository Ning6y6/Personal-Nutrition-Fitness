import SwiftUI

/// The endpoint marker makes an overlapping overflow lap legible without relying on color.
struct EnergyRingArc: View {
    let progress: Double
    let startColor: Color
    let endColor: Color
    var showsEndpoint = false

    var body: some View {
        if progress > 0 {
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    AngularGradient(
                        colors: [startColor, endColor],
                        center: .center,
                        startAngle: .degrees(0),
                        endAngle: .degrees(max(progress, 0.001) * 360)
                    ),
                    style: StrokeStyle(lineWidth: DesignTokens.ringLineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .overlay {
                    if showsEndpoint {
                        EnergyRingEndpoint(progress: progress, diameter: DesignTokens.ringEndpointDiameter)
                            .fill(endColor)
                            .overlay {
                                EnergyRingEndpoint(progress: progress, diameter: DesignTokens.ringEndpointDiameter)
                                    .stroke(.primary, lineWidth: DesignTokens.ringEndpointOutlineWidth)
                            }
                            .shadow(color: .black.opacity(0.3), radius: DesignTokens.ringEndpointShadowRadius, y: 1)
                    }
                }
                .accessibilityHidden(true)
        }
    }
}
