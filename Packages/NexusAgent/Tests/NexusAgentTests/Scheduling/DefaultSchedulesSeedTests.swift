import Foundation
import Testing

@testable import NexusAgent

@MainActor
@Test func seedAddsFourDefaultsOnce() throws {
    let ctx = try AgentTestSupport.makeContext()
    let store = AgentScheduleStore(context: ctx)
    let defaults = UserDefaults(suiteName: "test-seed-\(UUID())")!
    try DefaultSchedulesSeed.runIfNeeded(store: store, defaults: defaults)
    #expect(try store.allActive().count == 4)
    try DefaultSchedulesSeed.runIfNeeded(store: store, defaults: defaults)
    #expect(try store.allActive().count == 4)
}

@MainActor
@Test func seedMarksMorningEveningWeeklyEnabledDigestDisabled() throws {
    let ctx = try AgentTestSupport.makeContext()
    let store = AgentScheduleStore(context: ctx)
    let defaults = UserDefaults(suiteName: "test-seed-\(UUID())")!
    try DefaultSchedulesSeed.runIfNeeded(store: store, defaults: defaults)
    let names = try store.allActive().map { ($0.name, $0.enabled) }
    let enabled = Dictionary(uniqueKeysWithValues: names)
    #expect(enabled["Morning Brief"] == true)
    #expect(enabled["Evening Plan"] == true)
    #expect(enabled["Weekly Review"] == true)
    #expect(enabled["Project Digest"] == false)
}

@MainActor
@Test func seedRecoversPartialDefaultsWithoutDuplicates() throws {
    let ctx = try AgentTestSupport.makeContext()
    let store = AgentScheduleStore(context: ctx)
    let defaults = UserDefaults(suiteName: "test-seed-\(UUID())")!
    _ = try store.create(
        name: "Morning Brief",
        kind: .builtIn,
        cronExpression: "0 8 * * *",
        prompt: "partial",
        enabled: true
    )
    _ = try store.create(
        name: "Project Digest",
        kind: .projectDigest,
        cronExpression: "0 9 * * 1",
        prompt: "partial",
        enabled: false
    )

    try DefaultSchedulesSeed.runIfNeeded(store: store, defaults: defaults)

    let identities = try store.allActive().map { "\($0.name)|\($0.kind.rawValue)" }
    #expect(identities.count == 4)
    #expect(Set(identities).count == 4)
    #expect(defaults.bool(forKey: DefaultSchedulesSeed.seededKey))
}
