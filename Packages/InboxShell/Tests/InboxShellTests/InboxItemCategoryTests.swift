import Foundation
import Testing

@testable import InboxShell

@Suite("InboxItemCategory — sourceID prefix authority")
struct InboxItemCategoryTests {

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

    @Test("tasks.* prefix wins over @ mention heuristic")
    func taskWithMentionTitleIsTasks() {
        #expect(item(sourceID: "tasks.no-date", title: "@alice").category == .tasks)
    }

    @Test("tasks.* prefix wins over digest heuristic")
    func taskWithDigestTitleIsTasks() {
        #expect(item(sourceID: "tasks.snoozed", title: "GitHub PR follow-up").category == .tasks)
    }

    @Test("non-task source still classifies as mentions")
    func mentionSourceIsMentions() {
        #expect(item(sourceID: "linear.feed", title: "Assigned to you").category == .mentions)
    }
}
