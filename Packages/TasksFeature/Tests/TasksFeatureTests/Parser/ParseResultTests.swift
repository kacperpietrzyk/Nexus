import Foundation
import NexusCore
import Testing

@testable import TasksFeature

@Suite("ParseResult")
struct ParseResultTests {
    @Test("empty result has empty title and zero confidence")
    func emptyDefaults() {
        let result = ParseResult.empty(title: "")
        #expect(result.title.isEmpty)
        #expect(result.dueAt == nil)
        #expect(result.startAt == nil)
        #expect(result.deadlineAt == nil)
        #expect(result.priority == nil)
        #expect(result.tags.isEmpty)
        #expect(result.recurrence == nil)
        #expect(result.unresolvedFragments.isEmpty)
        #expect(result.confidence == 0.0)
    }

    @Test("equality compares all fields")
    func equality() {
        let a = ParseResult(
            title: "Buy milk",
            dueAt: Date(timeIntervalSince1970: 1_700_000_000),
            startAt: nil,
            deadlineAt: Date(timeIntervalSince1970: 1_800_000_000),
            priority: .medium,
            tags: ["shopping"],
            recurrence: nil,
            unresolvedFragments: [],
            confidence: 0.95
        )
        let b = ParseResult(
            title: "Buy milk",
            dueAt: Date(timeIntervalSince1970: 1_700_000_000),
            startAt: nil,
            deadlineAt: Date(timeIntervalSince1970: 1_800_000_000),
            priority: .medium,
            tags: ["shopping"],
            recurrence: nil,
            unresolvedFragments: [],
            confidence: 0.95
        )
        #expect(a == b)
    }
}
