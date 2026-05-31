import SwiftUI
import Testing

@testable import NexusUI

@Test func cardElevation_hasElev1AndElev2() {
    #expect(NexusCardElevation.elev1 != NexusCardElevation.elev2)
}

@MainActor
@Test func card_elev1_initializesWithoutCrash() {
    let card = NexusCard(.elev1) { Text("Hello") }
    _ = card.body  // forces SwiftUI evaluation
}

@MainActor
@Test func card_elev2_initializesWithoutCrash() {
    let card = NexusCard(.elev2) { Text("Hero") }
    _ = card.body
}

@MainActor
@Test func card_defaultsToElev1() {
    let card = NexusCard { Text("x") }
    #expect(card.elevation == .elev1)
}

@MainActor
@Test func card_elev1_usesFlatPanelSurface() {
    let card = NexusCard<EmptyView>(.elev1) { EmptyView() }
    #expect(card.surfaceFill.resolvedRGBA == NexusColor.Background.panel.resolvedRGBA)
}

@MainActor
@Test func card_elev2_usesFlatRaisedSurface() {
    let card = NexusCard<EmptyView>(.elev2) { EmptyView() }
    #expect(card.surfaceFill.resolvedRGBA == NexusColor.Background.raised.resolvedRGBA)
}
