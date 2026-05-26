import Foundation
import NexusCore

#if canImport(Vision)

// OCR helpers extracted from `AgentRuntime` to keep file/type sizes within lint budgets.
extension AgentRuntime {
    /// Run OCR on each attached image data URL and return formatted text blocks.
    ///
    /// Each block is either:
    /// - `"[Image content extracted via OCR:\n<text>\n]"` for high-confidence results, or
    /// - `"[Image attached — text extraction confidence low; describe what you see if needed.]"`
    ///   for low-confidence / empty results and Vision errors.
    func extractOCRBlocks(
        from attachments: [String],
        using pipeline: OCRPipeline
    ) async -> [String] {
        var blocks: [String] = []
        for attachment in attachments {
            guard let payload = try? AgentImageCapture.payload(fromDataURL: attachment) else {
                blocks.append(AgentRuntime.ocrLowConfidenceHint)
                continue
            }
            do {
                let result = try await pipeline.extractText(from: payload.data)
                if result.confidence < 0.5 || result.text.isEmpty {
                    blocks.append(AgentRuntime.ocrLowConfidenceHint)
                } else {
                    blocks.append(AgentOCRMarker.ocrBlock(for: result.text))
                }
            } catch {
                blocks.append(AgentRuntime.ocrLowConfidenceHint)
            }
        }
        return blocks
    }

    nonisolated static let ocrLowConfidenceHint = AgentOCRMarker.lowConfidenceHint
}

#endif
