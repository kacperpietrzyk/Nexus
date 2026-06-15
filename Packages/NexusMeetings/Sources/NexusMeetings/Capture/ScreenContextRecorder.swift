import Foundation

/// Recording-time driver for the opt-in screen-OCR feature (spec §7).
///
/// `ScreenContextStage` knows how to capture + OCR one snapshot and append the
/// text to the per-meeting sidecar, but something has to *invoke* it while a
/// meeting records. This driver owns that cadence: when the feature is enabled it
/// captures one snapshot, appends it (de-duplicated by the store), waits the
/// cadence interval, and repeats until ``stop()``. It runs in the helper process
/// alongside the audio recorder, so the sidecar is already on disk by the time
/// the post-hoc pipeline reads it via ``ScreenContextStore/combinedText(folder:)``.
///
/// Gating (I4): when the opt-in toggle is OFF, ``start(folder:)`` returns without
/// launching any loop, so the screen is never read and the
/// Screen-Recording-permission prompt is never triggered. The stage *also*
/// self-gates, so an enabled-then-disabled flip mid-recording stops writing too.
@MainActor
public final class ScreenContextRecorder {
    private let stage: ScreenContextStage
    private let cadence: Duration
    private let isEnabled: @Sendable () -> Bool
    private let onCaptureError: @Sendable (any Error) -> Void
    private var task: Task<Void, Never>?

    public init(
        stage: ScreenContextStage,
        cadence: Duration = .seconds(20),
        isEnabled: @escaping @Sendable () -> Bool = { UserDefaultsScreenOCRStore.shared.isEnabled() },
        onCaptureError: @escaping @Sendable (any Error) -> Void = { error in
            NSLog("Nexus meetings screen-OCR capture failed: %@", String(describing: error))
        }
    ) {
        self.stage = stage
        self.cadence = cadence
        self.isEnabled = isEnabled
        self.onCaptureError = onCaptureError
    }

    /// Begin periodically capturing screen context into `folder`. No-op (no loop,
    /// no screen read) when the opt-in toggle is OFF. Replaces any prior loop.
    public func start(folder: URL) {
        stop()
        guard isEnabled() else { return }

        let stage = stage
        let cadence = cadence
        let onCaptureError = onCaptureError
        task = Task { [weak self] in
            // Capture once up front so a short meeting still gets context, then
            // settle into the cadence.
            while Task.isCancelled == false {
                guard self?.isEnabled() == true else { return }
                do {
                    _ = try await stage.capture(folder: folder)
                } catch is CancellationError {
                    return
                } catch {
                    // A *thrown* capture means the capture path itself failed.
                    // Surface it via the handler either way, then decide whether
                    // to keep going. Screen-OCR is optional enrichment, never
                    // load-bearing for the transcript, so a single bad frame must
                    // not kill OCR for the whole meeting.
                    onCaptureError(error)
                    if Self.isFatalCaptureError(error) {
                        // Unrecoverable (no capture path on this platform, or the
                        // Screen-Recording TCC grant was declined): stopping is
                        // correct — retrying every cadence would only re-prompt /
                        // re-fail forever.
                        return
                    }
                    // Transient (display momentarily unshareable, OCR hiccup):
                    // fall through to the cadence sleep and try the next frame.
                }
                if Task.isCancelled { return }
                try? await Task.sleep(for: cadence)
            }
        }
    }

    /// Distinguish a truly unrecoverable capture failure (where stopping the loop
    /// is correct) from a transient per-frame error (where the next cadence tick
    /// may succeed). The only unrecoverable case here is `unsupportedPlatform`
    /// (non-macOS — no capture path will ever exist). Everything else is treated
    /// as transient so OCR survives a bad frame: a momentarily unshareable display
    /// (`noShareableContent`), an OCR/Vision hiccup, and even a denied
    /// Screen-Recording grant (macOS won't re-prompt after the first denial, so
    /// retrying is harmless and lets OCR recover if the user grants mid-meeting).
    private static func isFatalCaptureError(_ error: any Error) -> Bool {
        if let captureError = error as? ScreenContextCaptureError {
            switch captureError {
            case .unsupportedPlatform:
                return true
            case .noShareableContent:
                return false
            }
        }
        return false
    }

    /// Stop the capture loop. Idempotent.
    public func stop() {
        task?.cancel()
        task = nil
    }
}
