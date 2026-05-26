import Foundation
import Testing

@testable import NexusMeetings

@Test func defaultsIncludeTeamsZoomWebex() {
    let registry = AppPatternRegistry.makeDefault()
    let bundleIDs = Set(registry.patterns.map(\.bundleID))
    #expect(bundleIDs.contains("com.microsoft.teams2"))
    #expect(bundleIDs.contains("us.zoom.xos"))
    #expect(bundleIDs.contains("Cisco-Systems.Spark"))
}

@Test func teamsMatchesMeetingTitles() {
    let registry = AppPatternRegistry.makeDefault()
    #expect(
        registry.matches(
            bundleID: "com.microsoft.teams2",
            title: "Microsoft Teams Meeting"))
    #expect(
        registry.matches(
            bundleID: "com.microsoft.teams2",
            title: "Waiting for the meeting to start | Microsoft Teams"))
    #expect(
        registry.matches(
            bundleID: "com.microsoft.teams2",
            title: "Inbox — Microsoft Teams") == false)
    #expect(
        registry.matches(
            bundleID: "com.microsoft.teams2",
            title: "Inbox | Microsoft Teams") == false)
}

@Test func zoomLobbyMatches() {
    let registry = AppPatternRegistry.makeDefault()
    #expect(registry.matches(bundleID: "us.zoom.xos", title: "Zoom Meeting"))
    #expect(registry.matches(bundleID: "us.zoom.xos", title: "Waiting Room — Zoom"))
    #expect(registry.matches(bundleID: "us.zoom.xos", title: "Zoom - Mail") == false)
}

@Test func disabledPatternsDoNotMatch() {
    var registry = AppPatternRegistry.makeDefault()
    registry.setEnabled("com.microsoft.teams2", enabled: false)
    #expect(
        registry.matches(
            bundleID: "com.microsoft.teams2",
            title: "Microsoft Teams Meeting") == false)
}

@Test func appendedSameBundlePatternsCanMatch() {
    var registry = AppPatternRegistry.makeDefault()
    registry.append(
        .init(
            bundleID: "us.zoom.xos",
            displayName: "Zoom Custom",
            regex: #"(?i)^Custom Zoom Focus Room$"#))

    #expect(
        registry.matches(
            bundleID: "us.zoom.xos",
            title: "Custom Zoom Focus Room"))
}

@Test func disablingBundleDisablesDuplicatePatterns() {
    var registry = AppPatternRegistry(patterns: [
        .init(
            bundleID: "com.microsoft.teams2",
            displayName: "Microsoft Teams",
            regex: #"(?i)microsoft teams.*meeting"#),
        .init(
            bundleID: "com.microsoft.teams2",
            displayName: "Microsoft Teams Custom",
            regex: #"(?i)^Custom Teams Meeting$"#),
    ])

    registry.setEnabled("com.microsoft.teams2", enabled: false)

    #expect(
        registry.matches(
            bundleID: "com.microsoft.teams2",
            title: "Microsoft Teams Meeting") == false)
    #expect(
        registry.matches(
            bundleID: "com.microsoft.teams2",
            title: "Custom Teams Meeting") == false)
}

@Test func registryRoundTripsThroughCodable() throws {
    let registry = AppPatternRegistry.makeDefault()
    let data = try JSONEncoder().encode(registry)
    let decoded = try JSONDecoder().decode(AppPatternRegistry.self, from: data)

    #expect(decoded == registry)
}

@Test func fingerprintNormalizesVolatileSuffixes() {
    let registry = AppPatternRegistry.makeDefault()
    #expect(
        registry.fingerprint(
            bundleID: "us.zoom.xos",
            title: "Zoom Meeting — abc-def") == "us.zoom.xos|Zoom Meeting")
    #expect(
        registry.fingerprint(
            bundleID: "us.zoom.xos",
            title: "Zoom Meeting|Zoom") == "us.zoom.xos|Zoom Meeting")
    #expect(
        registry.fingerprint(
            bundleID: "us.zoom.xos",
            title: "Zoom Meeting | Zoom") == "us.zoom.xos|Zoom Meeting")
    #expect(
        registry.fingerprint(
            bundleID: "com.microsoft.teams2",
            title: "Weekly Sync — Microsoft Teams") == "com.microsoft.teams2|Weekly Sync")
    #expect(
        registry.fingerprint(
            bundleID: "com.microsoft.teams2",
            title: "Weekly Sync—Microsoft Teams") == "com.microsoft.teams2|Weekly Sync")
    #expect(
        registry.fingerprint(
            bundleID: "com.microsoft.teams2",
            title: "Weekly Sync | Microsoft Teams") == "com.microsoft.teams2|Weekly Sync")
    #expect(
        registry.fingerprint(
            bundleID: "com.microsoft.teams2",
            title: "Weekly Sync|Microsoft Teams") == "com.microsoft.teams2|Weekly Sync")
}

@Test func normalizedTitleMatchesFingerprintTitleComponent() {
    let registry = AppPatternRegistry.makeDefault()
    let titles = [
        "Zoom Meeting|Zoom",
        "Zoom Meeting | Zoom",
        "Weekly Sync|Microsoft Teams",
        "Weekly Sync—Microsoft Teams",
    ]

    for title in titles {
        #expect(registry.fingerprint(bundleID: "bundle", title: title) == "bundle|\(registry.normalizedTitle(title))")
    }
}
