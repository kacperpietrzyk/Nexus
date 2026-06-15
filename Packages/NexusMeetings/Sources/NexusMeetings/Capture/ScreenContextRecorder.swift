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
                    // A *thrown* capture means the capture path itself failed
                    // (Screen-Recording permission denied, or no display) rather
                    // than merely "no text found" (which returns nil). Surface it
                    // and stop the loop instead of silently re-prompting every
                    // cadence — screen-OCR is optional enrichment, never
                    // load-bearing for the transcript.
                    onCaptureError(error)
                    return
                }
                if Task.isCancelled { return }
                try? await Task.sleep(for: cadence)
            }
        }
    }

    /// Stop the capture loop. Idempotent.
    public func stop() {
        task?.cancel()
        task = nil
    }
}
