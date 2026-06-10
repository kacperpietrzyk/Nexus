import NexusUI
import SwiftUI

/// The Agent fresh-thread invitation surface.
///
/// MP-3.2 slice 2 rebuilt this 1:1 to the accepted Agent oracle's `isFresh`
/// branch (`Packages/NexusUI/Sources/NexusUI/Lab/AgentChatPreview.swift` —
/// the visual source of truth, never imported), which composes `LabKit`'s
/// `LabEmptyState(tone: .invitation)` + four `LabExampleChip`s. Re-toned
/// through the MP-2.2 §2 achromatic LabPalette→NexusColor map:
/// `ink→Text.primary`, `read→Text.secondary`, `soft→Text.tertiary`,
/// `faint→Text.muted`, `dim→Text.disabled`. Zero hue (the prior chromatic
/// `NexusColor.Accent.*` 56×56 circle is exactly what this slice burns
/// down). Not a primitive — package-internal view restyled in place (§11).
///
/// The §9 invitation idiom (verbatim, verified vs `LabKit.swift:451-498`):
/// outer `VStack(spacing: 0)` of glyph/title/subtitle/extra, capped at
/// `maxWidth: 380`, then `maxWidth/maxHeight: .infinity`. The invitation
/// glyph is a bare `sparkles` (no circle, no background). The example
/// chips mirror `LabExampleChip` (`LabKit.swift:522-534`); their oracle
/// glass `labGlass(Capsule(), elevated: false)` maps to
/// `Background.control` fill + `Line.hairline` stroke — flat Linear idiom,
/// replacing the prior `.nexusGlass(.regular, in: Capsule())` glass call.
public struct AgentEmptyStateView: View {
    public typealias OnPick = (String) -> Void

    private let onPick: OnPick

    public init(onPick: @escaping OnPick) {
        self.onPick = onPick
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Invitation tone glyph: bare `sparkles`, NO circle, NO
            // background (oracle `LabEmptyState.glyphView` `.invitation`).
            Image(systemName: "sparkles")
                .font(.system(size: 21))
                .foregroundStyle(DS.ColorToken.textTertiary)
                .frame(height: 38)
                .padding(.bottom, DS.Space.l)
                .accessibilityHidden(true)

            Text("Ask Nexus")
                .font(DS.FontToken.title)
                .foregroundStyle(DS.ColorToken.textPrimary)
                .multilineTextAlignment(.center)

            Text(
                "Works on your tasks, notes, meetings, "
                    + "and calendar — locally, with undo for every action."
            )
            .font(DS.FontToken.body)
            .foregroundStyle(DS.ColorToken.textTertiary)
            .multilineTextAlignment(.center)
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, DS.Space.xs)

            VStack(spacing: DS.Space.s) {
                ForEach(Self.samples, id: \.self) { sample in
                    ExamplePromptChip(text: sample) { onPick(sample) }
                }
            }
            .padding(.top, DS.Space.xl)
        }
        .frame(maxWidth: 380)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    nonisolated private static let samples = [
        "What's most urgent today?",
        "Move the rest of today to tomorrow",
        "Summarise the Design crit meeting",
        "What did Codex change since this morning?",
    ]
}

/// One example-prompt chip — a Liquid glass capsule. The Lab-era chip was
/// non-interactive; this stays a `Button` wired to the EXISTING
/// `viewModel.createThread(title:)` (the adjudicated M1-class keep — an
/// interactive affordance over backend that already exists, zero new
/// behaviour).
private struct ExamplePromptChip: View {
    let text: String
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: "arrow.turn.down.left")
                    .font(.system(size: 9))
                    .foregroundStyle(DS.ColorToken.textMuted)
                Text(text)
                    .font(DS.FontToken.metadata)
                    .foregroundStyle(hovering ? DS.ColorToken.textPrimary : DS.ColorToken.textSecondary)
            }
            .padding(.horizontal, DS.Space.m)
            .padding(.vertical, 7)
            .background(
                hovering ? DS.ColorToken.glassSelected : DS.ColorToken.glassSoft,
                in: Capsule()
            )
            .overlay(
                Capsule().strokeBorder(
                    hovering ? DS.ColorToken.strokeDefault : DS.ColorToken.strokeHairline,
                    lineWidth: 1
                )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(text)
        #if os(macOS)
        .onHover { value in
            withAnimation(DS.Motion.hover) { hovering = value }
        }
        #endif
    }
}
