import Foundation

public enum CalendarAuthorizationStatus: Sendable, Equatable {
    case notDetermined
    case denied
    case restricted
    case fullAccess
    case writeOnly
}

public enum CalendarProviderError: Error, Sendable {
    case accessDenied
    case underlying(String)
}

public protocol CalendarEventProviding: Sendable {
    func authorizationStatus() -> CalendarAuthorizationStatus

    @discardableResult
    func requestAccess() async throws -> CalendarAuthorizationStatus

    func eventsToday(now: Date) async throws -> [CalendarEvent]
    func eventsBetween(start: Date, end: Date) async throws -> [CalendarEvent]
}
