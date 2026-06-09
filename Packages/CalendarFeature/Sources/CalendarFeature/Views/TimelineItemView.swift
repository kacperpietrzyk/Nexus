import NexusCore
import NexusUI
import SwiftUI

/// A single placed item on the hour axis (spec §7 / §9). Proposed blocks read as
/// dashed/dimmed (a suggestion), accepted blocks as a solid lime-edged surface,
/// and external events as a neutral raised surface — three visually distinct
/// treatments per spec §7.
struct TimelineItemView: View {
    let positioned: PositionedTimelineItem
    let onAccept: () -> Void
    let onReject: () -> Void
    let onTap: () -> Void

    private var item: TimelineItem { positioned.item }

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 6) {
                accentBar
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(NexusType.bodySmall)
                        .foregroundStyle(NexusColor.Text.primary)
                        .lineLimit(positioned.height > 34 ? 2 : 1)
                    if positioned.height > 40 {
                        Text(timeRange)
                            .font(NexusType.metaMono)
                            .foregroundStyle(NexusColor.Text.tertiary)
                    }
                }
                Spacer(minLength: 4)
                if item.kind == .proposedBlock {
                    proposalControls
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, minHeight: positioned.height, alignment: .topLeading)
            .background(background)
            .overlay(border)
            .clipShape(RoundedRectangle(cornerRadius: NexusRadius.r2, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accentBar: some View {
        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
            .fill(accentColor)
            .frame(width: 3)
    }

    @ViewBuilder
    private var proposalControls: some View {
        HStack(spacing: 4) {
            Button(action: onAccept) {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(NexusColor.Accent.limeInk)
                    .frame(width: 18, height: 18)
                    .background(NexusColor.Accent.lime, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Accept block \(item.title)")

            Button(action: onReject) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(NexusColor.Text.secondary)
                    .frame(width: 18, height: 18)
                    .background(NexusColor.Background.control, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Reject block \(item.title)")
        }
    }

    /// The event's desaturated calendar color, or nil when it has no/invalid hex.
    /// Lime (accepted) and the neutral tint (proposed) bypass this.
    private var calendarTint: Color? {
        guard item.kind == .event else { return nil }
        return item.colorHex.flatMap { Color(calendarHexDesaturated: $0) }
    }

    private var accentColor: Color {
        switch item.kind {
        case .event:
            return calendarTint ?? NexusColor.Text.tertiary
        case .proposedBlock:
            return NexusColor.Text.tertiary
        case .acceptedBlock:
            return NexusColor.Accent.lime
        }
    }

    /// Events no longer fight the dark palette with a full-saturation 3px bar:
    /// the whole card surface is tinted with the desaturated calendar color at
    /// low opacity over `Background.raised`, keeping events distinguishable by
    /// calendar while lime stays the only fully-saturated accent. Blocks keep
    /// their neutral surfaces.
    @ViewBuilder
    private var background: some View {
        let shape = RoundedRectangle(cornerRadius: NexusRadius.r2, style: .continuous)
        switch item.kind {
        case .event:
            ZStack {
                NexusColor.Background.raised
                if let tint = calendarTint {
                    tint.opacity(0.16)
                }
            }
            .clipShape(shape)
        case .proposedBlock:
            NexusColor.Background.panel.opacity(0.7)
        case .acceptedBlock:
            NexusColor.Background.control
        }
    }

    @ViewBuilder
    private var border: some View {
        let shape = RoundedRectangle(cornerRadius: NexusRadius.r2, style: .continuous)
        switch item.kind {
        case .proposedBlock:
            shape.strokeBorder(
                NexusColor.Line.strong,
                style: StrokeStyle(lineWidth: 1, dash: [4, 3])
            )
        case .acceptedBlock:
            shape.strokeBorder(NexusColor.Accent.lime.opacity(0.5), lineWidth: 1)
        case .event:
            // A faint tint-tinged rim keeps the card edge legible without the
            // hard saturated border the raw color produced.
            shape.strokeBorder((calendarTint ?? NexusColor.Line.hairline).opacity(0.4), lineWidth: 1)
        }
    }

    private var timeRange: String {
        "\(Self.timeFormatter.string(from: item.start))–\(Self.timeFormatter.string(from: item.end))"
    }

    private var accessibilityLabel: String {
        let kind: String
        switch item.kind {
        case .event: kind = "Event"
        case .proposedBlock: kind = "Proposed block"
        case .acceptedBlock: kind = "Scheduled block"
        }
        return "\(kind): \(item.title), \(timeRange)"
    }

    static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}
