import Foundation
import NexusCore

#if canImport(ScreenCaptureKit)
import ScreenCaptureKit
#endif

#if canImport(CoreGraphics)
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
#endif

/// Captures a single still frame of the screen content shared into the active
/// meeting, runs on-device OCR over it, and returns ONLY the extracted text.
///
/// Privacy stance (spec §7.2 / I4): the captured pixels never leave this call.
/// The image is OCR'd in-memory and discarded; nothing is written to disk and no
/// frame is returned. Callers only ever see text, which keeps the screen-OCR
/// feature text-only by construction.
///
/// Cadence is on-demand / on-shared-window-change (§7.1), never continuous — the
/// caller decides when to invoke this; there is no internal timer.
public protocol ScreenContextCapturing: Sendable {
    /// Capture the current shared screen content and return the recognised text,
    /// or `nil` when nothing usable was found (no shareable content, OCR empty).
    ///
    /// - Throws: when the capture path itself fails (permission denied, no
    ///   display). A throw is recoverable by the caller — screen-OCR is an
    ///   optional enrichment, never load-bearing for the transcript.
    func captureText() async throws -> String?
}

/// Errors surfaced by the ScreenCaptureKit-backed implementation.
public enum ScreenContextCaptureError: Error, Sendable, Equatable {
    /// ScreenCaptureKit reported no shareable display to capture.
    case noShareableContent
    /// The platform does not provide a screen-capture path (non-macOS).
    case unsupportedPlatform
}

#if canImport(ScreenCaptureKit) && canImport(Vision)
import Vision

/// ScreenCaptureKit + Vision implementation of ``ScreenContextCapturing``.
///
/// Uses `SCScreenshotManager.captureImage` for an on-demand single still (no
/// `SCStream`, so no continuous frame pipeline). The grabbed `CGImage` is encoded
/// to in-memory PNG data, handed to ``OCRPipeline``, then dropped when this method
/// returns. The Screen Recording TCC grant is requested by the system the first
/// time `SCShareableContent.current` / `captureImage` runs — that runtime prompt
/// is a manual smoke (it cannot be exercised in CI).
public final class ScreenshotScreenContextCapture: ScreenContextCapturing, @unchecked Sendable {
    private let ocr: OCRPipeline
    private let languages: [String]

    public init(ocr: OCRPipeline = OCRPipeline(), languages: [String] = ["en-US", "pl-PL"]) {
        self.ocr = ocr
        self.languages = languages
    }

    public func captureText() async throws -> String? {
        let imageData = try await captureImageData()
        let result = try await ocr.extractText(from: imageData, languages: languages)
        let trimmed = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
        // `imageData` and the underlying CGImage go out of scope here and are
        // released — nothing is persisted (I4: zero saved frames).
    }

    private func captureImageData() async throws -> Data {
        let content = try await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: true
        )
        guard let display = content.displays.first else {
            throw ScreenContextCaptureError.noShareableContent
        }

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let configuration = SCStreamConfiguration()
        configuration.width = display.width
        configuration.height = display.height

        let image = try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: configuration
        )
        guard let data = Self.pngData(from: image) else {
            throw ScreenContextCaptureError.noShareableContent
        }
        return data
    }

    private static func pngData(from image: CGImage) -> Data? {
        let mutableData = NSMutableData()
        guard
            let destination = CGImageDestinationCreateWithData(
                mutableData,
                UTType.png.identifier as CFString,
                1,
                nil
            )
        else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            return nil
        }
        return mutableData as Data
    }
}
#endif
