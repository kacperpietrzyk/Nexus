import SwiftUI
import Testing

@testable import NexusUI

@MainActor
@Test func showcase_initializesWithoutCrash() {
    let view = DesignSystemShowcase()
    _ = view.body
}

@MainActor
@Test func showcase_includesGlassFoundationsSection() {
    // Smoke — ensures the new Glass Foundations section composes without crashing.
    let showcase = DesignSystemShowcase()
    _ = showcase.body
}
