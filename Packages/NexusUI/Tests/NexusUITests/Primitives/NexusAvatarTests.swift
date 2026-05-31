import SwiftUI
import Testing

@testable import NexusUI

@Suite("NexusAvatar v4")
struct NexusAvatarTests {
    @MainActor
    @Test("Initials come from the first two name parts")
    func initials() {
        #expect(NexusAvatar(name: "Maya Chen").initials == "MC")
        #expect(NexusAvatar(name: "Jules").initials == "J")
        #expect(NexusAvatar(name: "  Ana Maria Silva  ").initials == "AM")
        #expect(NexusAvatar(name: "").initials == "?")
    }

    @MainActor
    @Test("Renders achromatic ink (no per-name hue)")
    func avatarRendersAchromatic() {
        let avatar = NexusAvatar(name: "Maya Chen", size: 28)

        #expect(avatar.size == 28)
        #expect(avatar.textColor.resolvedRGBA == NexusColor.Text.primary.resolvedRGBA)
        #expect(avatar.backgroundColor.resolvedRGBA == NexusColor.Text.muted.resolvedRGBA)
        _ = avatar.body
    }
}
