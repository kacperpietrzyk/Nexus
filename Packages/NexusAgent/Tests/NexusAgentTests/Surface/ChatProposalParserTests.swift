import Foundation
import NexusCore  // JSONValue
import Testing

@testable import NexusAgent

@Suite struct ChatProposalParserTests {
    @Test func plainTextHasNoProposalAndUnchangedDisplay() {
        let r = ChatProposalParser.parse("Here are your 3 tasks due today.")
        #expect(r.proposal == nil)
        #expect(r.displayText == "Here are your 3 tasks due today.")
    }

    @Test func validBlockProducesProposalAndStripsItFromDisplay() {
        let text = """
            Sure — I'll add that.
            ```nexus-proposal
            {"rationale":"Create the task you asked for","mutations":[{"tool":"tasks.create","args":{"title":"Email client"}}]}
            ```
            """
        let r = ChatProposalParser.parse(text)
        #expect(r.proposal?.mutations.count == 1)
        #expect(r.proposal?.mutations.first?.toolName == "tasks.create")
        #expect(r.displayText.contains("nexus-proposal") == false)  // raw block stripped (no leak)
        #expect(r.displayText.contains("I'll add that"))
    }

    @Test func malformedBlockStrippedWithNilProposal() {
        let text = "Done.\n```nexus-proposal\nnot json\n```"
        let r = ChatProposalParser.parse(text)
        #expect(r.proposal == nil)
        #expect(r.displayText.contains("nexus-proposal") == false)  // still stripped, no raw leak
        #expect(r.displayText.contains("Done."))
    }

    @Test func onlyWriteToolsAreAllowedInMutations() {
        // A block trying to express a read or unknown tool yields no mutation for it.
        let text =
            "```nexus-proposal\n{\"rationale\":\"x\",\"mutations\":[{\"tool\":\"search.global\",\"args\":{}}]}\n```"
        let r = ChatProposalParser.parse(text)
        #expect(r.proposal == nil || r.proposal?.mutations.isEmpty == true)
    }

    // MARK: - Mislabeled fence tolerance (12B emits ```json, not ```nexus-proposal)

    /// The on-device 12B (gemma4) fences the proposal as ```json instead of
    /// ```nexus-proposal. A body that decodes to the proposal shape must still be
    /// parsed and stripped so it never leaks as raw JSON into the chat.
    @Test func jsonFencedProposalIsParsedAndStripped() {
        let text = """
            Sure — I'll add that.
            ```json
            {"rationale":"Create the task","mutations":[{"tool":"tasks.create","args":{"title":"Email client"}}]}
            ```
            """
        let r = ChatProposalParser.parse(text)
        #expect(r.proposal?.mutations.first?.toolName == "tasks.create")
        #expect(r.displayText.contains("tasks.create") == false)  // raw JSON stripped, no leak
        #expect(r.displayText.contains("I'll add that"))
    }

    /// The exact observed bug: a json-fenced proposal with an invalid tool
    /// (`activity.get`) yields no proposal, but the raw block must NOT leak.
    @Test func jsonFencedInvalidToolStrippedNoLeak() {
        let text = """
            ```json
            {"rationale":"fetch meetings","mutations":[{"tool":"activity.get","args":{"item_id":"1234567890","limit":10}}]}
            ```
            """
        let r = ChatProposalParser.parse(text)
        #expect(r.proposal == nil)
        #expect(r.displayText.contains("activity.get") == false)  // no raw leak
        #expect(r.displayText.contains("mutations") == false)
    }

    /// Safety: an ordinary json code block the assistant shows the user (not a
    /// proposal shape) must be left untouched in the display.
    @Test func ordinaryJSONCodeBlockIsNotStripped() {
        let text = "Here is an example config:\n```json\n{\"port\":8080,\"debug\":true}\n```"
        let r = ChatProposalParser.parse(text)
        #expect(r.proposal == nil)
        #expect(r.displayText.contains("\"port\""))  // legitimate code block preserved
        #expect(r.displayText.contains("8080"))
    }
}
