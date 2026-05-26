import SwiftUI
import Testing

@testable import NexusUI

@Suite("NexusRowQuickActions")
struct NexusRowQuickActionsTests {
    @MainActor
    @Test("Builds a cluster with real handlers")
    func quickActionsBuild() {
        var fired = false
        let cluster = NexusRowQuickActions(actions: [
            .init(icon: "checkmark") { fired = true },
            .init(icon: "clock") {},
        ])

        _ = cluster.body
        cluster.actions.first?.action()
        #expect(fired)
    }

    // MARK: - A11y label propagation (advisor follow-up A1)

    @Test("Carries explicit accessibilityLabel when provided")
    func accessibilityLabelCarried() {
        let action = NexusRowQuickAction(icon: "checkmark", accessibilityLabel: "Complete") {}
        #expect(action.accessibilityLabel == "Complete")
    }

    @Test("Falls back to icon name when accessibilityLabel is nil")
    func accessibilityLabelFallsBackToIcon() {
        let action = NexusRowQuickAction(icon: "clock") {}
        // View body: `.accessibilityLabel(quickAction.accessibilityLabel ?? quickAction.icon)`
        let resolvedLabel = action.accessibilityLabel ?? action.icon
        #expect(resolvedLabel == action.icon)
    }

    @Test("accessibilityLabel defaults to nil at model level")
    func accessibilityLabelDefaultsNil() {
        let action = NexusRowQuickAction(icon: "star") {}
        #expect(action.accessibilityLabel == nil)
    }
}
