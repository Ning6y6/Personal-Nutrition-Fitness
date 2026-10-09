import SwiftUI

@Animatable
struct EnergyRingEndpoint: Shape {
    var progress: Double
    @AnimatableIgnored var diameter: CGFloat

    func path(in rect: CGRect) -> Path {
        Path(ellipseIn: Self.bounds(in: rect, progress: progress, diameter: diameter))
    }

    /// Geometry only: previews and device checks establish whether the cap is visually legible.
    static func bounds(in rect: CGRect, progress: Double, diameter: CGFloat) -> CGRect {
        let radius = min(rect.width, rect.height) / 2
        let angle = progress * 2 * .pi - .pi / 2
        let center = CGPoint(
            x: rect.midX + radius * cos(angle),
            y: rect.midY + radius * sin(angle)
        )
        return CGRect(
            x: center.x - diameter / 2, y: center.y - diameter / 2,
            width: diameter, height: diameter
        )
    }
}
