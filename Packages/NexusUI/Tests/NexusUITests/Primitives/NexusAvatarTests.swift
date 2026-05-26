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
    @Test("Hue is deterministic per name")
    func deterministicHue() {
        let first = NexusAvatar.deriveHue(from: "Maya Chen")
        let second = NexusAvatar.deriveHue(from: "Maya Chen")

        #expect(first == second)
    }

    @MainActor
    @Test("FNV-1a hue is bounded to 0 through 359")
    func hueBounds() {
        for name in ["Maya Chen", "Jules Park", "Nexus", "", "Zażółć gęślą jaźń"] {
            let hue = NexusAvatar.deriveHue(from: name)

            #expect(hue >= 0)
            #expect(hue < 360)
        }
    }

    @MainActor
    @Test("Explicit hue overrides derived hue")
    func explicitHue() {
        let avatar = NexusAvatar(name: "Maya Chen", size: 28, hue: 240)

        #expect(avatar.hue == 240)
        #expect(avatar.size == 28)
        _ = avatar.body
    }

    @MainActor
    @Test("Renders achromatic ink regardless of derived hue")
    func avatarRendersAchromatic() {
        let avatar = NexusAvatar(name: "Maya Chen", hue: 240)

        #expect(avatar.textColor.resolvedRGBA == NexusColor.Text.primary.resolvedRGBA)
        #expect(avatar.backgroundColor.resolvedRGBA == NexusColor.Text.muted.resolvedRGBA)
    }
}
