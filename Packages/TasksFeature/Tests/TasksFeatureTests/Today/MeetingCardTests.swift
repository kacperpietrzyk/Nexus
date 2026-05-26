import NexusCore
import SwiftUI
import Testing

@testable import TasksFeature

@MainActor
@Suite("MeetingCard v4")
struct MeetingCardTests {
    @Test
    func buildsWithAttendeesAndJoinURL() {
        let event = CalendarEvent(
            id: "standup",
            title: "Standup",
            start: Date(timeIntervalSince1970: 1_800),
            end: Date(timeIntervalSince1970: 2_700),
            location: "Zoom",
            attendees: [
                .init(name: "Ada Lovelace", email: "ada@example.com"),
                .init(name: "Grace Hopper", email: "grace@example.com"),
                .init(email: "linus@example.com"),
                .init(name: "Margaret Hamilton"),
            ],
            isVideoCall: true,
            urlForJoin: URL(string: "https://zoom.us/j/123")
        )

        _ = MeetingCard(event: event)
    }

    @Test
    func buildsCurrentState() {
        let event = CalendarEvent(
            id: "focus-review",
            title: "Focus Review",
            start: Date(timeIntervalSince1970: 3_600),
            end: Date(timeIntervalSince1970: 5_400)
        )

        _ = MeetingCard(event: event, isCurrent: true)
    }

    @Test
    func buildsWithoutJoinURLForCalendarFallback() {
        let event = CalendarEvent(
            id: "calendar-only",
            title: "Calendar-only",
            start: Date(timeIntervalSince1970: 7_200),
            end: Date(timeIntervalSince1970: 8_100)
        )

        _ = MeetingCard(event: event)
    }

    @Test
    func todayDashboardAcceptsCalendarProviderEnvironment() {
        let provider = MockCalendarEventProvider(events: [
            CalendarEvent(
                id: "calendar-event",
                title: "Calendar Event",
                start: Date(timeIntervalSince1970: 3_600),
                end: Date(timeIntervalSince1970: 4_500)
            )
        ])

        _ = TodayDashboard()
            .environment(\.calendarEventProvider, provider)
    }

    @Test
    func dashboardCalendarEventsRespectToggle() async {
        let event = CalendarEvent(
            id: "calendar-event",
            title: "Calendar Event",
            start: Date(timeIntervalSince1970: 3_600),
            end: Date(timeIntervalSince1970: 4_500)
        )
        let provider = MockCalendarEventProvider(events: [event])

        let disabled = await TodayDashboard.calendarEvents(now: event.start, enabled: false, provider: provider)
        let enabled = await TodayDashboard.calendarEvents(now: event.start, enabled: true, provider: provider)

        #expect(disabled.isEmpty)
        #expect(enabled == [event])
    }

    // MARK: - liveDotOpacity regression (Reduce Motion fix)

    @Test("live dot is full strength 1.0 under Reduce Motion regardless of phase")
    func liveDotOpacityReduceMotionAlwaysFullStrength() {
        let phases: [Double] = [0, .pi / 4, .pi, 7.3, -2.1]
        for phase in phases {
            #expect(MeetingCard.liveDotOpacity(reduceMotion: true, phase: phase) == 1.0)
        }
    }

    @Test("live dot opacity stays within [0.4, 1.0] range when motion is enabled")
    func liveDotOpacityMotionEnabledInRange() {
        let step = Double.pi / 8
        var phase = 0.0
        while phase < 2 * .pi {
            let opacity = MeetingCard.liveDotOpacity(reduceMotion: false, phase: phase)
            #expect(opacity >= 0.4 && opacity <= 1.0)
            phase += step
        }
    }
}
