import Foundation
import NexusCore
import Testing

@testable import NexusMeetings

@MainActor
@Test func detectorEmitsEventOnFirstMatch() async {
    let registry = AppPatternRegistry.makeDefault()
    let workspace = StubWorkspace(snapshots: [
        .init(
            bundleID: "com.microsoft.teams2",
            pid: 1,
            isFrontmost: true,
            windowTitles: ["Microsoft Teams Meeting"]
        )
    ])
    let poller = WindowTitlePoller(
        registry: registry,
        workspace: workspace,
        activeCadence: 0.01,
        idleCadence: 0.05
    )
    let debouncer = DetectionDebouncer(window: 60)
    let correlator = CalendarCorrelator(provider: EmptyCalendarProvider())
    let detector = MeetingDetector(
        poller: poller,
        debouncer: debouncer,
        correlator: correlator,
        registry: registry
    )
    let event = await firstEvent(from: detector)

    #expect(event?.bundleID == "com.microsoft.teams2")
    #expect(event?.pid == 1)
    #expect(
        (event?.suggestedTitle.contains("Teams") ?? false)
            || (event?.suggestedTitle.contains("Meeting") ?? false)
    )
}

@MainActor
@Test func detectorUsesCalendarCorrelationWhenAvailable() async {
    let registry = AppPatternRegistry.makeDefault()
    let workspace = StubWorkspace(snapshots: [
        .init(
            bundleID: "com.microsoft.teams2",
            pid: 1,
            isFrontmost: true,
            windowTitles: ["Microsoft Teams Meeting | Microsoft Teams"]
        )
    ])
    let poller = WindowTitlePoller(
        registry: registry,
        workspace: workspace,
        activeCadence: 0.01,
        idleCadence: 0.05
    )
    let provider = StubCalendarProvider(events: [
        .init(
            id: "calendar-1",
            title: "Product Review",
            start: Date().addingTimeInterval(-60),
            end: Date().addingTimeInterval(60)
        )
    ])
    let detector = MeetingDetector(
        poller: poller,
        debouncer: DetectionDebouncer(window: 60),
        correlator: CalendarCorrelator(provider: provider, window: 5 * 60),
        registry: registry
    )

    let event = await firstEvent(from: detector)

    #expect(event?.suggestedTitle == "Product Review")
    #expect(event?.calendarEventID == "calendar-1")
}

@MainActor
@Test func detectorSanitizesPipeStyleZoomSuffixWithoutCalendarCorrelation() async {
    let registry = AppPatternRegistry.makeDefault()
    let workspace = StubWorkspace(snapshots: [
        .init(
            bundleID: "us.zoom.xos",
            pid: 1,
            isFrontmost: true,
            windowTitles: ["Zoom Meeting | Zoom"]
        )
    ])
    let poller = WindowTitlePoller(
        registry: registry,
        workspace: workspace,
        activeCadence: 0.01,
        idleCadence: 0.05
    )
    let detector = MeetingDetector(
        poller: poller,
        debouncer: DetectionDebouncer(window: 60),
        correlator: CalendarCorrelator(provider: EmptyCalendarProvider()),
        registry: registry
    )

    let event = await firstEvent(from: detector)

    #expect(event?.suggestedTitle == "Zoom Meeting")
    #expect(event?.calendarEventID == nil)
}

@MainActor
@Test func detectorDebouncesSpacedAndNoSpaceZoomPipeTitlesTogether() async {
    let registry = AppPatternRegistry.makeDefault()
    let workspace = StubWorkspace(snapshots: [
        .init(
            bundleID: "us.zoom.xos",
            pid: 1,
            isFrontmost: true,
            windowTitles: [
                "Zoom Meeting|Zoom",
                "Zoom Meeting | Zoom",
            ]
        )
    ])
    let poller = WindowTitlePoller(
        registry: registry,
        workspace: workspace,
        activeCadence: 0.01,
        idleCadence: 0.05
    )
    let detector = MeetingDetector(
        poller: poller,
        debouncer: DetectionDebouncer(window: 60),
        correlator: CalendarCorrelator(provider: EmptyCalendarProvider()),
        registry: registry
    )

    let events = await collectedEvents(from: detector, limit: 2, timeoutNanoseconds: 2_000_000_000)

    #expect(events.count == 1)
    #expect(events.first?.fingerprint == "us.zoom.xos|Zoom Meeting")
    #expect(events.first?.suggestedTitle == "Zoom Meeting")
}

@MainActor
@Test func detectorDoesNotDebounceWhenCancelledDuringCorrelation() async {
    let registry = AppPatternRegistry.makeDefault()
    let workspace = StubWorkspace(snapshots: [
        .init(
            bundleID: "com.microsoft.teams2",
            pid: 1,
            isFrontmost: true,
            windowTitles: ["Microsoft Teams Meeting"]
        )
    ])
    let poller = WindowTitlePoller(
        registry: registry,
        workspace: workspace,
        activeCadence: 0.01,
        idleCadence: 0.05
    )
    let detector = MeetingDetector(
        poller: poller,
        debouncer: DetectionDebouncer(window: 60),
        correlator: CalendarCorrelator(provider: SlowCalendarProvider(delayNanoseconds: 300_000_000)),
        registry: registry
    )
    let cancelledConsumer = Task {
        await firstEvent(from: detector, timeoutNanoseconds: 1_000_000_000)
    }

    try? await Task.sleep(nanoseconds: 50_000_000)
    cancelledConsumer.cancel()
    _ = await cancelledConsumer.value

    let event = await firstEvent(from: detector, timeoutNanoseconds: 1_000_000_000)

    #expect(event?.bundleID == "com.microsoft.teams2")
    #expect(event?.fingerprint == "com.microsoft.teams2|Microsoft Teams Meeting")
}

@MainActor
@Test func detectorSuppressesDuplicateUntilAcknowledged() async {
    let registry = AppPatternRegistry.makeDefault()
    let workspace = StubWorkspace(snapshots: [
        .init(
            bundleID: "com.microsoft.teams2",
            pid: 1,
            isFrontmost: true,
            windowTitles: ["Microsoft Teams Meeting"]
        )
    ])
    let poller = WindowTitlePoller(
        registry: registry,
        workspace: workspace,
        activeCadence: 0.01,
        idleCadence: 0.05
    )
    let detector = MeetingDetector(
        poller: poller,
        debouncer: DetectionDebouncer(window: 60),
        correlator: CalendarCorrelator(provider: EmptyCalendarProvider()),
        registry: registry
    )
    var events: [MeetingDetectionEvent] = []
    let task = Task { @MainActor in
        for await event in detector.events() {
            events.append(event)
            if events.count == 1 {
                detector.acknowledgeRecording(fingerprint: event.fingerprint)
            } else {
                break
            }
        }
    }

    await waitFor { events.count == 2 }
    task.cancel()
    await task.value
    #expect(events.count == 2)
    if events.count == 2 {
        #expect(events[0].fingerprint == events[1].fingerprint)
    }
}

@MainActor
@Test func detectorRecordsDebounceBeforePostYieldCancellation() async {
    let registry = AppPatternRegistry.makeDefault()
    let workspace = StubWorkspace(snapshots: [
        .init(
            bundleID: "com.microsoft.teams2",
            pid: 1,
            isFrontmost: true,
            windowTitles: ["Microsoft Teams Meeting"]
        )
    ])
    let debouncer = DetectionDebouncer(window: 60)
    let firstDetector = MeetingDetector(
        poller: WindowTitlePoller(
            registry: registry,
            workspace: workspace,
            activeCadence: 0.01,
            idleCadence: 0.05
        ),
        debouncer: debouncer,
        correlator: CalendarCorrelator(provider: EmptyCalendarProvider()),
        registry: registry
    )
    let firstEvent = await firstEvent(from: firstDetector)

    let secondDetector = MeetingDetector(
        poller: WindowTitlePoller(
            registry: registry,
            workspace: workspace,
            activeCadence: 0.01,
            idleCadence: 0.05
        ),
        debouncer: debouncer,
        correlator: CalendarCorrelator(provider: EmptyCalendarProvider()),
        registry: registry
    )
    let secondEvents = await collectedEvents(
        from: secondDetector,
        limit: 1,
        timeoutNanoseconds: 150_000_000
    )

    #expect(firstEvent?.fingerprint == "com.microsoft.teams2|Microsoft Teams Meeting")
    #expect(secondEvents.isEmpty)
}

@MainActor
private func firstEvent(
    from detector: MeetingDetector,
    timeoutNanoseconds: UInt64 = 500_000_000
) async -> MeetingDetectionEvent? {
    await withTaskGroup(of: MeetingDetectionEvent?.self) { group in
        group.addTask {
            for await detected in detector.events() {
                return detected
            }
            return nil
        }
        group.addTask {
            try? await Task.sleep(nanoseconds: timeoutNanoseconds)
            return nil
        }

        guard let event = await group.next() else {
            group.cancelAll()
            return nil
        }
        group.cancelAll()
        return event
    }
}

@MainActor
private func collectedEvents(
    from detector: MeetingDetector,
    limit: Int,
    timeoutNanoseconds: UInt64
) async -> [MeetingDetectionEvent] {
    var events: [MeetingDetectionEvent] = []
    let task = Task { @MainActor in
        for await detected in detector.events() {
            events.append(detected)
            if events.count == limit {
                break
            }
        }
    }
    try? await Task.sleep(nanoseconds: timeoutNanoseconds)
    task.cancel()
    return events
}

@MainActor
private func waitFor(
    timeoutNanoseconds: UInt64 = 500_000_000,
    condition: @escaping @MainActor () -> Bool
) async {
    let stepNanoseconds: UInt64 = 10_000_000
    let attempts = max(1, Int(timeoutNanoseconds / stepNanoseconds))
    for _ in 0..<attempts where !condition() {
        try? await Task.sleep(nanoseconds: stepNanoseconds)
    }
}

private final class StubWorkspace: WindowTitleWorkspaceProviding, @unchecked Sendable {
    let snapshots: [RunningAppSnapshot]

    init(snapshots: [RunningAppSnapshot]) {
        self.snapshots = snapshots
    }

    func currentSnapshots(trackedBundleIDs: Set<String>) -> [RunningAppSnapshot] {
        snapshots.filter { trackedBundleIDs.contains($0.bundleID) }
    }
}

private struct EmptyCalendarProvider: CalendarEventProviding {
    func authorizationStatus() -> CalendarAuthorizationStatus {
        .fullAccess
    }

    func requestAccess() async throws -> CalendarAuthorizationStatus {
        .fullAccess
    }

    func eventsToday(now: Date) async throws -> [CalendarEvent] {
        []
    }

    func eventsBetween(start: Date, end: Date) async throws -> [CalendarEvent] {
        []
    }
}

private struct StubCalendarProvider: CalendarEventProviding {
    let events: [CalendarEvent]

    func authorizationStatus() -> CalendarAuthorizationStatus {
        .fullAccess
    }

    func requestAccess() async throws -> CalendarAuthorizationStatus {
        .fullAccess
    }

    func eventsToday(now: Date) async throws -> [CalendarEvent] {
        events
    }

    func eventsBetween(start: Date, end: Date) async throws -> [CalendarEvent] {
        events.filter { event in
            event.end > start && event.start < end
        }
    }
}

private struct SlowCalendarProvider: CalendarEventProviding {
    let delayNanoseconds: UInt64

    func authorizationStatus() -> CalendarAuthorizationStatus {
        .fullAccess
    }

    func requestAccess() async throws -> CalendarAuthorizationStatus {
        .fullAccess
    }

    func eventsToday(now: Date) async throws -> [CalendarEvent] {
        []
    }

    func eventsBetween(start: Date, end: Date) async throws -> [CalendarEvent] {
        try await Task.sleep(nanoseconds: delayNanoseconds)
        return []
    }
}
