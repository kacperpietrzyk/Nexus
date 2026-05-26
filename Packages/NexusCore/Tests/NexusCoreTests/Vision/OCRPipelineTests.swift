import Foundation
import Testing

@testable import NexusCore

#if canImport(Vision)
@Suite("OCRPipeline")
struct OCRPipelineTests {
    @Test("ocrExtractsTextFromTaskListScreenshot")
    func ocrExtractsTextFromTaskListScreenshot() async throws {
        let url = try #require(
            Bundle.module.url(forResource: "task-list-screenshot", withExtension: "png"),
            "Fixture 'task-list-screenshot.png' missing from the NexusCoreTests bundle (check Package.swift .process(\"Vision/Fixtures\"))."
        )

        let imageData = try Data(contentsOf: url)
        let pipeline = OCRPipeline()
        let result = try await pipeline.extractText(from: imageData)

        #expect(result.lineCount > 0, "Expected at least one recognised line")
        #expect(!result.text.isEmpty, "Expected non-empty recognised text")
        #expect(result.confidence > 0.5, "Expected mean confidence > 0.5, got \(result.confidence)")
        #expect(result.text.localizedCaseInsensitiveContains("milk"))
    }

    @Test("ocrReturnsEmptyForNonImageData")
    func ocrReturnsEmptyForNonImageData() async throws {
        let garbage = Data([0x00, 0x01])
        let pipeline = OCRPipeline()
        await #expect(throws: (any Error).self) {
            try await pipeline.extractText(from: garbage)
        }
    }
}
#endif
