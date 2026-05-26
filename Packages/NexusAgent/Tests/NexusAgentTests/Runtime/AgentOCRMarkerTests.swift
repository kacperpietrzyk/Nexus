import Foundation
import Testing

@testable import NexusAgent

@Suite("AgentOCRMarker")
struct AgentOCRMarkerTests {

    @Test("No marker — content passes through untouched")
    func noMarkerPassthrough() {
        let s = "describe the image please"
        #expect(AgentOCRMarker.userFacingText(s) == s)
    }

    @Test("Clean single OCR block + user text — block stripped")
    func cleanSingleBlock() {
        let content =
            AgentOCRMarker.ocrBlock(for: "Buy milk") + "\n" + "describe the image"
        #expect(AgentOCRMarker.userFacingText(content) == "describe the image")
    }

    @Test("Multi-line OCR text kept intact then fully stripped")
    func multiLineOCRText() {
        let ocr = "Line 1\nLine 2\nLine 3"
        let content = AgentOCRMarker.ocrBlock(for: ocr) + "\n" + "what is this?"
        #expect(AgentOCRMarker.userFacingText(content) == "what is this?")
    }

    @Test("Low-confidence hint + user text — hint stripped")
    func lowConfidenceHint() {
        let content = AgentOCRMarker.lowConfidenceHint + "\n" + "summarise it"
        #expect(AgentOCRMarker.userFacingText(content) == "summarise it")
    }

    @Test("Multiple leading blocks (OCR + low-confidence) all stripped")
    func multipleBlocks() {
        let content =
            AgentOCRMarker.ocrBlock(for: "Receipt total 42")
            + "\n" + AgentOCRMarker.lowConfidenceHint
            + "\n" + "compare these two"
        #expect(AgentOCRMarker.userFacingText(content) == "compare these two")
    }

    @Test("Image-only turn (no user text) — returns empty string")
    func imageOnlyTurn() {
        let content = AgentOCRMarker.ocrBlock(for: "Some text") + "\n"
        #expect(AgentOCRMarker.userFacingText(content).isEmpty)
    }

    @Test("Malformed marker (prefix, no suffix) — left untouched")
    func malformedMarkerPassthrough() {
        let content = AgentOCRMarker.ocrBlockPrefix + "no closing bracket here"
        #expect(AgentOCRMarker.userFacingText(content) == content)
    }

    @Test("Legit user text merely containing the phrase mid-string — untouched")
    func phraseNotAtPrefix() {
        let s = "why did you say [Image content extracted via OCR:\n] earlier?"
        #expect(AgentOCRMarker.userFacingText(s) == s)
    }

    @Test("Producer round-trip: ocrBlock then strip recovers the user message")
    func producerRoundTrip() {
        let msg = "what does the sign say?"
        let persisted = AgentOCRMarker.ocrBlock(for: "STOP\nYIELD") + "\n" + msg
        #expect(AgentOCRMarker.userFacingText(persisted) == msg)
    }
}
