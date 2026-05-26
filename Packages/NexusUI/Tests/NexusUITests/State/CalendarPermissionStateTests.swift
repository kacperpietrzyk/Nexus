import Foundation
import NexusCore
import Testing

@testable import NexusUI

@Suite("CalendarPermissionState")
@MainActor
struct CalendarPermissionStateTests {
    @Test func initialStatusComesFromProvider() {
        let provider = MockCalendarEventProvider(status: .restricted)

        let state = CalendarPermissionState(provider: provider)

        #expect(state.status == .restricted)
    }

    @Test func requestAccessUpdatesStatusFromProvider() async {
        let provider = MockCalendarEventProvider(status: .notDetermined)
        provider.requestAccessHook = { .fullAccess }
        let state = CalendarPermissionState(provider: provider)

        await state.requestAccess()

        #expect(state.status == .fullAccess)
    }

    @Test func requestAccessFailureFallsBackToDenied() async {
        let provider = FailingCalendarEventProvider(status: .notDetermined)
        let state = CalendarPermissionState(provider: provider)

        await state.requestAccess()

        #expect(state.status == .denied)
    }
}

private final class FailingCalendarEventProvider: CalendarEventProviding, @unchecked Sendable {
    private let statusValue: CalendarAuthorizationStatus

    init(status: CalendarAuthorizationStatus) {
        self.statusValue = status
    }

    func authorizationStatus() -> CalendarAuthorizationStatus {
        statusValue
    }

    func requestAccess() async throws -> CalendarAuthorizationStatus {
        throw CalendarProviderError.accessDenied
    }

    func eventsToday(now: Date) async throws -> [CalendarEvent] {
        []
    }

    func eventsBetween(start: Date, end: Date) async throws -> [CalendarEvent] {
        []
    }
}
