import NexusCore
import NexusUI
import SwiftUI

public struct MeetingsProviderSettingsView: View {
    @AppStorage(MeetingsSettingsKeys.transcriptionProvider, store: .nexusGroup)
    private var transcription = MeetingsTranscriptionProviderPreference.parakeetTDTv3.rawValue

    @AppStorage(MeetingsSettingsKeys.summaryProvider, store: .nexusGroup)
    private var summary = MeetingsSummaryProviderPreference.assistantModel.rawValue

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
                    NexusSelect(
                        selection: $transcription,
                        options: [
                            MeetingsTranscriptionProviderPreference.parakeetTDTv3.rawValue,
                            MeetingsTranscriptionProviderPreference.whisperKitLarge.rawValue,
                            MeetingsTranscriptionProviderPreference.ask.rawValue,
                        ],
                        label: { raw in
                            switch MeetingsTranscriptionProviderPreference(rawValue: raw) {
                            case .parakeetTDTv3: "Parakeet TDT v3 (default)"
                            case .whisperKitLarge: "WhisperKit-large (fallback)"
                            case .ask: "Ask per meeting"
                            default: raw
                            }
                        },
                        accessibilityLabel: "Provider"
                    )
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
                    NexusSelect(
                        selection: $summary,
                        options: [
                            MeetingsSummaryProviderPreference.assistantModel.rawValue,
                            MeetingsSummaryProviderPreference.appleIntelligence.rawValue,
                            MeetingsSummaryProviderPreference.disabled.rawValue,
                        ],
                        label: { raw in
                            switch MeetingsSummaryProviderPreference(rawValue: raw) {
                            case .assistantModel: "Asystent (Gemma, on-device) — domyślnie"
                            case .appleIntelligence: "Apple Intelligence"
                            case .disabled: "Wyłączone"
                            default: raw
                            }
                        },
                        accessibilityLabel: "Provider"
                    )
                    .frame(maxWidth: 220, alignment: .trailing)
                }
                .frame(minHeight: 44)
            }
        }
    }
}
