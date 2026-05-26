import Foundation
import Testing

@testable import NexusUI

@Test func whisperKitPreloadToggle_usesStableUserDefaultsKey() {
    #expect(NexusPreferences.Keys.agentVoicePreloadWhisperKit == "nexus.agent.voice.preloadWhisperKit")
    #expect(NexusPreferences.Keys.agentPreloadSpeech == NexusPreferences.Keys.agentVoicePreloadWhisperKit)
}

@Test func whisperKitPreloadToggle_keyDefaultsOffAndRoundTrips() {
    let suite = "nexus-test-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }

    #expect(defaults.bool(forKey: NexusPreferences.Keys.agentVoicePreloadWhisperKit) == false)
    defaults.set(true, forKey: NexusPreferences.Keys.agentVoicePreloadWhisperKit)
    #expect(defaults.bool(forKey: NexusPreferences.Keys.agentVoicePreloadWhisperKit) == true)
    defaults.set(false, forKey: NexusPreferences.Keys.agentVoicePreloadWhisperKit)
    #expect(defaults.bool(forKey: NexusPreferences.Keys.agentVoicePreloadWhisperKit) == false)
}
