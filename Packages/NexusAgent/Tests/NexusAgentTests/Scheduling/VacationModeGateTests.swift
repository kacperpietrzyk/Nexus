import Foundation
import NexusUI
import Testing

@testable import NexusAgent

@MainActor
@Test func vacationModeBlocksFires() {
    let suite = "test-vac-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }

    defaults.set(true, forKey: NexusPreferences.Keys.agentVacationMode)
    let gate = VacationModeGate(defaults: defaults)

    #expect(!gate.shouldFire(scheduleID: UUID()))
}

@MainActor
@Test func vacationModeAllowsFiresWhenOff() {
    let suite = "test-vac-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }

    defaults.set(false, forKey: NexusPreferences.Keys.agentVacationMode)
    let gate = VacationModeGate(defaults: defaults)

    #expect(gate.shouldFire(scheduleID: UUID()))
}

@MainActor
@Test func agentEnableToggleBlocksFires() {
    let suite = "test-agent-enabled-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }

    defaults.set(false, forKey: NexusPreferences.Keys.agentEnabled)
    defaults.set(false, forKey: NexusPreferences.Keys.agentVacationMode)
    let gate = VacationModeGate(defaults: defaults)

    #expect(!gate.shouldFire(scheduleID: UUID()))
}

@MainActor
@Test func missingAgentEnableToggleDefaultsToEnabled() {
    let suite = "test-agent-enabled-default-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }

    defaults.set(false, forKey: NexusPreferences.Keys.agentVacationMode)
    let gate = VacationModeGate(defaults: defaults)

    #expect(gate.shouldFire(scheduleID: UUID()))
}
