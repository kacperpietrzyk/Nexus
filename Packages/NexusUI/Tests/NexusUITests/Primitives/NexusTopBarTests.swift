#if !os(watchOS)
import SwiftUI
import Testing

@testable import NexusUI

@Suite("NexusTopBar v4")
struct NexusTopBarTests {
    @MainActor
    @Test("Builds with breadcrumbs + trailing slot")
    func buildWithTrailingSlot() {
        let bar = NexusTopBar(crumbs: ["Workspace", "Today"]) {
            Color.clear
        }

        _ = bar.body
    }

    @MainActor
    @Test("Builds without search pill or trailing slot")
    func buildWithoutSearchPill() {
        let bar = NexusTopBar(crumbs: ["Workspace"], showSearchPill: false)

        _ = bar.body
    }

    @MainActor
    @Test("Search-pill metrics stay fixed (capsule bar has no fixed height)")
    func metrics() {
        #expect(NexusTopBar<EmptyView>.searchHeight == 30)
        #expect(NexusTopBar<EmptyView>.searchMinWidth == 240)
    }
}
#endif
