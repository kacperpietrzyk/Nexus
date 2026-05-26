import Foundation
import NexusAI
import NexusCore
import Testing

@testable import NexusAgent

#if canImport(Vision)
import CoreGraphics
import CoreText
import ImageIO

@MainActor
@Suite("AgentRuntimeOCR", .serialized)
struct AgentRuntimeOCRTests {
    // MARK: - hasImageProvider

    @Test("hasImageProvider is true when OCRPipeline is injected")
    func hasImageProviderIsTrueWithPipeline() throws {
        let harness = try RuntimeHarness.make(
            tools: [],
            scripts: [],
            ocrPipeline: OCRPipeline()
        )
        #expect(harness.runtime.hasImageProvider == true)
    }

    @Test("imageAttachmentDeferralReason is nil when an OCRPipeline is injected (banner hidden)")
    func imageAttachmentDeferralReasonIsNilWithPipeline() throws {
        let harness = try RuntimeHarness.make(
            tools: [],
            scripts: [],
            ocrPipeline: OCRPipeline()
        )
        #expect(harness.runtime.imageAttachmentDeferralReason == nil)
    }

    @Test("hasImageProvider is false when no OCRPipeline is injected")
    func hasImageProviderIsFalseWithoutPipeline() throws {
        let harness = try RuntimeHarness.make(
            tools: [],
            scripts: [],
            ocrPipeline: nil
        )
        #expect(harness.runtime.hasImageProvider == false)
    }

    // MARK: - OCR injection into prompt

    @Test("image attachment text is extracted via OCR and injected into the prompt")
    func ocrTextIsInjectedIntoPrompt() async throws {
        let imageData = try #require(
            makeImageFixtureData(text: "Buy milk"),
            "CGContext PNG generation failed."
        )
        let dataURL = "data:image/png;base64,\(imageData.base64EncodedString())"

        let harness = try RuntimeHarness.make(
            tools: [],
            scripts: [.text("done")],
            ocrPipeline: OCRPipeline()
        )
        let threadID = try harness.threadStore.create(title: "ocr-test")

        let response = try await harness.runtime.runTurn(
            AgentTurnRequest(
                threadID: threadID,
                userMessage: "what does the image say",
                attachments: [dataURL],
                scope: "global"
            )
        )

        #expect(response.haltReason == .completed)

        let prompt = try #require(harness.provider.prompts.first)
        // The OCR block must appear — either high-confidence extraction or the
        // low-confidence fallback hint; both satisfy the plan contract.
        let hasOCRBlock =
            prompt.contains("Image content extracted via OCR")
            || prompt.contains(
                "Image attached — text extraction confidence low; describe what you see if needed."
            )
        #expect(hasOCRBlock, "Expected OCR block in prompt; got: \(prompt.prefix(400))")

        // If high-confidence, the extracted text should contain "Buy milk" (case-insensitive).
        if prompt.contains("Image content extracted via OCR") {
            #expect(
                prompt.localizedCaseInsensitiveContains("Buy milk"),
                "High-confidence OCR block missing 'Buy milk'; prompt: \(prompt.prefix(400))"
            )
        }
    }

    @Test("OCR block is intentionally persisted into stored user-history message for multi-turn context retention")
    func ocrBlockIsPersistedIntoStoredMessageForMultiTurnContext() async throws {
        let imageData = try #require(makeImageFixtureData(text: "Buy milk"))
        let dataURL = "data:image/png;base64,\(imageData.base64EncodedString())"

        let harness = try RuntimeHarness.make(
            tools: [],
            scripts: [.text("done")],
            ocrPipeline: OCRPipeline()
        )
        let threadID = try harness.threadStore.create(title: "ocr-stored")

        _ = try await harness.runtime.runTurn(
            AgentTurnRequest(
                threadID: threadID,
                userMessage: "describe the image",
                attachments: [dataURL],
                scope: "global"
            )
        )

        let stored = try harness.messageStore.slidingWindow(threadID: threadID, last: 10)
        let userMessage = try #require(stored.first(where: { $0.role == .user }))
        let storedContent = userMessage.content
        // Design A (ratified): the runtime prepends the OCR block to effectiveUserMessage
        // before persisting, so later context-window turns still see the image content.
        // MessageBubbleView rendering of this OCR-prefixed content is a known separate
        // follow-up and is NOT addressed here.
        let hasOCRBlock =
            storedContent.contains("Image content extracted via OCR")
            || storedContent.contains(
                "Image attached — text extraction confidence low; describe what you see if needed."
            )
        #expect(hasOCRBlock, "Design A: stored message must contain OCR block or fallback hint; got: \(storedContent.prefix(200))")
        // The original user text must also be present alongside the OCR block.
        #expect(
            storedContent.contains("describe the image"),
            "Stored message must preserve original user text alongside OCR block; got: \(storedContent.prefix(200))"
        )
        // The OCR block must also reach the built prompt.
        let prompt = try #require(harness.provider.prompts.first)
        let hasOCRInPrompt =
            prompt.contains("Image content extracted via OCR")
            || prompt.contains(
                "Image attached — text extraction confidence low; describe what you see if needed."
            )
        #expect(hasOCRInPrompt, "OCR block must also appear in the built prompt; got: \(prompt.prefix(400))")
    }

    @Test("turn with OCRPipeline and valid image completes successfully and calls the provider once")
    func turnWithOCRPipelineCompletesAndCallsProvider() async throws {
        let imageData = try #require(makeImageFixtureData(text: "Buy milk"))
        let dataURL = "data:image/png;base64,\(imageData.base64EncodedString())"

        let harness = try RuntimeHarness.make(
            tools: [],
            scripts: [.text("Got it.")],
            ocrPipeline: OCRPipeline()
        )
        let threadID = try harness.threadStore.create(title: "ocr-completes")

        let response = try await harness.runtime.runTurn(
            AgentTurnRequest(
                threadID: threadID,
                userMessage: "read this",
                attachments: [dataURL],
                scope: "global"
            )
        )

        #expect(response.haltReason == .completed)
        #expect(response.finalAssistantContent == "Got it.")
        #expect(harness.provider.callCount == 1)
    }
}

// MARK: - PNG fixture generator

/// Renders a small white-on-black PNG with the given `text` using Core Graphics and
/// Core Text. Returns `nil` only if `CGContext` construction fails (should never happen
/// in a unit-test environment).
private func makeImageFixtureData(text: String) -> Data? {
    let width = 400
    let height = 80
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

    guard
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        )
    else {
        return nil
    }

    // White background
    context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))

    // Black text via Core Text
    let font = CTFontCreateWithName("Helvetica-Bold" as CFString, 36, nil)
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: CGColor(red: 0, green: 0, blue: 0, alpha: 1),
    ]
    let attrString = NSAttributedString(string: text, attributes: attributes)
    let line = CTLineCreateWithAttributedString(attrString)

    context.textPosition = CGPoint(x: 20, y: 20)
    CTLineDraw(line, context)

    guard let cgImage = context.makeImage() else { return nil }

    let mutableData = NSMutableData()
    guard
        let destination = CGImageDestinationCreateWithData(
            mutableData,
            "public.png" as CFString,
            1,
            nil
        )
    else {
        return nil
    }
    CGImageDestinationAddImage(destination, cgImage, nil)
    guard CGImageDestinationFinalize(destination) else { return nil }

    return mutableData as Data
}
#endif
