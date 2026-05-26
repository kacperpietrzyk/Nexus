#if canImport(EventKit) && !os(watchOS)
import CoreGraphics
import Foundation
import Testing

@testable import NexusCore

@Suite("EventKitCalendarProvider helpers")
struct EventKitCalendarProviderHelperTests {
    @Test("URL extraction scans every URL and video filter can choose a later meeting link")
    func extractsAllURLs() throws {
        let urls = EventKitCalendarProvider.urls(
            in: "Agenda: https://example.com/doc. Join: https://meet.google.com/abc-defg-hij"
        )

        #expect(urls.map(\.absoluteString) == ["https://example.com/doc", "https://meet.google.com/abc-defg-hij"])
        #expect(urls.first(where: EventKitCalendarProvider.isVideoCallURL)?.absoluteString == "https://meet.google.com/abc-defg-hij")
    }

    @Test("Color hex converts through sRGB")
    func colorHexUsesSRGB() throws {
        let color = CGColor(
            srgbRed: 0.2,
            green: 0.4,
            blue: 0.6,
            alpha: 1
        )

        #expect(EventKitCalendarProvider.hexString(from: color) == "#336699")
    }
}

@Suite(
    "EventKitCalendarProvider (INTEGRATION=1)",
    .enabled(if: ProcessInfo.processInfo.environment["INTEGRATION"] == "1")
)
struct EventKitCalendarProviderIntegrationTests {
    @Test("Reports an authorization status")
    func reportsStatus() {
        let provider = EventKitCalendarProvider()
        let status = provider.authorizationStatus()
        let valid: [CalendarAuthorizationStatus] = [
            .notDetermined,
            .denied,
            .restricted,
            .fullAccess,
            .writeOnly,
        ]

        #expect(valid.contains(status))
    }

    @Test("eventsToday returns empty when not authorized")
    func emptyWhenUnauthorized() async throws {
        let provider = EventKitCalendarProvider()
        guard provider.authorizationStatus() != .fullAccess else { return }

        let events = try await provider.eventsToday(now: .now)
        #expect(events.isEmpty)
    }
}
#endif
