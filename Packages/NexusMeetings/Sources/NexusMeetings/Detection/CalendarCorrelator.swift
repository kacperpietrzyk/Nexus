import Foundation
import NexusCore

public struct CalendarCorrelationResult: Sendable, Equatable {
    public let eventID: String
    public let title: String

    public init(eventID: String, title: String) {
        self.eventID = eventID
        self.title = title
    }
}

public final class CalendarCorrelator: Sendable {
    private let provider: any CalendarEventProviding
    private let window: TimeInterval

    public init(provider: any CalendarEventProviding, window: TimeInterval = 15 * 60) {
        self.provider = provider
        self.window = window
    }

    public func correlate(at moment: Date) async -> CalendarCorrelationResult? {
        let lower = moment.addingTimeInterval(-window)
        let upper = moment.addingTimeInterval(window)

        do {
            let events = try await provider.eventsBetween(start: lower, end: upper)
            guard
                let pick = events.min(by: { lhs, rhs in
                    CalendarCorrelator.isBetter(lhs, than: rhs, at: moment)
                })
            else {
                return nil
            }
            return CalendarCorrelationResult(eventID: pick.id, title: pick.title)
        } catch {
            // Calendar correlation is best-effort and must not block meeting detection.
            return nil
        }
    }

    private static func isBetter(_ lhs: CalendarEvent, than rhs: CalendarEvent, at moment: Date) -> Bool {
        let lhsIsActive = lhs.start <= moment && lhs.end > moment
        let rhsIsActive = rhs.start <= moment && rhs.end > moment
        if lhsIsActive != rhsIsActive {
            return lhsIsActive
        }

        let lhsStartDelta = abs(lhs.start.timeIntervalSince(moment))
        let rhsStartDelta = abs(rhs.start.timeIntervalSince(moment))
        if lhsStartDelta != rhsStartDelta {
            return lhsStartDelta < rhsStartDelta
        }

        if lhs.start != rhs.start {
            return lhs.start < rhs.start
        }

        let titleComparison = lhs.title.localizedCaseInsensitiveCompare(rhs.title)
        if titleComparison != .orderedSame {
            return titleComparison == .orderedAscending
        }

        return lhs.id < rhs.id
    }
}
