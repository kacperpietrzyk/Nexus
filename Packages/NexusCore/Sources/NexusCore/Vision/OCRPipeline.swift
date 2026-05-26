import Foundation

/// A platform-universal result from OCR text extraction.
public struct OCRResult: Sendable {
    /// The recognised text with lines joined by newline characters.
    public let text: String
    /// Mean confidence across all recognised lines (0…1). Zero when nothing was found.
    public let confidence: Float
    /// Number of recognised text lines.
    public let lineCount: Int

    public init(text: String, confidence: Float, lineCount: Int) {
        self.text = text
        self.confidence = confidence
        self.lineCount = lineCount
    }
}

#if canImport(Vision)
import Vision

/// Async actor that wraps `VNRecognizeTextRequest` for single-shot OCR.
///
/// The actor serialises calls so concurrent callers queue rather than race.
/// `handler.perform` is synchronous/blocking but that is acceptable: OCR is
/// single-shot and the actor boundary provides natural back-pressure.
public actor OCRPipeline {
    public init() {}

    /// Extract text from raw PNG/JPEG/HEIF image data.
    ///
    /// - Parameters:
    ///   - imageData: Raw bytes of a supported image format.
    ///   - languages: BCP-47 language hint list (e.g. `["en-US", "pl-PL"]`).
    /// - Returns: `OCRResult` with joined text, mean confidence, and line count.
    /// - Throws: Vision errors when `imageData` cannot be decoded or processed.
    public func extractText(
        from imageData: Data,
        languages: [String] = ["en-US", "pl-PL"]
    ) async throws -> OCRResult {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = languages

        let handler = VNImageRequestHandler(data: imageData, options: [:])
        try handler.perform([request])

        let observations = request.results ?? []
        var lines: [String] = []
        var confidenceSum: Float = 0

        for observation in observations {
            if let candidate = observation.topCandidates(1).first {
                lines.append(candidate.string)
                confidenceSum += candidate.confidence
            }
        }

        let avgConfidence: Float = lines.isEmpty ? 0 : confidenceSum / Float(lines.count)
        return OCRResult(
            text: lines.joined(separator: "\n"),
            confidence: avgConfidence,
            lineCount: lines.count
        )
    }
}
#endif
