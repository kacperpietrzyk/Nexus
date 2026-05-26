import NexusCore
import NexusUI
import SwiftUI

#if os(macOS)
import AppKit
#elseif canImport(UIKit) && !os(watchOS)
import UIKit
#endif

public struct MeetingCard: View {
    public let event: CalendarEvent
    public let isCurrent: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(event: CalendarEvent, isCurrent: Bool = false) {
        self.event = event
        self.isCurrent = isCurrent
    }

    public var body: some View {
        NexusCard(.elev1, padding: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Self.range(event))
                        .font(NexusType.mono)
                        .foregroundStyle(NexusColor.Text.tertiary)

                    if let location = event.location.nilIfEmpty {
                        Text(location)
                            .font(NexusType.caption)
                            .foregroundStyle(NexusColor.Text.muted)
                            .lineLimit(1)
                    }
                }
                .frame(minWidth: 80, alignment: .leading)

                Rectangle()
                    .fill(NexusColor.Line.hairline)
                    .frame(width: 1, height: 22)

                VStack(alignment: .leading, spacing: 4) {
                    Text(event.title)
                        .font(NexusType.body)
                        .foregroundStyle(NexusColor.Text.primary)
                        .lineLimit(1)

                    attendeeRow
                }

                Spacer(minLength: 8)

                if isCurrent {
                    TimelineView(.animation(paused: reduceMotion)) { tl in
                        let phase =
                            tl.date.timeIntervalSinceReferenceDate
                            / NexusMotion.breathePeriod * 2 * .pi
                        let opacity = Self.liveDotOpacity(reduceMotion: reduceMotion, phase: phase)
                        Circle()
                            .fill(NexusColor.Text.primary)
                            .frame(width: 8, height: 8)
                            .opacity(opacity)
                    }
                }

                NexusButton(variant: .outline, size: .sm, action: openEvent) {
                    Text("Notes")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .overlay(alignment: .leading) {
            if isCurrent {
                Rectangle()
                    .fill(NexusColor.Text.primary)
                    .frame(width: 2)
                    .clipShape(RoundedRectangle(cornerRadius: NexusRadius.r3, style: .continuous))
            }
        }
        .accessibilityLabel(accessibilityLabel)
    }

    @ViewBuilder
    private var attendeeRow: some View {
        if !event.attendees.isEmpty {
            HStack(spacing: -4) {
                ForEach(Array(event.attendees.prefix(3).enumerated()), id: \.offset) { _, attendee in
                    Text(Self.initials(for: attendee))
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(NexusColor.Text.primary)
                        .frame(width: 20, height: 20)
                        .background(NexusColor.Background.control, in: Circle())
                        .overlay {
                            Circle().strokeBorder(NexusColor.Line.hairline, lineWidth: 1)
                        }
                }

                if event.attendees.count > 3 {
                    Text("+\(event.attendees.count - 3)")
                        .font(NexusType.caption)
                        .foregroundStyle(NexusColor.Text.tertiary)
                        .padding(.leading, 8)
                }
            }
        }
    }

    /// Returns the live-dot opacity for the "happening now" indicator.
    /// Under Reduce Motion the dot renders at full strength (1.0) — a clear,
    /// solid signal — instead of a frozen arbitrary value derived from the
    /// paused animation clock.
    static func liveDotOpacity(reduceMotion: Bool, phase: Double) -> Double {
        reduceMotion ? 1.0 : 0.4 + 0.6 * (0.5 + 0.5 * sin(phase))
    }

    private var accessibilityLabel: String {
        "Meeting \(event.title), \(Self.range(event))"
    }

    private static func range(_ event: CalendarEvent) -> String {
        "\(timeFormatter.string(from: event.start))-\(timeFormatter.string(from: event.end))"
    }

    private static func initials(for attendee: CalendarEvent.Attendee) -> String {
        let source = attendee.name.nilIfEmpty ?? attendee.email.nilIfEmpty ?? "?"
        let parts =
            source
            .split(whereSeparator: { $0 == " " || $0 == "." || $0 == "@" || $0 == "_" || $0 == "-" })
            .prefix(2)
        let value = parts.compactMap(\.first).map(String.init).joined()
        return value.isEmpty ? "?" : value.uppercased()
    }

    private func open(_ event: CalendarEvent) {
        #if os(macOS)
        if let url = event.urlForJoin {
            NSWorkspace.shared.open(url)
        } else if let calendarURL = URL(string: "ical://") {
            NSWorkspace.shared.open(calendarURL)
        }
        #elseif canImport(UIKit) && !os(watchOS)
        if let url = event.urlForJoin {
            UIApplication.shared.open(url)
        } else if let calendarURL = URL(string: "calshow:\(event.start.timeIntervalSinceReferenceDate)") {
            UIApplication.shared.open(calendarURL)
        }
        #else
        _ = event
        #endif
    }

    private func openEvent() {
        open(event)
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}

extension Optional where Wrapped == String {
    fileprivate var nilIfEmpty: String? {
        guard let self, !self.isEmpty else { return nil }
        return self
    }
}
