import Foundation
import NexusCore
import Testing

@testable import NexusAgent

// MP-3.2 slice 4 — the §1b testable core: the pure `AgentRecentTools`
// derivation (newest-first window over the already-loaded `messages`) + its
// deterministic relative-age bucket. Precedent: slice 3's
// `AgentMessageGroupingTests` and MP-3.1's `InboxSectionBuilderTests` ("pure
// derivation function + its own test file"; no UI snapshot — the function is
// the testable core).
//
// No `#if os(macOS)` gate: `AgentRecentTools` / `AgentMessage` are
// platform-neutral (no macOS-only types) — mirrors the slice-3 file's
// per-import decision.

@Suite
struct AgentRecentToolsTests {

    private func toolMessage(
        name: String,
        threadID: UUID,
        createdAt: Date
    ) -> AgentMessage {
        let transcript = AgentToolTranscript(
            call: AgentToolCallEnvelope(name: name, input: .object([:])),
            result: .object([:]),
            auditLogID: UUID()
        )
        // Encoding a fixed Codable struct cannot realistically fail; `try?`
        // with a `Data()` sentinel keeps the helper non-throwing without
        // `force_try` (the sentinel would decode-fail → row skipped, an
        // unreachable safety net, not a masked path).
        let data = (try? JSONEncoder().encode(transcript)) ?? Data()
        return AgentMessage(
            threadID: threadID,
            createdAt: createdAt,
            role: .tool,
            content: "",
            toolCallJSON: data
        )
    }

    @Test func newestFirstOrdering() {
        let tid = UUID()
        let now = Date(timeIntervalSince1970: 10_000)
        let messages: [AgentMessage] = [
            toolMessage(name: "tasks.search", threadID: tid, createdAt: now.addingTimeInterval(-300)),
            toolMessage(name: "calendar.read", threadID: tid, createdAt: now.addingTimeInterval(-30)),
            toolMessage(name: "tasks.update", threadID: tid, createdAt: now.addingTimeInterval(-120)),
        ]

        let rows = AgentRecentTools.rows(from: messages, now: now)

        #expect(rows.map(\.name) == ["calendar.read", "tasks.update", "tasks.search"])
    }

    @Test func limitCapsToTheNewestRows() {
        let tid = UUID()
        let base = Date(timeIntervalSince1970: 10_000)
        let now = base.addingTimeInterval(600)  // 10 min after the oldest message

        // Ten tool calls supplied in OLDEST-FIRST (ascending createdAt) order.
        // index 0 → base+0 (oldest), index 9 → base+540 (newest).
        // A correct sort-BEFORE-cap picks the 3 newest: indices 9, 8, 7.
        // A buggy cap-BEFORE-sort would prefix([oldest…]) → [t0, t1, t2],
        // then sort descending → [t2, t1, t0] — a distinct wrong result.
        let messages: [AgentMessage] = (0..<10).map { index in
            toolMessage(
                name: "tasks.t\(index)",
                threadID: tid,
                createdAt: base.addingTimeInterval(TimeInterval(60 * index))
            )
        }

        let rows = AgentRecentTools.rows(from: messages, now: now, limit: 3)

        #expect(rows.count == 3)
        // Must be the 3 newest (t9 > t8 > t7), not the 3 oldest.
        #expect(rows.map(\.name) == ["tasks.t9", "tasks.t8", "tasks.t7"])
    }

    @Test func identicalCreatedAtTiesAreHandledGracefully() {
        let tid = UUID()
        let base = Date(timeIntervalSince1970: 10_000)
        let tiedAt = base.addingTimeInterval(-120)

        // Layout: one clearly-newer row (base), two rows sharing an identical
        // createdAt (tiedAt), and one clearly-older row (base - 300s).
        let newer = toolMessage(name: "tasks.newer", threadID: tid, createdAt: base)
        let tieA = toolMessage(name: "tasks.tieA", threadID: tid, createdAt: tiedAt)
        let tieB = toolMessage(name: "tasks.tieB", threadID: tid, createdAt: tiedAt)
        let older = toolMessage(name: "tasks.older", threadID: tid, createdAt: base.addingTimeInterval(-300))

        let rows = AgentRecentTools.rows(from: [older, tieA, tieB, newer], now: base, limit: 6)

        // All 4 rows must be present — ties must not drop rows.
        #expect(rows.count == 4)
        // The clearly-newer row is always first.
        #expect(rows[0].name == "tasks.newer")
        // The clearly-older row is always last.
        #expect(rows[3].name == "tasks.older")
        // Both tied rows appear in positions [1] and [2] (order between them
        // is implementation-defined but deterministic for a given build).
        let tiedNames = Set(rows[1...2].map(\.name))
        #expect(tiedNames == ["tasks.tieA", "tasks.tieB"])
    }

    @Test func defaultLimitIsSix() {
        let tid = UUID()
        let now = Date(timeIntervalSince1970: 10_000)
        let messages: [AgentMessage] = (0..<9).map { index in
            toolMessage(
                name: "tasks.t\(index)",
                threadID: tid,
                createdAt: now.addingTimeInterval(TimeInterval(-60 * index))
            )
        }

        let rows = AgentRecentTools.rows(from: messages, now: now)

        #expect(rows.count == 6)
        #expect(AgentRecentTools.defaultLimit == 6)
    }

    @Test func nonToolRolesAreIgnored() {
        let tid = UUID()
        let now = Date(timeIntervalSince1970: 10_000)
        let messages: [AgentMessage] = [
            AgentMessage(threadID: tid, role: .user, content: "do it"),
            AgentMessage(threadID: tid, role: .agent, content: "done"),
            AgentMessage(threadID: tid, role: .system, content: "context plumbing"),
            toolMessage(name: "tasks.search", threadID: tid, createdAt: now),
        ]

        let rows = AgentRecentTools.rows(from: messages, now: now)

        #expect(rows.count == 1)
        #expect(rows[0].name == "tasks.search")
    }

    @Test func nilToolCallJSONIsSkippedGracefully() {
        let tid = UUID()
        let now = Date(timeIntervalSince1970: 10_000)
        let messages: [AgentMessage] = [
            AgentMessage(threadID: tid, role: .tool, content: "", toolCallJSON: nil),
            toolMessage(name: "tasks.search", threadID: tid, createdAt: now),
        ]

        let rows = AgentRecentTools.rows(from: messages, now: now)

        #expect(rows.count == 1)
        #expect(rows[0].name == "tasks.search")
    }

    @Test func garbageToolCallJSONIsSkippedGracefully() {
        let tid = UUID()
        let now = Date(timeIntervalSince1970: 10_000)
        let messages: [AgentMessage] = [
            AgentMessage(
                threadID: tid,
                role: .tool,
                content: "",
                toolCallJSON: Data("not json at all".utf8)
            ),
            toolMessage(name: "calendar.read", threadID: tid, createdAt: now),
        ]

        let rows = AgentRecentTools.rows(from: messages, now: now)

        #expect(rows.count == 1)
        #expect(rows[0].name == "calendar.read")
    }

    @Test func emptyInputYieldsEmptyResult() {
        let rows = AgentRecentTools.rows(
            from: [],
            now: Date(timeIntervalSince1970: 10_000)
        )
        #expect(rows.isEmpty)
    }

    @Test func rowIdEqualsSourceMessageID() {
        let tid = UUID()
        let now = Date(timeIntervalSince1970: 10_000)
        let message = toolMessage(name: "tasks.search", threadID: tid, createdAt: now)

        let rows = AgentRecentTools.rows(from: [message], now: now)

        #expect(rows.count == 1)
        #expect(rows[0].id == message.id)
        // Stable across re-evaluation (referential purity).
        let again = AgentRecentTools.rows(from: [message], now: now)
        #expect(again[0].id == message.id)
    }

    // MARK: - Relative-age buckets (strict `<`, exact boundary rolls up)

    @Test func relativeAgeNowBucket() {
        #expect(AgentRecentTools.relativeAge(0) == "teraz")
        #expect(AgentRecentTools.relativeAge(59) == "teraz")
    }

    @Test func relativeAgeMinutesBucket() {
        // Exact 60s boundary rolls UP into minutes ("1m", not "teraz").
        #expect(AgentRecentTools.relativeAge(60) == "1m")
        #expect(AgentRecentTools.relativeAge(3599) == "59m")
    }

    @Test func relativeAgeHoursBucket() {
        // Exact 3600s boundary rolls UP into hours.
        #expect(AgentRecentTools.relativeAge(3600) == "1g")
        #expect(AgentRecentTools.relativeAge(86_399) == "23g")
    }

    @Test func relativeAgeDaysBucket() {
        // Exact 86400s boundary rolls UP into days.
        #expect(AgentRecentTools.relativeAge(86_400) == "1d")
        #expect(AgentRecentTools.relativeAge(86_400 * 5) == "5d")
    }

    @Test func relativeAgeNegativeIntervalClampsToNow() {
        // Clock skew / future-dated fixture: clamp BEFORE bucketing so it
        // reads "teraz" rather than a truncated negative count.
        #expect(AgentRecentTools.relativeAge(-30) == "teraz")
        #expect(AgentRecentTools.relativeAge(-10_000) == "teraz")
    }

    @Test func agePropagatesThroughDerivation() {
        let tid = UUID()
        let now = Date(timeIntervalSince1970: 10_000)
        let messages: [AgentMessage] = [
            toolMessage(name: "tasks.search", threadID: tid, createdAt: now.addingTimeInterval(-90)),
            toolMessage(name: "calendar.read", threadID: tid, createdAt: now),
        ]

        let rows = AgentRecentTools.rows(from: messages, now: now)

        #expect(rows[0].age == "teraz")
        #expect(rows[1].age == "1m")
    }
}
