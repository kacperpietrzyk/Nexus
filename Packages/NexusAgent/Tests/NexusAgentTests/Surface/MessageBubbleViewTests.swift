import Foundation
import NexusCore
import Testing

@testable import NexusAgent

// MP-3.2 slice 3 — the §1b testable core: the pure `AgentMessageGrouping`
// derivation + the `AgentToolIcon` map. Precedent: MP-3.1's
// `InboxSectionBuilderTests` / `InboxItemPresentationTests` ("pure derivation
// function + its own test file"). The previous static-helper assertions
// (`MessageBubbleView.accessibilityLabel(for:)` /
// `.shouldShowRedactedBadge(message:)`) were replaced — that API shape did not
// survive the flat-oracle rebuild and preserving it just for two trivial
// assertions would be API ballast.
//
// No `#if os(macOS)` gate: `AgentMessageGrouping` / `AgentToolIcon` /
// `AgentMessage` are platform-neutral (no macOS-only types imported) — mirrors
// MP-3.1's per-file decision based on imports.

@Suite
struct AgentMessageGroupingTests {

    private func toolMessage(name: String, threadID: UUID) -> AgentMessage {
        let transcript = AgentToolTranscript(
            call: AgentToolCallEnvelope(name: name, input: .object([:])),
            result: .object([:]),
            auditLogID: UUID()
        )
        // Encoding a fixed Codable struct cannot realistically fail; `try?`
        // with a sentinel keeps the helper non-throwing without `force_try`.
        // A `Data()` fallback would decode-fail (row skipped) — acceptable as
        // an unreachable safety net, not a masked path.
        let data = (try? JSONEncoder().encode(transcript)) ?? Data()
        return AgentMessage(
            threadID: threadID,
            role: .tool,
            content: "",
            toolCallJSON: data
        )
    }

    @Test func userMessageEmitsUserBlock() {
        let tid = UUID()
        let blocks = AgentMessageGrouping.blocks(
            from: [AgentMessage(threadID: tid, role: .user, content: "hi nexus")],
            isThinking: false
        )

        #expect(blocks.count == 1)
        #expect(blocks[0].kind == .user)
        #expect(blocks[0].eyebrow == "TY")
        #expect(blocks[0].text == "hi nexus")
        #expect(blocks[0].tools.isEmpty)
        #expect(blocks[0].redacted == false)
    }

    @Test func consecutiveToolsBufferIntoFollowingAgentBlock() {
        let tid = UUID()
        let messages: [AgentMessage] = [
            AgentMessage(threadID: tid, role: .user, content: "do it"),
            toolMessage(name: "tasks.search", threadID: tid),
            toolMessage(name: "calendar.read", threadID: tid),
            AgentMessage(threadID: tid, role: .agent, content: "done"),
        ]

        let blocks = AgentMessageGrouping.blocks(from: messages, isThinking: false)

        #expect(blocks.count == 2)
        #expect(blocks[0].kind == .user)
        #expect(blocks[1].kind == .agent)
        #expect(blocks[1].eyebrow == "NEXUS")
        #expect(blocks[1].text == "done")
        #expect(blocks[1].tools.map(\.name) == ["tasks.search", "calendar.read"])
    }

    @Test func duplicateNamedToolsAreBothBuffered() {
        // A turn that calls the same tool twice (realistic: `tasks.search`
        // with different params) must yield TWO rows — the view keys the
        // `ForEach` by offset, not name, so they do not collapse.
        let tid = UUID()
        let messages: [AgentMessage] = [
            toolMessage(name: "tasks.search", threadID: tid),
            toolMessage(name: "tasks.search", threadID: tid),
            AgentMessage(threadID: tid, role: .agent, content: "two searches"),
        ]

        let blocks = AgentMessageGrouping.blocks(from: messages, isThinking: false)

        #expect(blocks.count == 1)
        #expect(blocks[0].tools.count == 2)
        #expect(blocks[0].tools.map(\.name) == ["tasks.search", "tasks.search"])
    }

    @Test func toolBufferClearsBetweenAgentBlocks() {
        let tid = UUID()
        let messages: [AgentMessage] = [
            toolMessage(name: "tasks.search", threadID: tid),
            AgentMessage(threadID: tid, role: .agent, content: "first"),
            toolMessage(name: "calendar.read", threadID: tid),
            AgentMessage(threadID: tid, role: .agent, content: "second"),
        ]

        let blocks = AgentMessageGrouping.blocks(from: messages, isThinking: false)

        #expect(blocks.count == 2)
        #expect(blocks[0].tools.map(\.name) == ["tasks.search"])
        #expect(blocks[1].tools.map(\.name) == ["calendar.read"])
    }

    @Test func systemMessageIsOmittedFromStream() {
        let tid = UUID()
        let messages: [AgentMessage] = [
            AgentMessage(threadID: tid, role: .system, content: "context plumbing"),
            AgentMessage(threadID: tid, role: .user, content: "hello"),
            AgentMessage(threadID: tid, role: .system, content: "more plumbing"),
        ]

        let blocks = AgentMessageGrouping.blocks(from: messages, isThinking: false)

        #expect(blocks.count == 1)
        #expect(blocks[0].kind == .user)
        #expect(blocks[0].text == "hello")
    }

    @Test func trailingToolsSuppressedWhileThinking() {
        let tid = UUID()
        let messages: [AgentMessage] = [
            AgentMessage(threadID: tid, role: .user, content: "go"),
            toolMessage(name: "tasks.update", threadID: tid),
        ]

        let blocks = AgentMessageGrouping.blocks(from: messages, isThinking: true)

        // Only the settled user block; the open buffer is suppressed.
        #expect(blocks.count == 1)
        #expect(blocks[0].kind == .user)
    }

    @Test func trailingToolsEmitEmptyAgentBlockWhenNotThinking() {
        let tid = UUID()
        let messages: [AgentMessage] = [
            AgentMessage(threadID: tid, role: .user, content: "go"),
            toolMessage(name: "tasks.update", threadID: tid),
            toolMessage(name: "tasks.reschedule", threadID: tid),
        ]

        let blocks = AgentMessageGrouping.blocks(from: messages, isThinking: false)

        #expect(blocks.count == 2)
        #expect(blocks[1].kind == .agent)
        #expect(blocks[1].text.isEmpty)
        #expect(blocks[1].tools.map(\.name) == ["tasks.update", "tasks.reschedule"])
    }

    @Test func nilToolCallJSONRowIsSkippedGracefully() {
        let tid = UUID()
        let messages: [AgentMessage] = [
            AgentMessage(threadID: tid, role: .tool, content: "", toolCallJSON: nil),
            AgentMessage(threadID: tid, role: .agent, content: "no tools shown"),
        ]

        let blocks = AgentMessageGrouping.blocks(from: messages, isThinking: false)

        #expect(blocks.count == 1)
        #expect(blocks[0].kind == .agent)
        #expect(blocks[0].tools.isEmpty)
    }

    @Test func garbageToolCallJSONRowIsSkippedGracefully() {
        let tid = UUID()
        let messages: [AgentMessage] = [
            AgentMessage(
                threadID: tid,
                role: .tool,
                content: "",
                toolCallJSON: Data("not json at all".utf8)
            ),
            toolMessage(name: "tasks.search", threadID: tid),
            AgentMessage(threadID: tid, role: .agent, content: "one good tool"),
        ]

        let blocks = AgentMessageGrouping.blocks(from: messages, isThinking: false)

        #expect(blocks.count == 1)
        #expect(blocks[0].tools.map(\.name) == ["tasks.search"])
    }

    @Test func redactedAgentContentMarksBlock() {
        let tid = UUID()
        let messages: [AgentMessage] = [
            AgentMessage(
                threadID: tid,
                role: .agent,
                content: "(redacted)",
                redactedContent: true
            )
        ]

        let blocks = AgentMessageGrouping.blocks(from: messages, isThinking: false)

        #expect(blocks.count == 1)
        #expect(blocks[0].redacted == true)
    }
}

@Suite
struct AgentToolIconTests {
    @Test func tasksFamilyMapsToChecklist() {
        #expect(AgentToolIcon.symbol(for: "tasks.search") == "checklist")
        #expect(AgentToolIcon.symbol(for: "tasks.update") == "checklist")
        #expect(AgentToolIcon.symbol(for: "tasks.reschedule") == "checklist")
    }

    @Test func calendarFamilyMapsToCalendar() {
        #expect(AgentToolIcon.symbol(for: "calendar.read") == "calendar")
    }

    @Test func memoryFamilyMapsToBrain() {
        #expect(AgentToolIcon.symbol(for: "agent.remember") == "brain")
        #expect(AgentToolIcon.symbol(for: "agent.recall") == "brain")
        #expect(AgentToolIcon.symbol(for: "agent.forget") == "brain")
    }

    @Test func searchFamilyMapsToMagnifyingglass() {
        #expect(AgentToolIcon.symbol(for: "agent.search_semantic") == "magnifyingglass")
        #expect(AgentToolIcon.symbol(for: "search.notes") == "magnifyingglass")
    }

    @Test func linkFamilyMapsToLink() {
        #expect(AgentToolIcon.symbol(for: "agent.link_items") == "link")
    }

    @Test func otherAgentToolsMapToSparkles() {
        #expect(AgentToolIcon.symbol(for: "agent.daily_summary") == "sparkles")
    }

    @Test func unknownToolFallsBackToGenericGlyph() {
        #expect(AgentToolIcon.symbol(for: "weird.unknown.tool") == "wrench.and.screwdriver")
        #expect(AgentToolIcon.symbol(for: "") == "wrench.and.screwdriver")
    }
}
