import Foundation
import NexusUI
import Testing

@testable import NexusAgent

@Test func settingsSectionsHaveStableOrder() {
    #expect(
        AgentSettingsView.sectionOrder == [
            .masterSwitch,
            .providerRouting,
            .schedulesEditor,
            .indexing,
            .memoryEditor,
            .audit,
            .devHub,
        ]
    )
}

@Test("Agent preload speech uses WhisperKit preload key")
func preloadSpeechUsesWhisperKitPreloadKey() {
    #expect(NexusPreferences.Keys.agentPreloadSpeech == "nexus.agent.voice.preloadWhisperKit")
}
