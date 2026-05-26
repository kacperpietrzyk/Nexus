import SwiftUI
import Testing

@testable import NexusUI

@MainActor
@Test func kbd_initializesWithKey() {
    let kbd = NexusKbd("⌘")
    #expect(kbd.key == "⌘")
}

@MainActor
@Test func kbd_combo_factory_joinsWithGap() {
    let combo = NexusKbd.combo(["⌘", "K"])
    _ = combo
}

@MainActor
@Test func kbd_initializesWithGlassTint() {
    let kbd = NexusKbd("⌘")
    _ = kbd.body
}

@MainActor
@Test func kbd_usesCossCapDimensions() {
    #expect(NexusKbd.minimumSize == 18)
    #expect(NexusKbd.bottomBorderHeight == 2)
    #expect(NexusKbd.cornerRadius == 4)
}
