import Observation
import SwiftUI

/// Where the panel's arrow points, in points from the panel's leading edge.
@MainActor
@Observable
final class PanelGeometry {
    var arrowX: CGFloat?
}

/// Rounded panel with a small, soft arrow on top pointing at the menu bar item.
struct NotePanelShape: Shape {
    static let arrowHeight: CGFloat = 10
    static let arrowWidth: CGFloat = 30
    static let cornerRadius: CGFloat = 22

    var arrowX: CGFloat

    func path(in rect: CGRect) -> Path {
        let h = Self.arrowHeight
        let w = Self.arrowWidth
        let r = Self.cornerRadius
        let body = CGRect(x: rect.minX, y: rect.minY + h, width: rect.width, height: rect.height - h)
        let x = min(max(arrowX, body.minX + r + w / 2), body.maxX - r - w / 2)

        var path = Path(roundedRect: body, cornerRadius: r, style: .continuous)
        // Bell-shaped arrow: gentle shoulders, rounded tip. Overlaps the body by
        // 1 pt so the union has no seam.
        path.move(to: CGPoint(x: x - w / 2, y: body.minY + 1))
        path.addCurve(
            to: CGPoint(x: x, y: rect.minY),
            control1: CGPoint(x: x - w * 0.22, y: body.minY + 1),
            control2: CGPoint(x: x - w * 0.14, y: rect.minY)
        )
        path.addCurve(
            to: CGPoint(x: x + w / 2, y: body.minY + 1),
            control1: CGPoint(x: x + w * 0.14, y: rect.minY),
            control2: CGPoint(x: x + w * 0.22, y: body.minY + 1)
        )
        path.closeSubpath()
        return path
    }
}

/// Hosts the note screen on Liquid Glass in the panel shape.
struct NotePanelRoot<Content: View>: View {
    let geometry: PanelGeometry
    let content: Content

    var body: some View {
        GeometryReader { proxy in
            content
                .padding(.top, NotePanelShape.arrowHeight)
                .frame(width: proxy.size.width, height: proxy.size.height)
                .glassEffect(.regular, in: NotePanelShape(arrowX: geometry.arrowX ?? proxy.size.width / 2))
        }
    }
}
