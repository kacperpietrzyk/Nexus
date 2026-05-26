#if os(macOS)
import Foundation
import Testing
@testable import InboxShell

@Suite("InboxSectionBuilder")
struct InboxSectionBuilderTests {

    // MARK: - Helpers

    private func item(
        id: UUID = UUID(),
        sourceID: String,
        title: String = "Title",
        body: String? = nil,
        tags: [String] = []
    ) -> InboxItem {
        InboxItem(
            id: id,
            sourceID: sourceID,
            title: title,
            body: body,
            due: nil,
            tags: tags,
            createdAt: Date(timeIntervalSince1970: 0)
        )
    }

    // MARK: - Oracle section order

    @Test("sections returns oracle order: NO DATE / SNOOZED / E-MAIL / MENTIONS")
    func oracleOrder() {
        let items = [
            item(sourceID: "linear.feed", title: "@alice review"),  // .mentions → MENTIONS
            item(sourceID: "github.notifications", title: "PR #42"),  // .digests → E-MAIL
            item(sourceID: "tasks.snoozed"),  // → SNOOZED
            item(sourceID: "tasks.no-date"),  // → NO DATE
        ]
        let sections = InboxSectionBuilder.sections(from: items)
        #expect(sections.map(\.title) == ["NO DATE", "SNOOZED", "E-MAIL", "MENTIONS"])
    }

    // MARK: - sourceID bucketing

    @Test("tasks.no-date goes to NO DATE")
    func noDateBucket() {
        let noDateItem = item(sourceID: "tasks.no-date", title: "Buy oat milk")
        let sections = InboxSectionBuilder.sections(from: [noDateItem])
        #expect(sections.count == 1)
        #expect(sections[0].title == "NO DATE")
        #expect(sections[0].items.map(\.id) == [noDateItem.id])
    }

    @Test("tasks.snoozed goes to SNOOZED")
    func snoozedBucket() {
        let snoozedItem = item(sourceID: "tasks.snoozed", title: "Follow up")
        let sections = InboxSectionBuilder.sections(from: [snoozedItem])
        #expect(sections.count == 1)
        #expect(sections[0].title == "SNOOZED")
        #expect(sections[0].items.map(\.id) == [snoozedItem.id])
    }

    // MARK: - Category fallthrough

    @Test("github sourceID resolves to digests bucket (E-MAIL)")
    func digestsBucket() {
        // category heuristic: searchable contains "github" → .digests → E-MAIL
        let digestItem = item(sourceID: "github.notifications", title: "PR merged")
        let sections = InboxSectionBuilder.sections(from: [digestItem])
        #expect(sections.count == 1)
        #expect(sections[0].title == "E-MAIL")
        #expect(sections[0].items.map(\.id) == [digestItem.id])
    }

    @Test("linear sourceID resolves to mentions bucket (MENTIONS)")
    func mentionsBucket() {
        // category heuristic: searchable contains "linear" → .mentions → MENTIONS
        let mentionItem = item(sourceID: "linear.feed", title: "Review requested")
        let sections = InboxSectionBuilder.sections(from: [mentionItem])
        #expect(sections.count == 1)
        #expect(sections[0].title == "MENTIONS")
        #expect(sections[0].items.map(\.id) == [mentionItem.id])
    }

    // MARK: - Empty-bucket omission

    @Test("empty buckets are omitted from result")
    func emptyBucketOmission() {
        // Only a no-date item — the other 3 sections have zero items and
        // must not appear.
        let onlyNoDate = item(sourceID: "tasks.no-date")
        let sections = InboxSectionBuilder.sections(from: [onlyNoDate])
        #expect(sections.count == 1)
        #expect(sections[0].title == "NO DATE")
    }

    @Test("empty input produces no sections")
    func emptyInput() {
        let sections = InboxSectionBuilder.sections(from: [])
        #expect(sections.isEmpty)
    }

    // MARK: - Orphan-drop

    @Test("people-category item appears in no section (orphan-drop)")
    func orphanDrop() {
        // category heuristic: searchable has none of @/mention/linear/digest/
        // github/calendar/task; sourceID doesn't start with tasks. → .people
        // The builder has no oracle section for .people → item is dropped.
        let orphanID = UUID()
        let orphan = item(id: orphanID, sourceID: "alice", title: "Hello")

        // Mix in a valid item so the test is meaningful (non-empty input).
        let noDateItem = item(sourceID: "tasks.no-date")
        let sections = InboxSectionBuilder.sections(from: [orphan, noDateItem])

        // Orphan must not appear in any section.
        let allIDs = sections.flatMap { $0.items.map(\.id) }
        #expect(!allIDs.contains(orphanID))

        // Only the NO DATE section with the valid item remains.
        #expect(sections.count == 1)
        #expect(sections[0].title == "NO DATE")
    }

    @Test("tasks-category item from unregistered source is also dropped")
    func tasksOrphanDrop() {
        // sourceID doesn't match tasks.no-date/tasks.snoozed, but tags contain
        // "task" → category == .tasks, no oracle section → dropped.
        let tasksOrphanID = UUID()
        let tasksOrphan = item(
            id: tasksOrphanID,
            sourceID: "reminder.foo",
            title: "Reminder",
            tags: ["task"]
        )
        let sections = InboxSectionBuilder.sections(from: [tasksOrphan])
        let allIDs = sections.flatMap { $0.items.map(\.id) }
        #expect(!allIDs.contains(tasksOrphanID))
        #expect(sections.isEmpty)
    }

    // MARK: - Section item membership

    @Test("each section contains exactly the expected items")
    func sectionItemMembership() {
        let ndID = UUID()
        let snoozedID = UUID()
        let digestID = UUID()
        let mentionID = UUID()

        let noDate = item(id: ndID, sourceID: "tasks.no-date")
        let snoozed = item(id: snoozedID, sourceID: "tasks.snoozed")
        let digest = item(id: digestID, sourceID: "github.notifications", title: "Build report")
        let mention = item(id: mentionID, sourceID: "linear.feed", title: "Tagged you")

        let sections = InboxSectionBuilder.sections(from: [noDate, snoozed, digest, mention])
        #expect(sections.count == 4)

        let bezDaty = sections.first { $0.title == "NO DATE" }
        let uspione = sections.first { $0.title == "SNOOZED" }
        let email = sections.first { $0.title == "E-MAIL" }
        let wzmianki = sections.first { $0.title == "MENTIONS" }

        #expect(bezDaty?.items.map(\.id) == [ndID])
        #expect(uspione?.items.map(\.id) == [snoozedID])
        #expect(email?.items.map(\.id) == [digestID])
        #expect(wzmianki?.items.map(\.id) == [mentionID])
    }

    // MARK: - Intra-section ordering

    @Test("items within a bucket preserve input order (stable filter)")
    func intraSectionOrderPreserved() {
        let firstID = UUID()
        let secondID = UUID()
        let first = item(id: firstID, sourceID: "tasks.no-date", title: "First")
        let second = item(id: secondID, sourceID: "tasks.no-date", title: "Second")

        let sections = InboxSectionBuilder.sections(from: [first, second])
        let bezDaty = sections.first { $0.title == "NO DATE" }

        // Guards against an accidental rewrite to sort/dedup: a non-stable
        // bucketing would still pass every other test but break this.
        #expect(bezDaty?.items.map(\.id) == [firstID, secondID])
    }
}
#endif
