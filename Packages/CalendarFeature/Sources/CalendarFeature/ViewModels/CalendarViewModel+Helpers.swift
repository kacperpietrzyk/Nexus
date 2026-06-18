import Foundation
import NexusCore

// MARK: - Display / error-copy helpers
//
// Stateless static helpers extracted from `CalendarViewModel.swift` to keep
// that file under the length limit. Neither touches instance state.
extension CalendarViewModel {
    /// Format an attendee for the read-only editor list: "Name (email)" when both
    /// are present, otherwise whichever the invite carried; nil only when neither.
    static func attendeeDisplay(_ attendee: CalendarEvent.Attendee) -> String? {
        switch (attendee.name, attendee.email) {
        case (let name?, let email?): return "\(name) (\(email))"
        case (let name?, nil): return name
        case (nil, let email?): return email
        case (nil, nil): return nil
        }
    }

    /// User-facing `lastError` copy: `CalendarProviderError` carries its own
    /// message (`LocalizedError`), so surfaces never render the enum's debug
    /// shape (`underlying("…")`); anything else falls back to the debug
    /// description as before.
    nonisolated static func errorMessage(_ error: any Error) -> String {
        if let providerError = error as? CalendarProviderError {
            return providerError.errorDescription ?? String(describing: error)
        }
        return String(describing: error)
    }
}
