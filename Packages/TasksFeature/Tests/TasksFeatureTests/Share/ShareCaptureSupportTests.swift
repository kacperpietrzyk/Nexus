import Foundation
import NexusCore
import Testing

@testable import TasksFeature

@Suite("Share capture support")
struct ShareCaptureSupportTests {
    @Test("loaded item text supports URL, string, data, and attributed string")
    func loadedItemTextSupportsSharePayloads() {
        #expect(ShareInputTextExtractor.text(fromLoadedItem: URL(string: "https://example.com/t")!) == "https://example.com/t")
        #expect(ShareInputTextExtractor.text(fromLoadedItem: "  plain task  ") == "plain task")
        #expect(ShareInputTextExtractor.text(fromLoadedItem: Data("from data".utf8)) == "from data")
        #expect(ShareInputTextExtractor.text(fromLoadedItem: NSAttributedString(string: "  rich text  ")) == "rich text")
    }

    @Test("joined text trims blank fragments and removes duplicates")
    func joinedTextTrimsAndDeduplicatesFragments() {
        let text = ShareInputTextExtractor.joinedText(from: [
            "  Buy milk  ",
            "",
            "https://example.com",
            "Buy milk",
        ])

        #expect(text == "Buy milk\nhttps://example.com")
    }

    @MainActor
    @Test("task construction preserves parsed metadata")
    func taskConstructionPreservesParsedMetadata() throws {
        let dueAt = Date(timeIntervalSince1970: 1_800_000_000)
        let startAt = Date(timeIntervalSince1970: 1_800_003_600)
        let endAt = Date(timeIntervalSince1970: 1_800_007_200)
        let deadlineAt = Date(timeIntervalSince1970: 1_800_086_400)
        let result = ParseResult(
            title: "  Submit report  ",
            dueAt: dueAt,
            startAt: startAt,
            endAt: endAt,
            deadlineAt: deadlineAt,
            priority: .high,
            tags: ["work", "finance"],
            recurrence: "FREQ=WEEKLY",
            confidence: 0.95
        )

        let task = try ShareTaskBuilder.task(from: result)

        #expect(task.title == "Submit report")
        #expect(task.dueAt == dueAt)
        #expect(task.startAt == startAt)
        #expect(task.endAt == endAt)
        #expect(task.deadlineAt == deadlineAt)
        #expect(task.priority == .high)
        #expect(task.tags == ["work", "finance"])
        #expect(task.recurrenceRule == "FREQ=WEEKLY")
    }

    @MainActor
    @Test("task construction rejects empty titles")
    func taskConstructionRejectsEmptyTitles() {
        #expect(throws: ShareTaskBuilderError.emptyTitle) {
            _ = try ShareTaskBuilder.task(from: ParseResult(title: "   "))
        }
    }

    @MainActor
    @Test("task construction resolves the project token when a resolver is supplied")
    func taskConstructionResolvesProject() throws {
        let nexusID = UUID()
        let result = ParseResult(title: "Ship build", projectToken: "Nexus", confidence: 0.95)

        let resolved = try ShareTaskBuilder.task(from: result) { token in
            token == "Nexus" ? nexusID : nil
        }
        #expect(resolved.projectID == nexusID)

        let unresolved = try ShareTaskBuilder.task(from: result) { _ in nil }
        #expect(unresolved.projectID == nil)

        let withoutResolver = try ShareTaskBuilder.task(from: result)
        #expect(withoutResolver.projectID == nil)
    }
}
