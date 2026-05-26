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
/// `.nexusGlass(.regular, in: Capsule())` — the same labGlass→nexusGlass
/// convention the §1a pinned-capsule and prior MP-3.x slices use.
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
                .foregroundStyle(NexusColor.Text.tertiary)
                .frame(height: 38)
                .padding(.bottom, 18)
                .accessibilityHidden(true)

            Text("Zapytaj Nexusa")
                .font(Font.custom("Geist-SemiBold", size: 17))
                .foregroundStyle(NexusColor.Text.secondary)
                .multilineTextAlignment(.center)

            Text(
                "Pracuje na Twoich zadaniach, notatkach, spotkaniach "
                    + "i kalendarzu — lokalnie, z cofnięciem każdej akcji."
            )
            .font(Font.custom("Geist-Regular", size: 12.5))
            .foregroundStyle(NexusColor.Text.muted)
            .multilineTextAlignment(.center)
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 6)

            VStack(spacing: 8) {
                ForEach(Self.samples, id: \.self) { sample in
                    exampleChip(sample)
                }
            }
            .padding(.top, 20)
        }
        .frame(maxWidth: 380)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// One example-prompt chip — structural mirror of the oracle's
    /// `LabExampleChip` (`LabKit.swift:522-534`). The Lab chip is
    /// non-interactive; here it stays a `Button` wired to the EXISTING
    /// `viewModel.createThread(title:)` (a deliberate oracle deviation, the
    /// adjudicated M1-class keep — an interactive affordance over backend
    /// that already exists, zero new behaviour; recorded in counts §12 at
    /// MP-3.2 closeout).
    private func exampleChip(_ text: String) -> some View {
        Button {
            onPick(text)
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "arrow.turn.down.left")
                    .font(.system(size: 9))
                    .foregroundStyle(NexusColor.Text.disabled)
                Text(text)
                    .font(Font.custom("Geist-Regular", size: 12))
                    .foregroundStyle(NexusColor.Text.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .nexusGlass(.regular, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(text)
    }

    nonisolated private static let samples = [
        "Co dziś jest najpilniejsze?",
        "Przenieś resztę „dziś” na jutro",
        "Podsumuj spotkanie „Design crit”",
        "Co zmienił Codex od rana?",
    ]
}
