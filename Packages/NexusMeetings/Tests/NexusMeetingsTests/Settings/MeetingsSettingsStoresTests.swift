import Foundation
import NexusAI
import Testing

@testable import NexusMeetings

@Test func meetingPromptStoreLoadSaveReset() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("meeting-prompt-store-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let store = MeetingsPromptStore(applicationSupportURL: root)

    #expect(store.load() == nil)

    try store.save("Summarize {{title}}\n{{transcript}}")

    #expect(store.promptFileURL.path.hasSuffix("com.kacperpietrzyk.Nexus/meetings_prompt.md"))
    #expect(store.load() == "Summarize {{title}}\n{{transcript}}")

    try store.reset()

    #expect(store.load() == nil)
}

@Test func meetingsProviderSettingsUseRuntimeRawValues() {
    #expect(MeetingsTranscriptionProviderPreference.parakeetTDTv3.rawValue == "parakeet-tdt-v3")
    #expect(MeetingsTranscriptionProviderPreference.whisperKitLarge.rawValue == "whisperkit-large")
    #expect(MeetingsTranscriptionProviderPreference.ask.rawValue == "ask")

    #expect(MeetingsSummaryProviderPreference.auto.rawValue == ProviderPreference.auto.rawValue)
    #expect(MeetingsSummaryProviderPreference.disabled.rawValue == "disabled")
    #expect(MeetingsSummaryProviderPreference.disabled.providerPreference == nil)
}

@Test func meetingsProviderSettingsStoreFallsBackForUnknownValues() {
    let suiteName = "meetings-provider-settings-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }

    defaults.set("openai", forKey: MeetingsSettingsKeys.summaryProvider)
    defaults.set("parakeet", forKey: MeetingsSettingsKeys.transcriptionProvider)

    let store = MeetingsProviderSettingsStore(defaults: defaults)

    #expect(store.summaryProvider() == .auto)
    #expect(store.transcriptionProvider() == .parakeetTDTv3)
}

@Test func meetingsHelperAutoRecordPreferenceStoreDefaultsToDisabledUntilUserChoice() {
    let suiteName = "meetings-helper-auto-record-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let store = UserDefaultsHelperAutoRecordStore(defaults: defaults)

    #expect(store.isEnabled() == false)

    store.save(enabled: true)
    #expect(store.isEnabled() == true)

    store.save(enabled: false)
    #expect(store.isEnabled() == false)
}
