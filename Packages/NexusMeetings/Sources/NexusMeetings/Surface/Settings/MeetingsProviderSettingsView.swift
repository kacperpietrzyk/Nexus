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
        VStack(alignment: .leading, spacing: DS.Space.xxxl) {
            LiquidGlassCard("Transcription") {
                HStack {
                    Text("Provider")
                        .font(DS.FontToken.body)
                        .foregroundStyle(DS.ColorToken.textPrimary)
                    Spacer()
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
                .frame(minHeight: 44)
            }

            LiquidGlassCard("Summary") {
                HStack {
                    Text("Provider")
                        .font(DS.FontToken.body)
                        .foregroundStyle(DS.ColorToken.textPrimary)
                    Spacer()
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
                .frame(minHeight: 44)
            }
        }
    }
}
