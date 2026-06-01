import NexusUI
import SwiftUI

// MP-3.2 slice 3 — rebuilt to the Agent oracle's FLAT idiom.
//
// This file is no longer a chat "bubble" (the name is kept to avoid
// cross-file/test churn — it is package-internal and a swap-in-place rename
// would add churn without payoff; §11 proportionate-call). It now renders the
// oracle `Lab/AgentChatPreview.swift` `msg(_:_:)` / `agentMsg(_:tools:)`
// presentation 1:1 through the §2 LabPalette→NexusColor map (zero hue): a flat
// eyebrow + body + (agent only) tool rows — NOT a card/bubble with a fill +
// stroke. The §1b precedent: the oracle ships its own message presentation over
// a non-`TaskItem` model, so this is a faithful rebuild, same class as
// MP-3.1's `InboxRowView` rebuild.
//
// §2 map applied here: ink→`Text.primary` · read→`Text.secondary` ·
// soft→`Text.tertiary` · faint→`Text.muted` · dim→`Text.disabled` ·
// block→`Glass.surface1`.
//
// Fonts: Geist-* → Inter-*, GeistMono-* → IBMPlexMono-* per Linear redesign.
// body-role (14 pt Regular) routes to NexusType.body; sub-scale mono (9/10 pt
// SemiBold) and tool-row mono (10 pt SemiBold) use IBMPlexMono-SemiBold directly
// (NexusType.metaMono is IBMPlexMono-Medium 10 pt — weight differs; preserve).

struct MessageBubbleView: View {
    let block: AgentMessageBlock

    init(block: AgentMessageBlock) {
        self.block = block
    }

    var body: some View {
        switch block.kind {
        case .user:
            userBlock
        case .agent:
            agentBlock
        }
    }

    // Oracle `msg("TY", text)`.
    private var userBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(block.eyebrow)
                .font(Font.custom("IBMPlexMono-SemiBold", size: 9))
                .tracking(2)
                .foregroundStyle(NexusColor.Text.disabled)  // §2 dim
            // LabKit Phase1l#4 interim: strip the prepended OCR/attachment
            // markers so the user's own bubble shows what they typed (the
            // markers stay in persisted `content` for multi-turn context).
            Text(AgentOCRMarker.userFacingText(block.text))
                .font(NexusType.body)
                .foregroundStyle(NexusColor.Text.secondary)  // §2 read
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    // Oracle `agentMsg(text, tools:)`. §10: the undo pill is OMITTED entirely
    // (the oracle's `agentMsg(undo:true)` shows an "Undo" pill +
    // "touched N tasks" — `AgentChatViewModel` exposes NO undo API and the
    // transcript carries no affected-entity count; surfacing it needs new
    // backend/query, §10-forbidden — delta-strip / achievement-pill
    // precedent). The tool-row "detail" string is OMITTED for the same reason
    // (see `toolRow`).
    private var agentBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(block.eyebrow)
                    .font(Font.custom("IBMPlexMono-SemiBold", size: 9))
                    .tracking(2)
                    .foregroundStyle(NexusColor.Text.muted)  // §2 faint

                // Adjudicated-keep (M1-class, same call as the `nowy ⌘⇧A`
                // top-bar keep): `redactedContent` is REAL data and the badge
                // is truthful UX even though the oracle has no such concept.
                // Retoned to `.muted` — both `.info` and `.muted` are
                // hue-free post-MP-1 (`Semantic.info` is grey `0x8C8D96`,
                // identical hex to `Text.tertiary`; the full `Semantic.*`
                // family was burned achromatic in MP-1). `.muted` is chosen
                // because it is the §2-neutral-named tone (clear bg,
                // `Line.hairline` border) whose token semantics align with
                // the rendered output — NOT because `.info` leaks hue.
                if block.redacted {
                    NexusBadge("summarised", tone: .muted)
                }
            }

            if !block.text.isEmpty {
                Text(block.text)
                    .font(NexusType.body)
                    .foregroundStyle(NexusColor.Text.primary)  // §2 ink
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }

            if !block.tools.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    // Oracle (`AgentChatPreview.swift:106`) keys by `.offset`,
                    // NOT name: a turn that calls the same tool twice
                    // (e.g. `tasks.search` with different params) must render
                    // two distinct rows — a name-keyed `ForEach` would
                    // collapse them.
                    ForEach(Array(block.tools.enumerated()), id: \.offset) { _, tool in
                        toolRow(tool)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    // Oracle tool row. §10: the oracle row is
    // `icon · name · "·" · detail · Spacer`; the `"·"` separator `Text` AND
    // the hand-authored `detail` prose ("status:open prio:P1 · 1 wynik") are
    // BOTH OMITTED — `detail` is not faithfully derivable from an arbitrary
    // `JSONValue` result without inventing a summarizer (= backend,
    // §10-forbidden). Honest truncated structure (delta-strip precedent): we
    // do NOT pad a fake empty `Text` or keep the `·` to preserve oracle width.
    private func toolRow(_ tool: AgentToolRow) -> some View {
        HStack(spacing: 8) {
            Image(systemName: tool.icon)
                .font(.system(size: 9))
                .foregroundStyle(NexusColor.Text.muted)  // §2 faint
            Text(tool.name)
                .font(Font.custom("IBMPlexMono-SemiBold", size: 10))
                .foregroundStyle(NexusColor.Text.tertiary)  // §2 soft
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            NexusColor.Background.raised,
            in: RoundedRectangle(cornerRadius: NexusRadius.r1)
        )
    }

    private var accessibilityLabel: String {
        let role = block.kind == .user ? "You" : "Nexus"
        let bodyText =
            block.kind == .user ? AgentOCRMarker.userFacingText(block.text) : block.text
        var label = "\(role). \(bodyText)"
        if block.redacted { label += ". Summarised content" }
        if !block.tools.isEmpty {
            label += ". Tools: " + block.tools.map(\.name).joined(separator: ", ")
        }
        return label
    }
}
