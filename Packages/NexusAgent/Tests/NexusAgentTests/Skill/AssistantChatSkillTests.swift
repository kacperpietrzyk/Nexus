import Foundation
import Testing

@testable import NexusAgent

@Suite
struct AssistantChatSkillTests {
    @Test func macConfigIsReadOnlyToolCalling() {
        let c = AssistantChatConfig.mac
        #expect(c.allowsToolCalling == true)
        #expect(c.maxIterations == 3)
        #expect(c.toolNames.isEmpty == false)
        #expect(c.toolNames.contains("tasks.create") == false)
        #expect(c.toolNames.contains("tasks.update") == false)
        #expect(c.systemPrompt.contains("nexus-proposal"))
    }

    @Test func iosConfigIsExtractionOnly() {
        let c = AssistantChatConfig.iOS
        #expect(c.allowsToolCalling == false)
        #expect(c.toolNames.isEmpty)
        #expect(c.maxIterations <= 2)
    }

    @Test func macToolNamesAreReadOnly() {
        let writingTools: Set<String> = ["tasks.create", "tasks.update"]
        let macTools = Set(AssistantChatConfig.mac.toolNames)
        #expect(macTools.isDisjoint(with: writingTools))
    }

    @Test func macSystemPromptContainsProposalSchema() {
        let prompt = AssistantChatConfig.mac.systemPrompt
        // Must contain the fenced block marker the parser expects.
        #expect(prompt.contains("nexus-proposal"))
        // Must describe the expected JSON keys.
        #expect(prompt.contains("rationale"))
        #expect(prompt.contains("mutations"))
    }
}
