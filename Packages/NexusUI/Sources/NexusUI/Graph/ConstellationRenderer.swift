#if os(macOS) || os(iOS)
import SwiftUI

/// The look of the knowledge graph: nodes are luminous orbs (accent-coloured
/// glow + bright core + sheen), edges are gradient filaments that fade between
/// their endpoints' accents, labels ride a glassy chip for legibility on the
/// dark aurora backdrop. Pure drawing into a `GraphicsContext` — all geometry
/// (layout, projection, fit) lives in the view; this only decides appearance.
enum ConstellationRenderer {
    /// Screen-space orb radius. Hubs grow on sqrt(degree); the focus node is the
    /// brightest, biggest star so the eye anchors on it.
    static func nodeRadius(degree: Int, isFocus: Bool) -> CGFloat {
        let base = min(16, 6.2 + 1.8 * CGFloat(Double(max(0, degree)).squareRoot()))
        return isFocus ? max(base, 12) * 1.18 : base
    }

    // MARK: Edges

    // swiftlint:disable:next function_parameter_count
    static func drawEdge(
        _ context: GraphicsContext,
        from start: CGPoint,
        to end: CGPoint,
        colorStart: Color,
        colorEnd: Color,
        emphasized: Bool,
        dimmed: Bool
    ) {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = max(1, (dx * dx + dy * dy).squareRoot())
        // Barely-there bow — keeps edges from looking mechanical without snaking.
        let bow = min(10, length * 0.045)
        let control = CGPoint(
            x: (start.x + end.x) / 2 - dy / length * bow,
            y: (start.y + end.y) / 2 + dx / length * bow)
        var path = Path()
        path.move(to: start)
        path.addQuadCurve(to: end, control: control)

        let alpha: Double = dimmed ? 0.08 : (emphasized ? 0.9 : 0.34)
        let shading = GraphicsContext.Shading.linearGradient(
            Gradient(colors: [colorStart.opacity(alpha), colorEnd.opacity(alpha)]),
            startPoint: start, endPoint: end)
        context.stroke(path, with: shading, lineWidth: emphasized ? 1.8 : 1.0)
    }

    // MARK: Nodes

    /// The soft accent glow. Drawn in its own pass under every core so a node's
    /// halo never washes out a neighbour's body.
    static func drawHalo(
        _ context: GraphicsContext,
        at point: CGPoint,
        radius: CGFloat,
        color: Color,
        intensity: Double
    ) {
        let haloRadius = radius * 3.4
        let rect = CGRect(
            x: point.x - haloRadius, y: point.y - haloRadius,
            width: haloRadius * 2, height: haloRadius * 2)
        let shading = GraphicsContext.Shading.radialGradient(
            Gradient(stops: [
                .init(color: color.opacity(0.55 * intensity), location: 0),
                .init(color: color.opacity(0.16 * intensity), location: 0.5),
                .init(color: color.opacity(0), location: 1),
            ]),
            center: point, startRadius: 0, endRadius: haloRadius)
        context.fill(Path(ellipseIn: rect), with: shading)
    }

    // swiftlint:disable:next function_parameter_count
    static func drawCore(
        _ context: GraphicsContext,
        at point: CGPoint,
        radius: CGFloat,
        color: Color,
        isFocus: Bool,
        isSelected: Bool,
        dimmed: Bool,
        glyph: String?
    ) {
        let coreRect = CGRect(
            x: point.x - radius, y: point.y - radius,
            width: radius * 2, height: radius * 2)
        // Luminous disc: a centred radial (bright core → accent edge) gives depth
        // without the offset plastic specular that read as a candy orb.
        let body = GraphicsContext.Shading.radialGradient(
            Gradient(colors: [color.opacity(dimmed ? 0.5 : 1.0), color.opacity(dimmed ? 0.3 : 0.78)]),
            center: point, startRadius: 0, endRadius: radius)
        context.fill(Path(ellipseIn: coreRect), with: body)
        // Crisp light rim for definition against the dark field.
        context.stroke(
            Path(ellipseIn: coreRect),
            with: .color(.white.opacity(dimmed ? 0.08 : 0.28)), lineWidth: 0.75)

        // Kind glyph rides inside hero nodes only — identity without clutter.
        if let glyph, radius >= 9 {
            let icon = context.resolve(
                Text(Image(systemName: glyph))
                    .font(.system(size: radius * 0.92, weight: .semibold))
                    .foregroundStyle(DS.ColorToken.backgroundApp.opacity(dimmed ? 0.5 : 0.92)))
            context.draw(icon, at: point)
        }

        if isFocus {
            let ringRadius = radius + 7
            let ringRect = CGRect(
                x: point.x - ringRadius, y: point.y - ringRadius,
                width: ringRadius * 2, height: ringRadius * 2)
            context.stroke(
                Path(ellipseIn: ringRect),
                with: .color(color.opacity(0.5)), lineWidth: 1)
        }
        if isSelected {
            let selRadius = radius + (isFocus ? 12 : 4)
            let selRect = CGRect(
                x: point.x - selRadius, y: point.y - selRadius,
                width: selRadius * 2, height: selRadius * 2)
            context.stroke(
                Path(ellipseIn: selRect),
                with: .color(DS.ColorToken.textPrimary.opacity(0.9)), lineWidth: 1.5)
        }
    }

    // MARK: Labels

    /// A clean caption pill below the node. Kind is already carried by the node's
    /// color, so no glyph here — just legible text on an opaque chip, placed clear
    /// of the orb (and its focus ring) via `topOffset`.
    static func drawLabel(
        _ context: GraphicsContext,
        at point: CGPoint,
        topOffset: CGFloat,
        title: String,
        emphasized: Bool
    ) {
        let text = context.resolve(
            Text(displayTitle(title))
                .font(DS.FontToken.caption)
                .foregroundStyle(emphasized ? DS.ColorToken.textPrimary : DS.ColorToken.textSecondary))
        let textSize = text.measure(in: CGSize(width: 260, height: 40))

        let padH: CGFloat = 9
        let padV: CGFloat = 4
        let chipWidth = padH * 2 + textSize.width
        let chipHeight = padV * 2 + textSize.height
        let chipRect = CGRect(
            x: point.x - chipWidth / 2, y: point.y + topOffset,
            width: chipWidth, height: chipHeight)
        let chip = Path(roundedRect: chipRect, cornerRadius: chipHeight / 2, style: .continuous)
        context.fill(chip, with: .color(DS.ColorToken.backgroundSunken.opacity(emphasized ? 0.96 : 0.84)))
        context.stroke(
            chip,
            with: .color(emphasized ? DS.ColorToken.strokeDefault : DS.ColorToken.strokeHairline),
            lineWidth: 0.5)
        context.draw(text, at: CGPoint(x: chipRect.midX, y: chipRect.midY))
    }

    static func displayTitle(_ title: String, maxLength: Int = 40) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Untitled" }
        guard trimmed.count > maxLength else { return trimmed }
        return String(trimmed.prefix(maxLength)) + "…"
    }
}
#endif
