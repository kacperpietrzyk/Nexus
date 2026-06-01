import NexusCore
import NexusUI
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
        VStack(alignment: .leading, spacing: NexusSpacing.s7) {
            VStack(alignment: .leading, spacing: NexusSpacing.s3) {
                nexusSettingsCardSectionHeader("Transcription")
                NexusSettingsCard {
                    NexusSettingsRow("Provider") {
                        Picker("Provider", selection: $transcription) {
                            Text("Parakeet TDT v3 (default)")
                                .tag(MeetingsTranscriptionProviderPreference.parakeetTDTv3.rawValue)
                            Text("WhisperKit-large (fallback)")
                                .tag(MeetingsTranscriptionProviderPreference.whisperKitLarge.rawValue)
                            Text("Ask per meeting")
                                .tag(MeetingsTranscriptionProviderPreference.ask.rawValue)
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(maxWidth: 220, alignment: .trailing)
                    }
                }
            }

            VStack(alignment: .leading, spacing: NexusSpacing.s3) {
                nexusSettingsCardSectionHeader("Summary")
                NexusSettingsCard {
                    NexusSettingsRow("Provider") {
                        Picker("Provider", selection: $summary) {
                            Text("Apple Intelligence (default)")
                                .tag(MeetingsSummaryProviderPreference.auto.rawValue)
                            Text("Disabled")
                                .tag(MeetingsSummaryProviderPreference.disabled.rawValue)
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(maxWidth: 220, alignment: .trailing)
                    }
                }
            }
        }
    }
}
