import NexusCore
import SwiftUI

private struct CalendarEventProviderEnvironmentKey: EnvironmentKey {
    static let defaultValue: any CalendarEventProviding = MockCalendarEventProvider()
}

private struct CalendarEventWriterEnvironmentKey: EnvironmentKey {
    static let defaultValue: (any CalendarEventWriting)? = nil
}

extension EnvironmentValues {
    public var calendarEventProvider: any CalendarEventProviding {
        get { self[CalendarEventProviderEnvironmentKey.self] }
        set { self[CalendarEventProviderEnvironmentKey.self] = newValue }
    }

    /// Optional EventKit write surface (spec §8). nil when no calendar write
    /// access is wired; the Today rail's "Plan my day" still proposes blocks
    /// locally, but accepting a block (materializing its mirror event) requires
    /// this writer. Injected by the composition root.
    public var calendarEventWriter: (any CalendarEventWriting)? {
        get { self[CalendarEventWriterEnvironmentKey.self] }
        set { self[CalendarEventWriterEnvironmentKey.self] = newValue }
    }
}
