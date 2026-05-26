import Foundation
import NexusCore

// MP-3.2 slice 4 — pure presentation derivation for the Agent rail's
// RECENT TOOLS section.
//
// The §1b precedent (same class as MP-3.1's `InboxSectionBuilder` and slice 3's
// sibling `AgentMessageGrouping`): the Agent oracle
// (`Lab/AgentChatPreview.swift`, read-only, never imported) ships a rail with
// three sections — MEMORY, RECENT TOOLS, SCHEDULES. Per slice 4's
// advisor-locked §10 ruling, only RECENT TOOLS is §10-REACHABLE: it is
// derivable purely from the already-loaded `AgentChatViewModel.messages` (each
// `.tool` row carries a decodable `toolCallJSON` transcript and every
// `AgentMessage` has a `createdAt`). MEMORY + SCHEDULES are §10-OMITTED — no
// memory/schedule read is reachable from this surface and wiring one would be a
// §11 new-query/behavior violation.
//
// §11: UI-only derivation over the ALREADY-LOADED `messages` array (the same
// `messageStore.slidingWindow(...)` slice 3 already decodes); NO new store
// query, NO behavior, NO schema touch. This pure function + typed result is the
// testable core.

// MARK: - Typed result

/// One rendered row in the rail's RECENT TOOLS list.
///
/// The oracle rail row (`Lab/AgentChatPreview.swift` `tool(_:_:_:)`) is
/// `name · detail · Spacer · age` with NO leading glyph (unlike the in-block
/// `agentMsg` tool rows, which DO carry one — that is a different idiom and
/// stays in `AgentMessageGrouping`). Two of those three text fields are
/// faithfully derivable; the `detail` prose (`"3 zadania"`, `"focus set"`) is
/// NOT — reconstructing it from `toolCallJSON` would require re-interpreting
/// per-tool semantics, exactly the §10-OMITTED call slice 3 already made for
/// the in-block tool rows' detail. So the model carries `name` + `age` only;
/// the view renders no fake separator and no empty `detail` placeholder.
struct AgentRecentToolRow: Equatable, Identifiable {
    /// The source `AgentMessage.id` — keeps the derivation referentially
    /// pure (stable identity across `body` re-evaluations, the same
    /// synthetic-id discipline `AgentMessageGrouping` uses).
    let id: UUID
    /// The tool's fully-qualified name (e.g. `tasks.search`).
    let name: String
    /// A deterministic English relative age (`"now"` / `"{n}m"` /
    /// `"{n}h"` / `"{n}d"`).
    let age: String
}

// MARK: - Derivation (the §1b core)

enum AgentRecentTools {
    /// The presentation "recent" window cap. The oracle hard-codes four
    /// sample rows; this is a presentation-only ceiling on how many of the
    /// most-recent tool calls the rail surfaces — NOT a backend-derived
    /// number and NOT a store query parameter.
    static let defaultLimit = 6

    /// Walk the already-loaded `messages`, keep `.tool` rows whose
    /// `toolCallJSON` decodes, and derive the rail's newest-first list.
    ///
    /// Algorithm:
    /// - Keep `.tool` role only (user/agent/system carry no tool call).
    /// - Decode `message.toolCallJSON` to `AgentToolTranscript` with the
    ///   exact graceful pattern slice 3's `AgentMessageGrouping` uses: a
    ///   `nil` or malformed/legacy payload → skip the row, never crash. The
    ///   Lab never modelled malformed transcripts.
    /// - Tool name = `transcript.call.name`.
    /// - Age = `relativeAge(now.timeIntervalSince(message.createdAt))` — a
    ///   pure deterministic bucketed string (see `relativeAge(_:)`).
    /// - Sort the kept rows by `createdAt` DESCENDING, then take the first
    ///   `limit` (newest-first window). Sorting BEFORE the cap is load-bearing
    ///   — capping first would drop the newest rows.
    /// - `id` = the source `AgentMessage.id` so the function stays
    ///   referentially pure / stable across `body` re-evaluations.
    static func rows(
        from messages: [AgentMessage],
        now: Date,
        limit: Int = defaultLimit
    ) -> [AgentRecentToolRow] {
        var decoded: [(message: AgentMessage, name: String)] = []
        for message in messages {
            guard message.role == .tool,
                let data = message.toolCallJSON,
                let transcript = try? JSONDecoder().decode(
                    AgentToolTranscript.self,
                    from: data
                )
            else {
                // Non-tool, or malformed / legacy `.tool` row — skip.
                continue
            }
            decoded.append((message, transcript.call.name))
        }

        return
            decoded
            .sorted { $0.message.createdAt > $1.message.createdAt }
            .prefix(limit)
            .map { entry in
                AgentRecentToolRow(
                    id: entry.message.id,
                    name: entry.name,
                    age: relativeAge(now.timeIntervalSince(entry.message.createdAt))
                )
            }
    }

    /// Pure deterministic relative-age bucket. The oracle only hard-coded two
    /// sampled idiom values (`"teraz"`, `"1m"`); this generalizes them
    /// deterministically over the existing `createdAt` field — presentation
    /// arithmetic, NOT new backend (the same class as MP-3.1's
    /// `nexusInboxSourceIcon` pure map over an existing field).
    ///
    /// Buckets (strict `<`, so an exact boundary rolls up):
    /// - `< 60s` → `"now"`
    /// - `< 3600s` → `"{n}m"`
    /// - `< 86400s` → `"{n}h"`
    /// - else → `"{n}d"`
    ///
    /// Negative intervals (clock skew / future-dated fixtures) are clamped to
    /// `0` BEFORE bucketing so they read `"teraz"` rather than a truncated
    /// negative count.
    static func relativeAge(_ interval: TimeInterval) -> String {
        let seconds = max(0, interval)
        if seconds < 60 { return "now" }
        if seconds < 3600 { return "\(Int(seconds / 60))m" }
        if seconds < 86400 { return "\(Int(seconds / 3600))h" }
        return "\(Int(seconds / 86400))d"
    }
}
