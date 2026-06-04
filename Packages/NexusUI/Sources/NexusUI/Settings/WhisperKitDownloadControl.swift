import SwiftUI

#if !os(watchOS)

import NexusAI

/// Download button + progress for the WhisperKit transcription model.
///
/// Owns its own coordinator — the download base + variant are deterministic, so
/// no app-root wiring is needed — and reads the already-downloaded state on init,
/// so the button hides once the model is present. Shared by the iOS
/// (`AISettingsSection`) and macOS (`NexusSettingsView.macVoiceSection`) settings
/// so BOTH platforms can fetch the local speech-to-text model. macOS previously
/// lacked this control entirely, leaving transcription stuck at "Not available
/// on this device" with no way to download.
///
/// `onRefresh` lets the host re-evaluate provider availability (e.g. refresh the
/// "Local" badge) once a download finishes.
public struct WhisperKitDownloadControl: View {
    private let onRefresh: () async -> Void
    @State private var downloader = WhisperKitModelDownloadCoordinator()

    public init(onRefresh: @escaping () async -> Void = {}) {
        self.onRefresh = onRefresh
    }

    public var body: some View {
        switch downloader.phase {
        case .done:
            EmptyView()
        case .idle:
            // The one genuine primary action in this group (gated by backend
            // availability) — so it earns the lime primary treatment per the
            // "lime only on primary action" rule.
            NexusButton(variant: .primary, size: .sm) {
                Task {
                    await downloader.download()
                    await onRefresh()
                }
            } label: {
                Text("Download transcription model (~1 GB)")
            }
        case .downloading(let fraction):
            ProgressView(value: fraction) {
                Text("Downloading transcription model… \(Int(fraction * 100))%")
                    .font(NexusType.caption)
                    .foregroundStyle(NexusColor.Text.secondary)
            }
            .tint(NexusColor.Text.primary)
        case .preparing:
            ProgressView {
                Text("Preparing transcription model…")
                    .font(NexusType.caption)
                    .foregroundStyle(NexusColor.Text.secondary)
            }
            .tint(NexusColor.Text.primary)
        case .failed(let message):
            VStack(alignment: .leading, spacing: NexusSpacing.s2) {
                Label("Download failed", systemImage: "exclamationmark.triangle")
                    .font(NexusType.bodySmall.weight(.medium))
                    .foregroundStyle(NexusColor.Text.primary)
                Text(message)
                    .font(NexusType.caption)
                    .foregroundStyle(NexusColor.Text.muted)
                    .textSelection(.enabled)
                NexusButton(variant: .outline, size: .sm) {
                    Task {
                        await downloader.download()
                        await onRefresh()
                    }
                } label: {
                    Text("Retry")
                }
            }
        }
    }
}

#endif
