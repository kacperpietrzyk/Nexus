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
        let notes = event.notes.nilIfBlank

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
            calendarID: event.calendar?.calendarIdentifier,
            organizer: event.organizer.map(attendee(from:)),
            notes: notes,
            meetingID: teamsMeetingID(notes: notes, joinURL: videoURL, eventURL: event.url)
        )
    }

    private static func attendees(from event: EKEvent) -> [CalendarEvent.Attendee] {
        (event.attendees ?? []).map(attendee(from:))
    }

    private static func attendee(from participant: EKParticipant) -> CalendarEvent.Attendee {
        CalendarEvent.Attendee(
            name: participant.name.nilIfBlank,
            email: participant.url.emailAddress,
            responseStatus: responseStatus(from: participant.participantStatus),
            role: role(from: participant.participantRole),
            isCurrentUser: participant.isCurrentUser
        )
    }

    private static func responseStatus(from status: EKParticipantStatus) -> CalendarEvent.ResponseStatus? {
        switch status {
        case .accepted: return .accepted
        case .declined: return .declined
        case .tentative: return .tentative
        case .pending: return .pending
        // `.unknown`, `.delegated`, `.completed`, `.inProcess` have no clean Nexus
        // mapping — surface them as "no recorded response" rather than guessing.
        default: return nil
        }
    }

    private static func role(from role: EKParticipantRole) -> CalendarEvent.Role? {
        switch role {
        case .required: return .required
        case .optional: return .optional
        case .chair: return .chair
        // `.unknown` / `.nonParticipant` carry no useful UI distinction.
        default: return nil
        }
    }

    /// Extract a Microsoft Teams meeting identifier (digits only) from the invite.
    /// Anchors on the two reliable forms — the `teams.microsoft.com/meet/<digits>`
    /// join URL and the localized "meeting id" label (e.g. Polish
    /// "Identyfikator spotkania: 312 967 000 844 149") — rather than grabbing the
    /// longest digit run, so phone numbers in the body are not misread (#4a).
    static func teamsMeetingID(notes: String?, joinURL: URL?, eventURL: URL?) -> String? {
        let urlCandidates = [joinURL, eventURL].compactMap(\.self).map(\.absoluteString)
        if let urlMeetID = urlCandidates.compactMap(meetID(fromTeamsURL:)).first {
            return urlMeetID
        }

        guard let notes else { return nil }
        // Any teams.microsoft.com/meet/<digits> URL embedded in the notes body.
        if let embedded = urls(in: notes).compactMap({ meetID(fromTeamsURL: $0.absoluteString) }).first {
            return embedded
        }
        // Localized label forms: "<label>: <grouped digits>". Match a label, then
        // read the digit groups that follow and strip the spaces. Covers EN
        // "Meeting ID:" and PL "Identyfikator spotkania:".
        return labelledMeetingID(in: notes)
    }

    private static func meetID(fromTeamsURL urlString: String) -> String? {
        let lower = urlString.lowercased()
        guard let range = lower.range(of: "teams.microsoft.com/meet/") else { return nil }
        let tail = urlString[range.upperBound...]
        let digits = tail.prefix { $0.isNumber }
        return digits.isEmpty ? nil : String(digits)
    }

    private static func labelledMeetingID(in text: String) -> String? {
        let labels = ["identyfikator spotkania", "meeting id", "meeting-id"]
        let separators: Set<Character> = [":", " ", "\u{00A0}"]
        let lower = text.lowercased()
        for label in labels {
            guard let labelRange = lower.range(of: label) else { continue }
            // Skip the label and any ":"/whitespace separator.
            var cursor = labelRange.upperBound
            while cursor < lower.endIndex, separators.contains(lower[cursor]) {
                cursor = lower.index(after: cursor)
            }
            // Collect digits, tolerating the spaces that group them, then strip
            // those spaces. Stops at the first non-digit, non-grouping character.
            var digits = ""
            var index = cursor
            while index < lower.endIndex {
                let character = lower[index]
                if character.isNumber {
                    digits.append(character)
                } else if (character == " " || character == "\u{00A0}") && !digits.isEmpty {
                    index = lower.index(after: index)
                    continue
                } else {
                    break
                }
                index = lower.index(after: index)
            }
            if !digits.isEmpty { return digits }
        }
        return nil
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
