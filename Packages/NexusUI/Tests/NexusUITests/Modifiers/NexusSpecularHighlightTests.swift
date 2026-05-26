#if os(macOS)
import SwiftUI
import Testing

@testable import NexusUI

struct NexusSpecularHighlightTests {

    @Test func tintMatchesCanvasToken() {
        let expected = NexusColor.Glass.surface3
        #expect(NexusSpecularHighlight.tintColor.resolvedRGBA == expected.resolvedRGBA)
    }

    @Test func tintEqualsGlassToken() {
        #expect(NexusSpecularHighlight.tintColor == NexusColor.Glass.surface3)
    }

    @Test func defaultRadiusIs220() {
        #expect(NexusSpecularHighlight.defaultRadius == 220)
    }
}
#endif
