import SwiftUI

#if !os(watchOS)

import NexusAI

/// AI status for local-only providers.
public struct AISettingsSection: View {
    private let liveData: AISettingsLiveData?

    public init(liveData: AISettingsLiveData? = nil) {
        self.liveData = liveData
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: NexusSpacing.s7) {
            onDeviceGroup
            voiceGroup
        }
        .task { await liveData?.refresh() }
    }

    private var onDeviceGroup: some View {
        VStack(alignment: .leading, spacing: NexusSpacing.s3) {
            nexusSettingsCardSectionHeader("On-device providers")
            NexusSettingsCard {
                VStack(alignment: .leading, spacing: 0) {
                    if let liveData {
                        providerRow(
                            title: "Apple Intelligence",
                            subtitle: "Local generation",
                            state: liveData.appleIntelligenceAvailability
                        )
                        NexusSettingsDivider()
                        providerRow(
                            title: "Embeddings",
                            subtitle: "NLEmbedding semantic index",
                            state: liveData.embeddingAvailability
                        )
                    } else {
                        providerRow(
                            title: "Apple Intelligence",
                            subtitle: "Local generation",
                            state: .unavailable(reason: .modelNotAvailable)
                        )
                        NexusSettingsDivider()
                        providerRow(
                            title: "Embeddings",
                            subtitle: "NLEmbedding semantic index",
                            state: .unavailable(reason: .modelNotAvailable)
                        )
                    }
                }
            }
            Text("Phase 1l-MLX adds a local LLM for longer-context work.")
                .font(NexusType.caption)
                .foregroundStyle(NexusColor.Text.muted)
                .padding(.horizontal, NexusSpacing.s4)
        }
    }

    private var voiceGroup: some View {
        VStack(alignment: .leading, spacing: NexusSpacing.s3) {
            nexusSettingsCardSectionHeader("Voice")
            NexusSettingsCard {
                VStack(alignment: .leading, spacing: 0) {
                    if let liveData {
                        providerRow(
                            title: "Transcription",
                            subtitle: "WhisperKit local speech-to-text",
                            state: liveData.whisperKitAvailability
                        )
                    } else {
                        providerRow(
                            title: "Transcription",
                            subtitle: "WhisperKit local speech-to-text",
                            state: .unavailable(reason: .modelNotAvailable)
                        )
                    }

                    if liveData != nil {
                        NexusSettingsDivider()
                        WhisperKitDownloadControl(onRefresh: { await liveData?.refresh() })
                            .padding(.horizontal, NexusSpacing.s4)
                            .padding(.vertical, NexusSpacing.s3)
                    }
                    NexusSettingsDivider()
                    WhisperKitPreloadToggle()
                        .padding(.horizontal, NexusSpacing.s4)
                        .padding(.vertical, NexusSpacing.s3)
                }
            }
        }
    }

    @ViewBuilder
    private func providerRow(title: String, subtitle: String, state: AvailabilityState) -> some View {
        HStack(alignment: .center, spacing: NexusSpacing.s4) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(NexusType.bodySmall.weight(.medium))
                    .foregroundStyle(NexusColor.Text.primary)
                Text(subtitle)
                    .font(NexusType.caption)
                    .foregroundStyle(NexusColor.Text.muted)
            }
            Spacer(minLength: NexusSpacing.s4)
            switch state {
            case .available:
                NexusBadge("Local", systemImage: "checkmark.circle.fill", tone: .pos)
            case .unavailable(let reason):
                NexusBadge(reasonLabel(reason), systemImage: "exclamationmark.circle", tone: .warn)
            }
        }
        .padding(.horizontal, NexusSpacing.s4)
        .padding(.vertical, NexusSpacing.s3)
    }

    private func reasonLabel(_ reason: AvailabilityState.UnavailableReason) -> String {
        switch reason {
        case .modelNotAvailable: return "Not available on this device"
        case .modelDownloading: return "Downloading…"
        case .userDisabled: return "Disabled in System Settings"
        }
    }

}

#endif
