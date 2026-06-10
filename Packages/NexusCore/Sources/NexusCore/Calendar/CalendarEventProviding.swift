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

extension CalendarProviderError: LocalizedError {
    /// User-facing message, so surfaces never render the enum's debug shape
    /// (`underlying("…")`): `.underlying` already carries provider copy;
    /// `.accessDenied` gets the one readable sentence the UI needs.
    public var errorDescription: String? {
        switch self {
        case .accessDenied:
            return "Calendar access was denied."
        case .underlying(let message):
            return message
        }
    }
}

public protocol CalendarEventProviding: Sendable {
    func authorizationStatus() -> CalendarAuthorizationStatus

    @discardableResult
    func requestAccess() async throws -> CalendarAuthorizationStatus

    func eventsToday(now: Date) async throws -> [CalendarEvent]
    func eventsBetween(start: Date, end: Date) async throws -> [CalendarEvent]
}
