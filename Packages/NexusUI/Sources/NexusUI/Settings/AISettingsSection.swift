import SwiftUI

#if !os(watchOS)

import NexusAI

/// AI status for local-only providers. Liquid-skinned: each logical group is a
/// `LiquidGlassCard` (was a Linear `nexusSettingsCardSectionHeader` +
/// `NexusSettingsCard` pair), rows use `DS.*` tokens, and inter-row separators
/// are `Divider().overlay(DS.ColorToken.strokeHairline)`. Shared with iOS
/// `NexusSettingsView` and rendered on macOS via NexusAgent's
/// `AgentProviderRoutingSection`. All `liveData` wiring is preserved verbatim.
public struct AISettingsSection: View {
    private let liveData: AISettingsLiveData?

    public init(liveData: AISettingsLiveData? = nil) {
        self.liveData = liveData
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.l) {
            onDeviceGroup
            voiceGroup
        }
        .task { await liveData?.refresh() }
    }

    private var onDeviceGroup: some View {
        VStack(alignment: .leading, spacing: DS.Space.m) {
            LiquidGlassCard("On-device providers") {
                VStack(alignment: .leading, spacing: 0) {
                    if let liveData {
                        providerRow(
                            title: "Apple Intelligence",
                            subtitle: "Local generation",
                            state: liveData.appleIntelligenceAvailability
                        )
                        divider
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
                        divider
                        providerRow(
                            title: "Embeddings",
                            subtitle: "NLEmbedding semantic index",
                            state: .unavailable(reason: .modelNotAvailable)
                        )
                    }
                }
            }
            Text("Phase 1l-MLX adds a local LLM for longer-context work.")
                .font(DS.FontToken.caption)
                .foregroundStyle(DS.ColorToken.textMuted)
                .padding(.horizontal, DS.Space.l)
        }
    }

    private var voiceGroup: some View {
        LiquidGlassCard("Voice") {
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
                    divider
                    WhisperKitDownloadControl(onRefresh: { await liveData?.refresh() })
                        .padding(.horizontal, DS.Space.l)
                        .padding(.vertical, DS.Space.m)
                }
                divider
                WhisperKitPreloadToggle()
                    .padding(.horizontal, DS.Space.l)
                    .padding(.vertical, DS.Space.m)
            }
        }
    }

    private var divider: some View {
        Divider()
            .overlay(DS.ColorToken.strokeHairline)
    }

    @ViewBuilder
    private func providerRow(title: String, subtitle: String, state: AvailabilityState) -> some View {
        HStack(alignment: .center, spacing: DS.Space.l) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(DS.FontToken.body)
                    .foregroundStyle(DS.ColorToken.textPrimary)
                Text(subtitle)
                    .font(DS.FontToken.caption)
                    .foregroundStyle(DS.ColorToken.textMuted)
            }
            Spacer(minLength: DS.Space.l)
            switch state {
            case .available:
                NexusBadge("Local", systemImage: "checkmark.circle.fill", tone: .pos)
            case .unavailable(let reason):
                NexusBadge(reasonLabel(reason), systemImage: "exclamationmark.circle", tone: .warn)
            }
        }
        .padding(.horizontal, DS.Space.l)
        .padding(.vertical, DS.Space.m)
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
