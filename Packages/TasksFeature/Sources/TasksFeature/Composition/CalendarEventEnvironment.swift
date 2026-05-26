import NexusCore
import SwiftUI

private struct CalendarEventProviderEnvironmentKey: EnvironmentKey {
    static let defaultValue: any CalendarEventProviding = MockCalendarEventProvider()
}

extension EnvironmentValues {
    public var calendarEventProvider: any CalendarEventProviding {
        get { self[CalendarEventProviderEnvironmentKey.self] }
        set { self[CalendarEventProviderEnvironmentKey.self] = newValue }
    }
}
