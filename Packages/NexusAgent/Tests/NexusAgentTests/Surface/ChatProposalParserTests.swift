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
}
