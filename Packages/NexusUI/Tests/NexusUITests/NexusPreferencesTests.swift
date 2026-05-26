import Foundation
import Testing

@testable import NexusUI

@Test func nexusPreferences_keys_haveStableNamespace() {
    #expect(NexusPreferences.Keys.theme == "nexus.general.theme")
    #expect(NexusPreferences.Keys.mcpEnabled == "nexus.mcp.enabled")
    #expect(NexusPreferences.Keys.advancedEnabled == "nexus.advanced.uiVisibility")
    #expect(NexusPreferences.Keys.welcomeShown == "nexus.welcome.shown")
    #expect(NexusPreferences.Keys.calendarEventsInTodayEnabled == "nexus.calendar.eventsInTodayEnabled")
    #expect(NexusPreferences.Keys.agentEnabled == "nexus.agent.enabled")
    #expect(NexusPreferences.Keys.agentMemoryAutoSaveEnabled == "nexus.agent.memory.autoSaveEnabled")
    #expect(NexusPreferences.Keys.agentVacationMode == "nexus.agent.vacationMode")
    #expect(NexusPreferences.Keys.agentPreloadSpeech == "nexus.agent.voice.preloadWhisperKit")
    #expect(NexusPreferences.Keys.agentVoicePreloadWhisperKit == "nexus.agent.voice.preloadWhisperKit")
}

@Test func nexusPreferences_themeRawValues_areStable() {
    #expect(NexusTheme.amberDark.rawValue == "amberDark")
    #expect(NexusTheme.allCases == [.amberDark])
}

@Test func nexusPreferences_advancedEnabledRoundTripsThroughUserDefaults() {
    let suite = "nexus-test-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }

    #expect(defaults.bool(forKey: NexusPreferences.Keys.advancedEnabled) == false)
    defaults.set(true, forKey: NexusPreferences.Keys.advancedEnabled)
    #expect(defaults.bool(forKey: NexusPreferences.Keys.advancedEnabled) == true)
}

@Test func nexusPreferences_welcomeShownRoundTripsThroughUserDefaults() {
    let suite = "nexus-test-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }

    #expect(defaults.bool(forKey: NexusPreferences.Keys.welcomeShown) == false)
    defaults.set(true, forKey: NexusPreferences.Keys.welcomeShown)
    #expect(defaults.bool(forKey: NexusPreferences.Keys.welcomeShown) == true)
}

@Test func nexusPreferences_calendarEventsInTodayRoundTripsThroughUserDefaults() {
    let suite = "nexus-test-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }

    #expect(defaults.bool(forKey: NexusPreferences.Keys.calendarEventsInTodayEnabled) == false)
    defaults.set(true, forKey: NexusPreferences.Keys.calendarEventsInTodayEnabled)
    #expect(defaults.bool(forKey: NexusPreferences.Keys.calendarEventsInTodayEnabled) == true)
}

@Test func nexusPreferences_purgesLegacyAgentSidebarOpenKey() {
    let suite = "nexus-test-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }

    defaults.set(true, forKey: "nexus.agent.sidebarOpen")
    #expect(defaults.object(forKey: "nexus.agent.sidebarOpen") != nil)

    NexusPreferences.purgeLegacyAgentSidebarOpenKey(defaults: defaults)

    #expect(defaults.object(forKey: "nexus.agent.sidebarOpen") == nil)
}

@Test func nexusPreferences_agentEnabledRoundTripsThroughUserDefaults() {
    let suite = "nexus-test-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }

    #expect(defaults.bool(forKey: NexusPreferences.Keys.agentEnabled) == false)
    defaults.set(true, forKey: NexusPreferences.Keys.agentEnabled)
    #expect(defaults.bool(forKey: NexusPreferences.Keys.agentEnabled) == true)
    defaults.set(false, forKey: NexusPreferences.Keys.agentEnabled)
    #expect(defaults.bool(forKey: NexusPreferences.Keys.agentEnabled) == false)
}

@Test func nexusPreferences_agentMemoryAutoSaveRoundTripsThroughUserDefaults() {
    let suite = "nexus-test-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }

    #expect(defaults.bool(forKey: NexusPreferences.Keys.agentMemoryAutoSaveEnabled) == false)
    defaults.set(true, forKey: NexusPreferences.Keys.agentMemoryAutoSaveEnabled)
    #expect(defaults.bool(forKey: NexusPreferences.Keys.agentMemoryAutoSaveEnabled) == true)
    defaults.set(false, forKey: NexusPreferences.Keys.agentMemoryAutoSaveEnabled)
    #expect(defaults.bool(forKey: NexusPreferences.Keys.agentMemoryAutoSaveEnabled) == false)
}

@Test func nexusPreferences_agentVacationModeRoundTripsThroughUserDefaults() {
    let suite = "nexus-test-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }

    #expect(defaults.bool(forKey: NexusPreferences.Keys.agentVacationMode) == false)
    defaults.set(true, forKey: NexusPreferences.Keys.agentVacationMode)
    #expect(defaults.bool(forKey: NexusPreferences.Keys.agentVacationMode) == true)
    defaults.set(false, forKey: NexusPreferences.Keys.agentVacationMode)
    #expect(defaults.bool(forKey: NexusPreferences.Keys.agentVacationMode) == false)
}

@Test func nexusPreferences_agentPreloadSpeechRoundTripsThroughUserDefaults() {
    let suite = "nexus-test-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }

    #expect(defaults.bool(forKey: NexusPreferences.Keys.agentPreloadSpeech) == false)
    defaults.set(true, forKey: NexusPreferences.Keys.agentPreloadSpeech)
    #expect(defaults.bool(forKey: NexusPreferences.Keys.agentPreloadSpeech) == true)
    defaults.set(false, forKey: NexusPreferences.Keys.agentPreloadSpeech)
    #expect(defaults.bool(forKey: NexusPreferences.Keys.agentPreloadSpeech) == false)
}

@Test func nexusPreferences_migratesLegacyAgentPreloadSpeechKey() {
    let suite = "nexus-test-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }

    defaults.set(true, forKey: "nexus.agent.preloadSpeech")

    NexusPreferences.migrateLegacyAgentPreloadSpeechKey(defaults: defaults)

    #expect(defaults.bool(forKey: NexusPreferences.Keys.agentVoicePreloadWhisperKit) == true)
}
