import NexusCore
import NexusUI
import SwiftUI

/// Single-day hour axis (spec §9). Renders events + blocks against an hour ruler,
/// with a "now" line. Block accept/reject controls live on the item view.
struct DayGridView: View {
    let day: Date
    let items: [TimelineItem]
    let calendar: Calendar
    let now: Date
    let onAccept: (UUID) -> Void
    let onReject: (UUID) -> Void
    let onTapItem: (TimelineItem) -> Void
    /// Drag-to-adjust a block (spec §7): a vertical drag shifts its start/end and
    /// (for proposed blocks) implicitly accepts it. Receives the new start/end.
    var onAdjust: ((UUID, Date, Date) -> Void)?

    @State private var dragOffsets: [String: CGFloat] = [:]

    private let startHour = 6
    private let endHour = 23
    private let hourHeight: CGFloat = 56
    private let gutter: CGFloat = 52

    private var axisHeight: CGFloat { CGFloat(endHour - startHour) * hourHeight }

    var body: some View {
        ScrollView {
            ZStack(alignment: .topLeading) {
                hourRuler
                nowLine
                placedItems
            }
            .frame(height: axisHeight)
            .padding(.vertical, 8)
        }
    }

    private var hourRuler: some View {
        VStack(spacing: 0) {
            ForEach(startHour..<endHour, id: \.self) { hour in
                HStack(alignment: .top, spacing: 8) {
                    Text(hourLabel(hour))
                        .font(NexusType.caption)
                        .foregroundStyle(NexusColor.Text.muted)
                        .frame(width: gutter - 12, alignment: .trailing)
                    Rectangle()
                        .fill(NexusColor.Line.hairline)
                        .frame(height: 1)
                }
                .frame(height: hourHeight, alignment: .top)
            }
        }
    }

    @ViewBuilder
    private var nowLine: some View {
        if calendar.isDate(now, inSameDayAs: day), let offset = nowOffset {
            HStack(spacing: 0) {
                Circle()
                    .fill(NexusColor.Accent.lime)
                    .frame(width: 6, height: 6)
                Rectangle()
                    .fill(NexusColor.Accent.lime)
                    .frame(height: 1)
            }
            .padding(.leading, gutter - 3)
            .offset(y: offset)
        }
    }

    private var placedItems: some View {
        let positioned = DayTimelineLayout.layout(
            items,
            forDay: day,
            metrics: AxisMetrics(startHour: startHour, endHour: endHour, hourHeight: hourHeight),
            calendar: calendar
        )
        return ForEach(positioned) { placed in
            TimelineItemView(
                positioned: placed,
                onAccept: { if let id = placed.item.blockID { onAccept(id) } },
                onReject: { if let id = placed.item.blockID { onReject(id) } },
                onTap: { onTapItem(placed.item) }
            )
            .frame(height: placed.height)
            .padding(.leading, gutter)
            .padding(.trailing, 8)
            .offset(y: placed.yOffset + (dragOffsets[placed.id] ?? 0))
            .gesture(dragGesture(for: placed))
        }
    }

    /// Vertical drag on a block → shift its start/end by the dragged duration
    /// (snapped to 5-minute steps), then commit via `onAdjust` (spec §7).
    private func dragGesture(for placed: PositionedTimelineItem) -> some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                guard placed.item.blockID != nil, onAdjust != nil else { return }
                dragOffsets[placed.id] = value.translation.height
            }
            .onEnded { value in
                defer { dragOffsets[placed.id] = nil }
                guard let blockID = placed.item.blockID, let onAdjust else { return }
                let secondsPerPoint = 3600.0 / Double(hourHeight)
                let rawSeconds = Double(value.translation.height) * secondsPerPoint
                // Snap to 5-minute steps so adjustments land on tidy boundaries.
                let snapped = (rawSeconds / 300).rounded() * 300
                guard abs(snapped) >= 300 else { return }
                let newStart = placed.item.start.addingTimeInterval(snapped)
                let newEnd = placed.item.end.addingTimeInterval(snapped)
                onAdjust(blockID, newStart, newEnd)
            }
    }

    private var nowOffset: CGFloat? {
        let dayStart = calendar.startOfDay(for: day)
        guard let axisStart = calendar.date(byAdding: .hour, value: startHour, to: dayStart) else { return nil }
        let seconds = now.timeIntervalSince(axisStart)
        guard seconds >= 0, seconds <= Double(endHour - startHour) * 3600 else { return nil }
        return CGFloat(seconds / 3600) * hourHeight
    }

    private func hourLabel(_ hour: Int) -> String {
        String(format: "%02d:00", hour)
    }
}
