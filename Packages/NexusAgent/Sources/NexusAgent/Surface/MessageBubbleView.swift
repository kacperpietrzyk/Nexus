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
// Liquid re-skin: inks/fonts/radii now come from the DS token namespace
// (NexusUI/Tokens/LiquidTokens.swift). The user's turn sits on a quiet
// glass-selected wash; the agent's turn stays flat on the shell glass with
// its tool cluster on a soft glass tier. Tool names keep a monospaced face
// (code identifiers, not prose).
//
// Task 5: when `block.proposal` is non-nil (agent block only), a
// `ProposalConfirmCard` is rendered below the text body. Accept/reject are
// routed through `AgentChatViewModel` via the injected `onAccept`/`onReject`
// closures — the view itself stays stateless.

struct MessageBubbleView: View {
    let block: AgentMessageBlock
    /// Called when the user taps "Apply" on a confirm card.
    var onAcceptProposal: ((UUID) async -> Void)?
    /// Called when the user taps "Discard" on a confirm card.
    var onRejectProposal: ((UUID) -> Void)?

    init(
        block: AgentMessageBlock,
        onAcceptProposal: ((UUID) async -> Void)? = nil,
        onRejectProposal: ((UUID) -> Void)? = nil
    ) {
        self.block = block
        self.onAcceptProposal = onAcceptProposal
        self.onRejectProposal = onRejectProposal
    }

    var body: some View {
        switch block.kind {
        case .user:
            userBlock
                .contextMenu { messageContextMenu }
        case .agent:
            agentBlock
                .contextMenu { messageContextMenu }
        }
    }

    @ViewBuilder
    private var messageContextMenu: some View {
        Button {
            PasteboardCopy.string(markdownRepresentation)
        } label: {
            Label("Copy as Markdown", systemImage: "doc.plaintext")
        }
    }

    /// Canonical Markdown for this message block. User messages use a plain
    /// `> quote` block; agent messages use a heading + body. Tool rows are
    /// appended as a bullet list so the export is informative.
    private var markdownRepresentation: String {
        switch block.kind {
        case .user:
            let text = AgentOCRMarker.userFacingText(block.text)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return MarkdownExport.entity(title: "You", body: text)
        case .agent:
            var meta: [String] = []
            if block.redacted { meta.append("summarised") }
            for tool in block.tools {
                meta.append("tool: \(tool.name)")
            }
            return MarkdownExport.entity(
                title: "Nexus",
                body: block.text.trimmingCharacters(in: .whitespacesAndNewlines),
                metadata: meta
            )
        }
    }

    // The user's turn sits on a quiet glass-selected wash so the
    // conversation alternation is scannable at a glance (the agent's turns
    // stay flat on the shell glass — the calmer of the two).
    private var userBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(block.eyebrow)
                .font(DS.FontToken.caption)
                .tracking(1.4)
                .textCase(.uppercase)
                .foregroundStyle(DS.ColorToken.textMuted)
            // LabKit Phase1l#4 interim: strip the prepended OCR/attachment
            // markers so the user's own bubble shows what they typed (the
            // markers stay in persisted `content` for multi-turn context).
            Text(AgentOCRMarker.userFacingText(block.text))
                .font(DS.FontToken.body)
                .foregroundStyle(DS.ColorToken.textSecondary)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .padding(.horizontal, DS.Space.m)
        .padding(.vertical, DS.Space.s + 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            DS.ColorToken.glassSelected,
            in: RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous)
                .strokeBorder(DS.ColorToken.strokeHairline, lineWidth: 1)
        )
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
                    .font(DS.FontToken.caption)
                    .tracking(1.4)
                    .textCase(.uppercase)
                    .foregroundStyle(DS.ColorToken.accentPrimary.opacity(0.85))

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
                    .font(DS.FontToken.body)
                    .foregroundStyle(DS.ColorToken.textPrimary)
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
                // Tool-call group gets its own tier so it reads as a distinct
                // cluster against the flat message body: soft glass under
                // selected-glass rows (clean two-tier nest), faint hairline.
                .padding(DS.Space.s)
                .background(
                    DS.ColorToken.glassSoft,
                    in: RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous)
                        .strokeBorder(DS.ColorToken.strokeHairline, lineWidth: 1)
                }
            }

            if let proposal = block.proposal {
                proposalCard(for: proposal)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    @MainActor
    private func proposalCard(for proposal: Proposal) -> some View {
        let messageID = block.id
        let cardModel = ProposalConfirmCardModel(
            title: "Proposed changes",
            rationale: proposal.rationale,
            previews: proposal.previews.map(\.summary),
            onAccept: { [onAcceptProposal] in
                await onAcceptProposal?(messageID)
            },
            onReject: { [onRejectProposal] in
                onRejectProposal?(messageID)
            }
        )
        return ProposalConfirmCard(model: cardModel)
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
                .foregroundStyle(DS.ColorToken.textMuted)
            Text(tool.name)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(DS.ColorToken.textSecondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            DS.ColorToken.glassSelected,
            in: RoundedRectangle(cornerRadius: DS.Radius.xs, style: .continuous)
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
