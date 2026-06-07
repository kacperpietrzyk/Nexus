import Foundation

/// A Sendable description of a single EventKit calendar, shaped for the
/// multi-calendar Settings surface (spec §9 / §13). EventKit-free by contract so
/// the listing can be rendered and unit-tested without touching `EKCalendar`.
public struct CalendarInfo: Identifiable, Equatable, Sendable {
    /// `EKCalendar.calendarIdentifier`.
    public let id: String
    public let title: String
    /// Source title (e.g. "iCloud", "On My Mac") for grouping in Settings.
    public let sourceTitle: String
    /// Hex color (`#RRGGBB`) of the calendar, if resolvable.
    public let colorHex: String?
    /// Whether Nexus may create/edit events in this calendar (write-target eligibility).
    public let isWritable: Bool

    public init(
        id: String,
        title: String,
        sourceTitle: String,
        colorHex: String? = nil,
        isWritable: Bool = false
    ) {
        self.id = id
        self.title = title
        self.sourceTitle = sourceTitle
        self.colorHex = colorHex
        self.isWritable = isWritable
    }
}

/// Enumerate the user's event calendars (spec §9 multi-cal Settings). Separate
/// from `CalendarEventProviding` (read events) and `CalendarEventWriting` (CRUD)
/// so adding the listing surface never breaks the existing conformers. EventKit
/// lives entirely inside `EventKitCalendarProvider`; the Settings view depends
/// only on this protocol and is tested with a fake.
public protocol CalendarListing: Sendable {
    /// All event calendars visible to the app, sorted by source then title. Empty
    /// when access is not granted.
    func availableCalendars() async throws -> [CalendarInfo]
}
