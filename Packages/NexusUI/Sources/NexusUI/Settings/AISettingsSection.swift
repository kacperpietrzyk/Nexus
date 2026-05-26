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
        Section {
            if let liveData {
                providerRow(
                    title: "Apple Intelligence",
                    subtitle: "Local generation",
                    state: liveData.appleIntelligenceAvailability
                )
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
                providerRow(
                    title: "Embeddings",
                    subtitle: "NLEmbedding semantic index",
                    state: .unavailable(reason: .modelNotAvailable)
                )
            }

            Text("Phase 1l-MLX adds a local LLM for longer-context work.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } header: {
            nexusSettingsSectionHeader("On-device providers")
        }

        Section {
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

            WhisperKitPreloadToggle()
        } header: {
            nexusSettingsSectionHeader("Voice")
        }
        .task { await liveData?.refresh() }
    }

    @ViewBuilder
    private func providerRow(title: String, subtitle: String, state: AvailabilityState) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.footnote)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            switch state {
            case .available:
                NexusBadge("Local", systemImage: "checkmark.circle.fill", tone: .pos)
            case .unavailable(let reason):
                NexusBadge(reasonLabel(reason), systemImage: "exclamationmark.circle", tone: .warn)
            }
        }
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
