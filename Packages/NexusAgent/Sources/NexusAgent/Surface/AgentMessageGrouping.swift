import Foundation
import NexusCore

// MP-3.2 slice 3 — pure presentation derivation for the Agent message stream.
//
// The §1b precedent (same class as MP-3.1's `InboxSectionBuilder`): the Agent
// oracle (`Lab/AgentChatPreview.swift` `msg(_:_:)` / `agentMsg(_:tools:undo:)`,
// read-only, never imported) ships its OWN flat eyebrow+text message idiom over
// a NON-`TaskItem` model (`AgentMessage` has no status/project — reusing
// `TaskRowView` per §4 is type-impossible). So we rebuild THAT oracle
// presentation here, achromatic, as a pure function + typed result — NOT a §4
// violation.
//
// §11: UI-only derivation over the ALREADY-LOADED `messages` array
// (`AgentChatViewModel.messages` from `messageStore.slidingWindow(...)`); NO new
// store query, NO behavior. The grouping/decoding is the testable core.

// MARK: - Typed result

/// One rendered tool row inside an agent block. The oracle row is
/// `icon · name · "·" · detail · Spacer`; the `"·"` separator AND the `detail`
/// prose are §10-OMITTED (see `AgentMessageGrouping`), so the model carries
/// only the two faithfully-derivable fields.
struct AgentToolRow: Equatable {
    /// SF Symbol for the leading glyph (pure `toolName` → symbol map).
    let icon: String
    /// The tool's fully-qualified name (e.g. `tasks.search`).
    let name: String
}

/// One settled block in the stream. The oracle has exactly two idioms —
/// `msg("TY", …)` (user) and `agentMsg(…, tools:)` (agent) — so the block kind
/// is binary; tool rows only ever attach to an agent block.
struct AgentMessageBlock: Identifiable, Equatable {
    enum Kind: Equatable {
        case user
        case agent
    }

    let id: UUID
    let kind: Kind
    /// `"TY"` for user, `"NEXUS"` for agent (oracle eyebrows).
    let eyebrow: String
    let text: String
    /// Always empty for `.user`; the buffered tool rows for `.agent`.
    let tools: [AgentToolRow]
    /// Real `AgentMessage.redactedContent` — drives the adjudicated-keep
    /// "summarised" badge (see `AgentMessageStreamView`). Always `false` for
    /// `.user`.
    let redacted: Bool
}

// MARK: - Per-tool SF-symbol map

enum AgentToolIcon {
    /// Pure `toolName` → SF Symbol. Precedent: MP-3.1's
    /// `InboxItem.nexusInboxSourceIcon` — a pure presentation map over an
    /// existing field (§10/§11-OK, no schema/query). Matched by name PREFIX so
    /// the whole `tasks.*` / `calendar.*` / `agent.*` families resolve without
    /// enumerating every tool; an unknown name falls back to a neutral
    /// "generic tool" glyph (never a fake-specific symbol).
    private static let memoryNames: Set<String> = [
        "agent.remember", "agent.recall", "agent.forget",
    ]

    static func symbol(for toolName: String) -> String {
        let name = toolName.lowercased()
        let isMemory =
            name.hasPrefix("agent.memory") || name.hasPrefix("memory.")
            || memoryNames.contains(name)
        let isSearch =
            name.hasPrefix("agent.search") || name.hasPrefix("search.")
            || name.contains("search")
        if name.hasPrefix("tasks.") { return "checklist" }
        if name.hasPrefix("calendar.") { return "calendar" }
        if isMemory { return "brain" }
        if isSearch { return "magnifyingglass" }
        if name.hasPrefix("agent.link") || name.hasPrefix("link") { return "link" }
        if name.hasPrefix("agent.") { return "sparkles" }
        // Generic-tool fallback: honest "some tool ran" glyph, never a
        // fabricated domain-specific symbol.
        return "wrench.and.screwdriver"
    }
}

// MARK: - Grouping (the §1b core)

enum AgentMessageGrouping {
    /// Walk the already-loaded `messages` (chronological — same order
    /// `slidingWindow` returns) and derive the oracle's flat block stream.
    ///
    /// Algorithm:
    /// - `.user` → emit a user block (`eyebrow:"TY"`, `text: content`).
    /// - `.tool` → decode `toolCallJSON` (`AgentToolTranscript`); buffer a tool
    ///   row `(name, icon)`. **§10-class real-data decision:** if
    ///   `toolCallJSON` is `nil` or fails to decode (malformed/legacy `.tool`
    ///   row) the row is skipped gracefully — no crash, no fake row. The Lab
    ///   never modelled malformed transcripts.
    /// - `.agent` → emit an agent block carrying the tool rows buffered since
    ///   the last emitted block, then clear the buffer.
    /// - `.system` → **§10-class omission:** the oracle has NO system idiom;
    ///   system rows are context-plumbing, not user-facing, so they are
    ///   omitted from the visual stream entirely (never an invented system
    ///   bubble).
    /// - **Trailing un-closed `.tool` run** (the runtime appends `.tool` rows
    ///   before the closing `.agent`): **§10-class decisions, two branches —**
    ///   - `isThinking == true`: SUPPRESS the open buffer. The turn is still
    ///     in flight; the existing `AgentInputBar` "Thinking…" affordance
    ///     already signals progress. We do NOT invent a live partial
    ///     `agentMsg` (the Lab modelled only settled turns).
    ///   - `isThinking == false`: a turn that errored/halted AFTER tool calls
    ///     but BEFORE a final `.agent`. Emit a trailing agent block with empty
    ///     `text` carrying those rows so the work isn't invisible (SwiftUI
    ///     collapses `Text("")` to zero height — the rows are the content; no
    ///     placeholder prose is faked).
    static func blocks(
        from messages: [AgentMessage],
        isThinking: Bool
    ) -> [AgentMessageBlock] {
        var result: [AgentMessageBlock] = []
        var buffer: [AgentToolRow] = []

        for message in messages {
            switch message.role {
            case .user:
                result.append(
                    AgentMessageBlock(
                        id: message.id,
                        kind: .user,
                        eyebrow: "TY",
                        text: message.content,
                        tools: [],
                        redacted: false
                    )
                )
            case .tool:
                guard let data = message.toolCallJSON,
                    let transcript = try? JSONDecoder().decode(
                        AgentToolTranscript.self,
                        from: data
                    )
                else {
                    // Malformed / legacy `.tool` row — skip, never crash.
                    continue
                }
                let name = transcript.call.name
                buffer.append(
                    AgentToolRow(
                        icon: AgentToolIcon.symbol(for: name),
                        name: name
                    )
                )
            case .agent:
                result.append(
                    AgentMessageBlock(
                        id: message.id,
                        kind: .agent,
                        eyebrow: "NEXUS",
                        text: message.content,
                        tools: buffer,
                        redacted: message.redactedContent
                    )
                )
                buffer.removeAll(keepingCapacity: true)
            case .system:
                // §10-class omission: no oracle system idiom.
                continue
            }
        }

        // Trailing un-closed `.tool` run. The synthetic block's `id` is
        // derived from the last source message (NOT a fresh `UUID()`) so the
        // function is genuinely pure/referentially-transparent — its identity
        // is stable across `body` re-evaluations.
        if !buffer.isEmpty && !isThinking {
            result.append(
                AgentMessageBlock(
                    id: messages.last?.id ?? UUID(),
                    kind: .agent,
                    eyebrow: "NEXUS",
                    text: "",
                    tools: buffer,
                    redacted: false
                )
            )
        }
        // (isThinking == true → buffer suppressed by falling through.)

        return result
    }
}
