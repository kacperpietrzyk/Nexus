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

    public init(_ status: NexusStatus) {
        self.status = status
    }

    public var body: some View {
        ZStack {
            switch status {
            case .inProgress:
                // LabKit `.now` — solid ink (no partial-progress ring; the
                // remaining progress value survives only for accessibility).
                Circle().fill(NexusColor.Text.primary)
            case .todo:
                Circle().stroke(NexusColor.Text.tertiary, lineWidth: 1.3)
            case .inReview:
                // LabKit `.waiting` — dashed muted ring.
                Circle().stroke(
                    NexusColor.Text.muted,
                    style: StrokeStyle(lineWidth: 1.3, dash: [2, 2.4]))
            case .done, .cancelled:
                Circle().stroke(NexusColor.Text.disabled, lineWidth: 1.3)
            }
            // Checkmark always mounted; scales + bounces in when status flips
            // to .done within withAnimation. Static screens render it
            // invisible (todo/…) or fully shown (done) — zero drift.
            Image(systemName: "checkmark").font(.system(size: 6, weight: .bold))
                .foregroundStyle(NexusColor.Text.disabled)
                .scaleEffect(isDone ? 1 : 0.1)
                .opacity(isDone ? 1 : 0)
                .symbolEffect(.bounce, value: isDone)
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
