import Foundation

/// Optional, opt-in stage that captures the shared-window screen, OCRs it, and
/// appends ONLY the recognised text to the per-meeting screen-context sidecar
/// (spec §7). It runs during recording on-demand / on-shared-window-change
/// (§7.1) — never continuously and never inside the post-hoc processing pipeline.
///
/// Gating (I4): when the opt-in toggle is OFF, ``capture(folder:)`` returns
/// immediately without ever invoking the capturer, so no screen pixels are read
/// and nothing is written. When ON, the captured image is OCR'd inside the
/// capturer and discarded there — this stage only ever sees text (§7.2).
public struct ScreenContextStage: Sendable {
    private let capture: any ScreenContextCapturing
    private let store: ScreenContextStore
    private let isEnabled: @Sendable () -> Bool

    public init(
        capture: any ScreenContextCapturing,
        store: ScreenContextStore = ScreenContextStore(),
        isEnabled: @escaping @Sendable () -> Bool = { UserDefaultsScreenOCRStore.shared.isEnabled() }
    ) {
        self.capture = capture
        self.store = store
        self.isEnabled = isEnabled
    }

    /// Capture one screen snapshot for the recording in `folder`. No-op (and the
    /// capturer is never touched) when the opt-in toggle is OFF. Returns the text
    /// that was appended, or `nil` when disabled / nothing recognised.
    ///
    /// - Returns: the appended OCR text, or `nil` (disabled or empty).
    @discardableResult
    public func capture(folder: URL) async throws -> String? {
        guard isEnabled() else { return nil }
        guard let text = try await capture.captureText() else { return nil }
        try store.append(text: text, folder: folder)
        return text
    }
}
