import SwiftUI
import Testing

@testable import NexusUI

@Suite("NexusColor achromatic LabKit tokens")
struct NexusColorTests {
    @Test("Background tokens are luma-preserving true neutral grays (audit #14)")
    func backgroundTokens() {
        // Former cool-biased values neutralized to Rec.601 luma grays
        // (R == G == B). Numbers below = V/255 for the new single value.
        assertColor(NexusColor.Background.base, r: 0.0392157, g: 0.0392157, b: 0.0392157)
        assertColor(NexusColor.Background.panel, r: 0.0549020, g: 0.0549020, b: 0.0549020)
        assertColor(NexusColor.Background.raised, r: 0.0823529, g: 0.0823529, b: 0.0823529)
        assertColor(NexusColor.Background.control, r: 0.1019608, g: 0.1019608, b: 0.1019608)
        assertColor(NexusColor.Background.controlHover, r: 0.1215686, g: 0.1215686, b: 0.1215686)
    }

    @Test("Glass tokens are achromatic white-alpha")
    func glassTokens() {
        assertColor(NexusColor.Glass.surface1, r: 1.0, g: 1.0, b: 1.0, a: 0.05)
        assertColor(NexusColor.Glass.surface2, r: 1.0, g: 1.0, b: 1.0, a: 0.06)
        assertColor(NexusColor.Glass.surface3, r: 1.0, g: 1.0, b: 1.0, a: 0.10)
    }

    @Test("Line tokens are achromatic white-alpha")
    func lineTokens() {
        assertColor(NexusColor.Line.hairline, r: 1.0, g: 1.0, b: 1.0, a: 0.07)
        assertColor(NexusColor.Line.regular, r: 1.0, g: 1.0, b: 1.0, a: 0.10)
        assertColor(NexusColor.Line.strong, r: 1.0, g: 1.0, b: 1.0, a: 0.16)
    }

    @Test("Text tokens are luma-preserving true neutral grays (audit #14)")
    func textTokens() {
        assertColor(NexusColor.Text.primary, r: 0.9490196, g: 0.9490196, b: 0.9490196)
        assertColor(NexusColor.Text.secondary, r: 0.7843137, g: 0.7843137, b: 0.7843137)
        assertColor(NexusColor.Text.tertiary, r: 0.5568627, g: 0.5568627, b: 0.5568627)
        assertColor(NexusColor.Text.muted, r: 0.3921569, g: 0.3921569, b: 0.3921569)
        assertColor(NexusColor.Text.disabled, r: 0.2745098, g: 0.2745098, b: 0.2745098)
    }

    @Test("Every tonal token is genuinely zero-hue (R == G == B) — #14 regression lock")
    func tonalTokensAreTrueNeutralGray() {
        let tonal: [Color] = [
            NexusColor.Background.base, NexusColor.Background.panel,
            NexusColor.Background.raised, NexusColor.Background.control,
            NexusColor.Background.controlHover,
            NexusColor.Text.primary, NexusColor.Text.secondary,
            NexusColor.Text.tertiary, NexusColor.Text.muted,
            NexusColor.Text.disabled,
        ]
        for color in tonal {
            let rgba = color.resolvedRGBA
            #expect(abs(rgba.r - rgba.g) < 0.0001)
            #expect(abs(rgba.g - rgba.b) < 0.0001)
        }
    }

}

private func assertColor(
    _ color: Color,
    r expectedR: Double,
    g expectedG: Double,
    b expectedB: Double,
    a expectedA: Double = 1.0,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    let resolved = color.resolvedRGBA
    #expect(abs(resolved.r - expectedR) < 0.0001, sourceLocation: sourceLocation)
    #expect(abs(resolved.g - expectedG) < 0.0001, sourceLocation: sourceLocation)
    #expect(abs(resolved.b - expectedB) < 0.0001, sourceLocation: sourceLocation)
    #expect(abs(resolved.a - expectedA) < 0.0001, sourceLocation: sourceLocation)
}
