import Foundation
@preconcurrency import WhisperKit

/// Downloads the WhisperKit transcription model and makes it usable end-to-end.
///
/// The `argmaxinc/whisperkit-coreml` variant folder ships only the CoreML models
/// — NOT the tokenizer — so a model-only download leaves transcription broken
/// (WhisperKit fetches the tokenizer separately on first load). This coordinator
/// therefore does two things on `download()`:
///   1. snapshots the variant folder (with progress), then
///   2. warm-loads it once so WhisperKit fetches and caches the tokenizer while
///      the network is available — the first real transcription then needs no
///      network.
/// On success it persists the variant folder path under
/// ``WhisperKitProvider/modelFolderDefaultsKey`` so every `WhisperKitProvider` /
/// `WhisperKitMeetingProvider` reflects the downloaded model immediately.
///
/// Self-contained: the download base and variant are deterministic, so the
/// Settings UI can own an instance directly without any app-root wiring.
@MainActor
@Observable
public final class WhisperKitModelDownloadCoordinator {
    public enum Phase: Equatable, Sendable {
        case idle
        case downloading(Double)
        /// Model files are on disk; warm-loading to fetch + cache the tokenizer.
        case preparing
        case done
        case failed(String)
    }

    public private(set) var phase: Phase

    public init() {
        self.phase = WhisperKitProvider.isModelDownloaded() ? .done : .idle
    }

    public var isDownloading: Bool {
        switch phase {
        case .downloading, .preparing: return true
        default: return false
        }
    }

    /// Downloads + prepares the model. Idempotent enough for a button: a second
    /// tap while in flight is ignored.
    public func download() async {
        guard !isDownloading else { return }
        guard let base = WhisperKitProvider.defaultDownloadBase() else {
            phase = .failed("No Application Support directory available.")
            return
        }

        phase = .downloading(0)
        do {
            try FileManager.default.createDirectory(
                at: base, withIntermediateDirectories: true)

            let modelFolder = try await WhisperKit.download(
                variant: WhisperKitProvider.modelVariant,
                downloadBase: base,
                progressCallback: { [weak self] progress in
                    let fraction = progress.fractionCompleted
                    Task { @MainActor in
                        guard let self, self.isDownloading else { return }
                        self.phase = .downloading(fraction)
                    }
                }
            )

            // Warm-load once so WhisperKit fetches + caches the tokenizer now.
            phase = .preparing
            let warm = try await WhisperKit(
                WhisperKitConfig(
                    modelFolder: modelFolder.path,
                    tokenizerFolder: base,
                    verbose: false,
                    prewarm: false,
                    load: true,
                    download: false
                )
            )
            _ = warm  // discard — the model is on disk; free the RAM immediately.

            UserDefaults.standard.set(
                modelFolder.path, forKey: WhisperKitProvider.modelFolderDefaultsKey)
            phase = .done
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }
}
