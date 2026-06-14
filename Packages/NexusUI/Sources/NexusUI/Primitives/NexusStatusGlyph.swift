import SwiftUI

public enum NexusStatus: Equatable, Sendable {
    case todo
    case inProgress(Double)
    case inReview
    case done
    case cancelled
}

public struct NexusStatusGlyph: View {
    public let status: NexusStatus
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(_ status: NexusStatus) {
        self.status = status
    }

    public var body: some View {
        ZStack {
            switch status {
            case .inProgress:
                // Active — the single lime indicator on this glyph (no
                // partial-progress ring; the remaining progress value
                // survives only for accessibility).
                Circle().fill(NexusColor.Accent.lime)
            case .todo:
                // Neutral default — empty Storm Cloud ring.
                Circle().stroke(NexusColor.Text.tertiary, lineWidth: 1.3)
            case .inReview:
                // Waiting — dashed muted ring (stays neutral).
                Circle().stroke(
                    NexusColor.Text.muted,
                    style: StrokeStyle(lineWidth: 1.3, dash: [2, 2.4]))
            case .done:
                // Completed — flat lime disc (matches NexusCheckbox's
                // completed idiom; lime is reserved for exactly this state).
                Circle().fill(NexusColor.Accent.lime)
            case .cancelled:
                // Dismissed — neutral ash ring, never lime.
                Circle().stroke(NexusColor.Text.disabled, lineWidth: 1.3)
            }
            // Checkmark always mounted; scales + bounces in when status flips
            // to .done within withAnimation. Static screens render it
            // invisible (todo/…) or fully shown (done) — zero drift. Drawn in
            // limeInk so it reads as dark ink on the lime done disc.
            Image(systemName: "checkmark").font(.system(size: 6, weight: .bold))
                .foregroundStyle(NexusColor.Accent.limeInk)
                .scaleEffect(isDone ? 1 : 0.1)
                .opacity(isDone ? 1 : 0)
                // Single intentional delight beat on completion; gated so
                // Reduce Motion gets the static scale/opacity swap with no bounce.
                .modifier(DoneBounceEffect(isDone: isDone, reduceMotion: reduceMotion))
        }
        .frame(width: 12, height: 12)
        .animation(NexusMotion.standard, value: status)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityLabel))
        .accessibilityValue(Text(accessibilityValue))
    }

    /// Morph trigger: the always-mounted checkmark is visible/active only for
    /// `.done` (LabKit `LabStatusGlyph` `done` contract). Introspected by the
    /// morph behaviour test.
    internal var isDone: Bool {
        if case .done = status { return true }
        return false
    }

    internal var accessibilityLabel: String {
        switch status {
        case .todo: return "To do"
        case .inProgress: return "In progress"
        case .inReview: return "In review"
        case .done: return "Done"
        case .cancelled: return "Cancelled"
        }
    }

    internal var accessibilityValue: String {
        switch status {
        case .inProgress(let progress):
            let percent = Int((Self.clampedProgress(progress) * 100).rounded())
            return "\(percent) percent"
        // `.inReview` reports no progress value — a fabricated "75 percent"
        // misled every consumer (VoiceOver announced fake progress). Only
        // `.inProgress` carries a real percent.
        case .inReview, .todo, .done, .cancelled:
            return ""
        }
    }

    internal static func clampedProgress(_ progress: Double) -> Double {
        min(max(progress, 0), 1)
    }
}

/// Applies the completion `.bounce` only when Reduce Motion is off. The static
/// scale/opacity swap on the checkmark already carries the state change, so the
/// reduced path loses nothing but the flourish.
private struct DoneBounceEffect: ViewModifier {
    let isDone: Bool
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        if reduceMotion {
            content
        } else {
            content.symbolEffect(.bounce, value: isDone)
        }
    }
}

#Preview {
    HStack(spacing: 16) {
        NexusStatusGlyph(.todo)
        NexusStatusGlyph(.inProgress(0.4))
        NexusStatusGlyph(.inReview)
        NexusStatusGlyph(.done)
        NexusStatusGlyph(.cancelled)
    }
    .padding(40)
    .background(NexusColor.Background.base)
}
