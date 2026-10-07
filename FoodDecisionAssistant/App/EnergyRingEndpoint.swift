import SwiftUI

@Animatable
struct EnergyRingEndpoint: Shape {
    var progress: Double
    @AnimatableIgnored var diameter: CGFloat

    func path(in rect: CGRect) -> Path {
        let radius = min(rect.width, rect.height) / 2
        let angle = progress * 2 * .pi - .pi / 2
        let center = CGPoint(
            x: rect.midX + radius * cos(angle),
            y: rect.midY + radius * sin(angle)
        )
        return Path(ellipseIn: CGRect(
            x: center.x - diameter / 2, y: center.y - diameter / 2,
            width: diameter, height: diameter
        ))
    }
}
