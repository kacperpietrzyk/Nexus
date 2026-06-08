#if canImport(EventKit) && !os(watchOS)
import CoreGraphics
@preconcurrency import EventKit
import Foundation

public final class EventKitCalendarProvider: CalendarEventProviding, @unchecked Sendable {
    public static let shared = EventKitCalendarProvider()

    private let store: EKEventStore
    private let storeBox: EventKitStoreBox
    private let eventQueryQueue = DispatchQueue(label: "com.kacperpietrzyk.Nexus.EventKitCalendarProvider.events")

    public init(store: EKEventStore = EKEventStore()) {
        self.store = store
        self.storeBox = EventKitStoreBox(store: store)
    }

    /// The underlying store, exposed for the `EKEventStoreChanged` observer
    /// registration (`observeStoreChanges`). Mutations go through `onStore`.
    var eventStore: EKEventStore { store }

    /// Run `body` against the store on the serial event queue. Centralizes the
    /// off-main, serialized EventKit access used by the write surface so CRUD ops
    /// never race the read path.
    func onStore<Value: Sendable>(_ body: @escaping @Sendable (EKEventStore) throws -> Value) async throws -> Value {
        try await withCheckedThrowingContinuation { continuation in
            eventQueryQueue.async { [storeBox] in
                do {
                    continuation.resume(returning: try body(storeBox.store))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    public func authorizationStatus() -> CalendarAuthorizationStatus {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .notDetermined:
            return .notDetermined
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        case .authorized:
            return .fullAccess
        case .writeOnly:
            return .writeOnly
        case .fullAccess:
            return .fullAccess
        @unknown default:
            return .notDetermined
        }
    }

    @discardableResult
    public func requestAccess() async throws -> CalendarAuthorizationStatus {
        do {
            let granted = try await store.requestFullAccessToEvents()
            return granted ? .fullAccess : .denied
        } catch {
            throw CalendarProviderError.underlying(String(describing: error))
        }
    }

    public func eventsToday(now: Date) async throws -> [CalendarEvent] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: now)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else {
            return []
        }

        return try await eventsBetween(start: start, end: end)
    }

    public func eventsBetween(start: Date, end: Date) async throws -> [CalendarEvent] {
        // No defensive authorization guard here. Callers (e.g. TodayDashboard) already gate on
        // `calendarEventsEnabled`, and `EKEventStore.events(matching:)` returns `[]` when
        // authorization is denied. Keeping a TOCTOU check would duplicate that contract while
        // racing the real EventKit decision.
        return await withCheckedContinuation { continuation in
            eventQueryQueue.async { [storeBox] in
                let predicate = storeBox.store.predicateForEvents(withStart: start, end: end, calendars: nil)
                let events =
                    storeBox.store
                    .events(matching: predicate)
                    .map(Self.calendarEvent(from:))
                    .sorted { lhs, rhs in
                        if lhs.start == rhs.start {
                            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
                        }
                        return lhs.start < rhs.start
                    }
                continuation.resume(returning: events)
            }
        }
    }

    private static func calendarEvent(from event: EKEvent) -> CalendarEvent {
        let videoURL = detectVideoURL(in: event)

        return CalendarEvent(
            id: event.eventIdentifier ?? UUID().uuidString,
            title: event.title.nilIfBlank ?? "Untitled",
            start: event.startDate,
            end: event.endDate,
            location: event.location.nilIfBlank,
            attendees: attendees(from: event),
            isVideoCall: videoURL != nil,
            urlForJoin: videoURL,
            calendarColorHex: event.calendar?.cgColor.flatMap(hexString(from:)),
            isAllDay: event.isAllDay,
            calendarID: event.calendar?.calendarIdentifier
        )
    }

    private static func attendees(from event: EKEvent) -> [CalendarEvent.Attendee] {
        (event.attendees ?? []).map { attendee in
            CalendarEvent.Attendee(
                name: attendee.name.nilIfBlank,
                email: attendee.url.emailAddress
            )
        }
    }

    private static func detectVideoURL(in event: EKEvent) -> URL? {
        let candidates =
            [
                event.url
            ].compactMap { $0 }
            + (event.notes.map(urls(in:)) ?? [])
            + (event.location.map(urls(in:)) ?? [])

        return candidates.first(where: isVideoCallURL)
    }

    static func urls(in text: String) -> [URL] {
        let separators = CharacterSet.whitespacesAndNewlines.union(.init(charactersIn: "<>()[]{}\"'"))
        let rawTokens = text.components(separatedBy: separators)
        var urls: [URL] = []

        for token in rawTokens {
            let trimmed = token.trimmingCharacters(in: .init(charactersIn: ".,;:!?"))
            guard !trimmed.isEmpty else { continue }

            if let url = URL(string: trimmed), url.scheme != nil {
                urls.append(url)
                continue
            }

            if trimmed.contains(".") {
                guard let url = URL(string: "https://\(trimmed)") else { continue }
                urls.append(url)
            }
        }

        return urls
    }

    static func isVideoCallURL(_ url: URL) -> Bool {
        let value = url.absoluteString.lowercased()
        return value.contains("zoom.us/j/")
            || value.contains("meet.google.com/")
            || value.contains("teams.microsoft.com/")
    }

    static func hexString(from color: CGColor) -> String? {
        let sRGB = CGColorSpace(name: CGColorSpace.sRGB)
        let converted =
            sRGB.flatMap {
                color.converted(to: $0, intent: .defaultIntent, options: nil)
            } ?? color
        guard let components = converted.components else { return nil }

        let red: CGFloat
        let green: CGFloat
        let blue: CGFloat

        switch components.count {
        case 2:
            red = components[0]
            green = components[0]
            blue = components[0]
        case 3...:
            red = components[0]
            green = components[1]
            blue = components[2]
        default:
            return nil
        }

        return String(
            format: "#%02X%02X%02X",
            clampedColorByte(red),
            clampedColorByte(green),
            clampedColorByte(blue)
        )
    }

    private static func clampedColorByte(_ component: CGFloat) -> Int {
        Int((min(max(component, 0), 1) * 255).rounded())
    }
}

private final class EventKitStoreBox: @unchecked Sendable {
    let store: EKEventStore

    init(store: EKEventStore) {
        self.store = store
    }
}

extension String {
    fileprivate var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

extension Optional where Wrapped == String {
    fileprivate var nilIfBlank: String? {
        flatMap(\.nilIfBlank)
    }
}

extension URL {
    fileprivate var emailAddress: String? {
        guard scheme?.lowercased() == "mailto" else { return nil }
        return
            absoluteString
            .replacingOccurrences(of: "mailto:", with: "")
            .nilIfBlank
    }
}
#endif
