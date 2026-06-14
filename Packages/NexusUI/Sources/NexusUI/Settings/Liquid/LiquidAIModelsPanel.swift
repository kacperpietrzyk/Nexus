#if os(macOS)
import NexusAI
import SwiftUI

// MARK: - AI & Models panel

/// On-device providers + Voice cards, then the composed Models (ManageModels) and
/// Agent (AgentSettings) sub-views embedded chromeless.
///
/// Provider/voice availability comes from `AISettingsLiveData`, which derives every
/// field from self-contained static checks (`AppleIntelligenceProvider.isModelAvailable`,
/// `NLEmbedding`, `WhisperKitProvider().isAvailableOnThisPlatform`) and ignores its
/// `router` argument — so `AISettingsLiveData(router: nil)` yields real availability
/// with no app-root wiring, mirroring `NexusSettingsView.macProvidersSection` /
/// `macVoiceSection`. The embedded sub-views receive `settingsDetailEmbedded = true`
/// so their shared `NexusSettingsDetailContainer` drops its own header + `ScrollView`
/// (the host detail pane provides both).
struct AIModelsPanel: View {
    @Environment(\.macSettingsDependencies) private var deps
    @State private var liveData = AISettingsLiveData(router: nil)

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.l) {
            providersCard
            voiceCard

            subHeader("Models")
            deps.manageModelsContent()
                .environment(\.settingsDetailEmbedded, true)

            subHeader("Agent")
            deps.agentSettingsContent()
                .environment(\.settingsDetailEmbedded, true)
        }
        .task { await liveData.refresh() }
    }

    // MARK: On-device providers card

    private var providersCard: some View {
        LiquidGlassCard("On-device providers") {
            VStack(spacing: 0) {
                providerRow(
                    title: "Apple Intelligence",
                    subtitle: "Local generation",
                    state: liveData.appleIntelligenceAvailability
                )

                Divider()
                    .overlay(DS.ColorToken.strokeHairline)

                providerRow(
                    title: "Embeddings",
                    subtitle: "NLEmbedding semantic index",
                    state: liveData.embeddingAvailability
                )

                Divider()
                    .overlay(DS.ColorToken.strokeHairline)

                Text("Phase 1l-MLX adds a local LLM for longer-context work.")
                    .font(DS.FontToken.caption)
                    .foregroundStyle(DS.ColorToken.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, DS.Space.s)
            }
        }
    }

    // MARK: Voice card

    private var voiceCard: some View {
        LiquidGlassCard("Voice") {
            VStack(spacing: 0) {
                providerRow(
                    title: "Transcription",
                    subtitle: "WhisperKit local speech-to-text",
                    state: liveData.whisperKitAvailability
                )

                Divider()
                    .overlay(DS.ColorToken.strokeHairline)

                WhisperKitDownloadControl(onRefresh: { await liveData.refresh() })
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, DS.Space.m)

                Divider()
                    .overlay(DS.ColorToken.strokeHairline)

                HStack {
                    Text("Preload transcription model at launch")
                        .font(DS.FontToken.body)
                        .foregroundStyle(DS.ColorToken.textPrimary)
                    Spacer()
                    WhisperKitPreloadToggle()
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
                .frame(minHeight: 44)
            }
        }
    }

    // MARK: Helpers

    private func providerRow(title: String, subtitle: String, state: AvailabilityState) -> some View {
        HStack(alignment: .center, spacing: DS.Space.m) {
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                Text(title)
                    .font(DS.FontToken.body.weight(.semibold))
                    .foregroundStyle(DS.ColorToken.textPrimary)
                Text(subtitle)
                    .font(DS.FontToken.caption)
                    .foregroundStyle(DS.ColorToken.textTertiary)
            }
            Spacer(minLength: DS.Space.l)
            switch state {
            case .available:
                LiquidPill("Local", color: DS.ColorToken.accentGreen, filled: true)
            case .unavailable(let reason):
                LiquidPill(reasonLabel(reason), color: DS.ColorToken.statusNeutral)
            }
        }
        .frame(minHeight: 44)
    }

    private func reasonLabel(_ reason: AvailabilityState.UnavailableReason) -> String {
        switch reason {
        case .modelNotAvailable: return "Not available on this device"
        case .modelDownloading: return "Downloading..."
        case .userDisabled: return "Disabled in System Settings"
        }
    }

    private func subHeader(_ title: String) -> some View {
        Text(title)
            .font(DS.FontToken.caption)
            .foregroundStyle(DS.ColorToken.textTertiary)
            .textCase(.uppercase)
            .tracking(1.4)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
#endif
