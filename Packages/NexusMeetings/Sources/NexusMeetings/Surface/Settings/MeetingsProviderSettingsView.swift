import NexusCore
import SwiftUI

public struct MeetingsProviderSettingsView: View {
    @AppStorage(MeetingsSettingsKeys.transcriptionProvider, store: .nexusGroup)
    private var transcription = MeetingsTranscriptionProviderPreference.parakeetTDTv3.rawValue

    @AppStorage(MeetingsSettingsKeys.summaryProvider, store: .nexusGroup)
    private var summary = MeetingsSummaryProviderPreference.auto.rawValue

    private let composition: MeetingsComposition

    public init(composition: MeetingsComposition) {
        self.composition = composition
    }

    public var body: some View {
        Section("Transcription") {
            Picker("Provider", selection: $transcription) {
                Text("Parakeet TDT v3 (default)")
                    .tag(MeetingsTranscriptionProviderPreference.parakeetTDTv3.rawValue)
                Text("WhisperKit-large (fallback)")
                    .tag(MeetingsTranscriptionProviderPreference.whisperKitLarge.rawValue)
                Text("Ask per meeting")
                    .tag(MeetingsTranscriptionProviderPreference.ask.rawValue)
            }
        }

        Section("Summary") {
            Picker("Provider", selection: $summary) {
                Text("Apple Intelligence (default)")
                    .tag(MeetingsSummaryProviderPreference.auto.rawValue)
                Text("Disabled")
                    .tag(MeetingsSummaryProviderPreference.disabled.rawValue)
            }
        }
    }
}
