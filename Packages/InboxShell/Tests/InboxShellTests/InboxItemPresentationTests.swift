import Foundation
import Testing

@testable import InboxShell

@Suite("InboxItemPresentation — nexusInboxSourceIcon")
struct InboxItemPresentationTests {

    // MARK: - Helpers

    private func item(
        sourceID: String,
        title: String = "Title",
        tags: [String] = []
    ) -> InboxItem {
        InboxItem(
            id: UUID(),
            sourceID: sourceID,
            title: title,
            body: nil,
            due: nil,
            tags: tags,
            createdAt: Date(timeIntervalSince1970: 0)
        )
    }

    // MARK: - sourceID-driven icons

    @Test("tasks.no-date maps to circle")
    func noDateIcon() {
        #expect(item(sourceID: "tasks.no-date").nexusInboxSourceIcon == "circle")
    }

    @Test("tasks.snoozed maps to moon.zzz")
    func snoozedIcon() {
        #expect(item(sourceID: "tasks.snoozed").nexusInboxSourceIcon == "moon.zzz")
    }

    // MARK: - Category-driven icons

    @Test("digests item maps to envelope")
    func digestsIcon() {
        // "github" in searchable text → .digests → SF Symbol "envelope"
        #expect(item(sourceID: "github.notifications", title: "Build status").nexusInboxSourceIcon == "envelope")
    }

    @Test("mentions item maps to at")
    func mentionsIcon() {
        // "linear" in searchable text → .mentions → SF Symbol "at"
        #expect(item(sourceID: "linear.feed", title: "Assigned to you").nexusInboxSourceIcon == "at")
    }

    // MARK: - Fallback icon

    @Test("people-category (orphan) item maps to tray fallback")
    func fallbackIcon() {
        // No keyword matches → .people → "tray"
        #expect(item(sourceID: "alice", title: "Hello").nexusInboxSourceIcon == "tray")
    }
}
