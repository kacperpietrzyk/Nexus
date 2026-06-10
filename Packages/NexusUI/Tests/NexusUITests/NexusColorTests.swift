import SwiftUI
import Testing

@testable import NexusUI

@Suite("NexusColor Linear palette tokens")
struct NexusColorTests {
    @Test("Background tokens match Linear layered-dark surface ladder")
    func backgroundTokens() {
        // Surface 0–3: Pitch Black → Graphite → Deep Slate → control → Charcoal Grey
        assertColor(NexusColor.Background.base, r: 0.0313725, g: 0.0352941, b: 0.0392157)
        assertColor(NexusColor.Background.panel, r: 0.0588235, g: 0.0627451, b: 0.0666667)
        assertColor(NexusColor.Background.raised, r: 0.0862745, g: 0.0901961, b: 0.0941176)
        assertColor(NexusColor.Background.control, r: 0.1098039, g: 0.1137255, b: 0.1215686)
        assertColor(NexusColor.Background.controlHover, r: 0.1372549, g: 0.1450980, b: 0.1647059)
    }

    @Test("Glass tokens are white-alpha (retained for de-glass sweep)")
    func glassTokens() {
        assertColor(NexusColor.Glass.surface1, r: 1.0, g: 1.0, b: 1.0, a: 0.05)
        assertColor(NexusColor.Glass.surface2, r: 1.0, g: 1.0, b: 1.0, a: 0.06)
        assertColor(NexusColor.Glass.surface3, r: 1.0, g: 1.0, b: 1.0, a: 0.10)
    }

    @Test("Line tokens match Linear solid border values")
    func lineTokens() {
        // Solid hex values (not white-alpha) in the Linear palette
        assertColor(NexusColor.Line.hairline, r: 0.1372549, g: 0.1450980, b: 0.1647059)
        assertColor(NexusColor.Line.regular, r: 0.1725490, g: 0.1803922, b: 0.2000000)
        assertColor(NexusColor.Line.strong, r: 0.2196078, g: 0.2313725, b: 0.2470588)
    }

    @Test("Text tokens match Linear cool-biased type palette")
    func textTokens() {
        // Linear deliberately carries blue bias (Light Steel, Storm Cloud)
        assertColor(NexusColor.Text.primary, r: 0.9686275, g: 0.9725490, b: 0.9725490)
        assertColor(NexusColor.Text.secondary, r: 0.8156863, g: 0.8392157, b: 0.8784314)
        assertColor(NexusColor.Text.tertiary, r: 0.5411765, g: 0.5607843, b: 0.5960784)
        assertColor(NexusColor.Text.muted, r: 0.3843137, g: 0.4000000, b: 0.4274510)
        assertColor(NexusColor.Text.disabled, r: 0.2901961, g: 0.3019608, b: 0.3215686)
    }

    @Test("Accent tokens: Liquid violet primary action + white ink on accent")
    func accentTokens() {
        // Liquid re-skin: `Accent.lime` re-valued to the Liquid violet
        // (#6D5DFB == DS.ColorToken.accentPrimary) with white ink; the Linear
        // Neon Lime (#E4F222 / pitch-black ink) is superseded.
        assertColor(NexusColor.Accent.lime, r: 0.4274510, g: 0.3647059, b: 0.9843137)
        assertColor(NexusColor.Accent.limeInk, r: 1.0, g: 1.0, b: 1.0)
    }

    @Test("Status tokens: Emerald success, Cyan Spark info, Warning Red danger")
    func statusTokens() {
        assertColor(NexusColor.Status.success, r: 0.1529412, g: 0.6509804, b: 0.2666667)
        assertColor(NexusColor.Status.info, r: 0.0078431, g: 0.7215686, b: 0.8000000)
        assertColor(NexusColor.Status.danger, r: 0.9215686, g: 0.3411765, b: 0.3411765)
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
