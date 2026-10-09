import SwiftUI

/// Semantic roles, not a second set of custom control sizes or animation timings.
/// Asset colors adapt to light/dark appearance; typography stays Dynamic Type/system-native.
enum DesignTokens {
    static let accent = Color("AccentColor")
    static let warning = Color.orange
    static let warningText = Color("WarningText")
    static let hardConstraint = Color.red
    static let surface = Color("GroupedSurface")
    static let background = Color("GroupedBackground")
    static let ringStart = Color("EnergyRingStart")
    static let ringEnd = Color("EnergyRingEnd")
    static let overflowStart = Color("OverflowRingStart")
    static let overflowEnd = Color.orange
    static let ringDiameter: CGFloat = 240
    static let ringLineWidth: CGFloat = 16
    // A slightly wider, outlined endpoint remains visible where two laps overlap.
    static let ringEndpointDiameter: CGFloat = ringLineWidth + 4
    static let ringEndpointOutlineWidth: CGFloat = 2
    static let ringEndpointShadowRadius: CGFloat = 3
}
