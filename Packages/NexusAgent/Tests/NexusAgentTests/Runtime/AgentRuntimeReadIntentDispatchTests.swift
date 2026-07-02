import Foundation
import NexusAgentTools
import NexusCore
import Testing

@testable import NexusAgent

// The on-device 12B does not emit native structured tool calls; it wraps a
// (correct) read intent in the ONLY structured format the prompt teaches — the
// `nexus-proposal` block — or, when taught, a `{"type":"tool_call"}` envelope it
// tends to fence as ```json. The runtime must dispatch that read intent in EITHER
// shape (gated by the tool being in the request allowlist, so writes still route
// to the confirm card), instead of leaking the raw JSON to the chat.
@MainActor
@Suite(.serialized)
struct AgentRuntimeReadIntentDispatchTests {
    /// A read tool that records whether it ran and returns canned data.
    private final class RecordingReadTool: AgentTool, @unchecked Sendable {
        let name = "projects.list"
        let description = "List projects."
        let inputSchema: JSONSchema = .object(properties: [:], required: [])
        private(set) var callCount = 0
        func call(args: JSONValue, context: AgentContext) async throws -> JSONValue {
            callCount += 1
            return .object(["projects": .array([.string("Nexus"), .string("Softinet")])])
        }
    }

    private static let projectsListProposal = """
        ```json
        {
          "rationale": "Retrieves the list of active projects from the Nexus app.",
          "mutations": [
            { "tool": "projects.list", "args": { "status": "active" } }
          ]
        }
        ```
        """

    @Test("a read intent wrapped in a proposal block is dispatched, and the follow-up answer surfaces")
    func proposalWrappedReadIsDispatchedThenAnswered() async throws {
        let tool = RecordingReadTool()
        let harness = try RuntimeHarness.make(
            tools: [tool],
            scripts: [
                .text(Self.projectsListProposal),
                .text("You have 2 active projects: Nexus and Softinet."),
            ]
        )
        let threadID = try harness.threadStore.create(title: "proposal-read")

        let response = try await harness.runtime.runTurn(
            AgentTurnRequest(
                threadID: threadID,
                userMessage: "jakie mam aktualnie aktywne projekty?",
                scope: "assistant",
                toolAllowlist: ["projects.list"]
            )
        )

        // The read tool actually ran, and the raw proposal JSON never became the answer.
        #expect(tool.callCount == 1)
        #expect(response.finalAssistantContent == "You have 2 active projects: Nexus and Softinet.")
        #expect(harness.provider.callCount == 2)
    }

    @Test("a fenced tool_call envelope is dispatched")
    func fencedToolCallEnvelopeIsDispatched() async throws {
        let tool = RecordingReadTool()
        let harness = try RuntimeHarness.make(
            tools: [tool],
            scripts: [
                .text("```json\n{\"type\":\"tool_call\",\"name\":\"projects.list\",\"input\":{}}\n```"),
                .text("Nexus and Softinet."),
            ]
        )
        let threadID = try harness.threadStore.create(title: "envelope-read")

        let response = try await harness.runtime.runTurn(
            AgentTurnRequest(
                threadID: threadID,
                userMessage: "list projects",
                scope: "assistant",
                toolAllowlist: ["projects.list"]
            )
        )

        #expect(tool.callCount == 1)
        #expect(response.finalAssistantContent == "Nexus and Softinet.")
    }

    @Test("a proposal for a NON-allowlisted write is NOT dispatched and stays a final proposal")
    func writeProposalIsNotAutoDispatched() async throws {
        let tool = RecordingReadTool()
        let writeProposal = """
            ```json
            {
              "rationale": "Create a task.",
              "mutations": [
                { "tool": "tasks.create", "args": { "title": "Buy milk" } }
              ]
            }
            ```
            """
        let harness = try RuntimeHarness.make(
            tools: [tool],
            scripts: [.text(writeProposal)]
        )
        let threadID = try harness.threadStore.create(title: "write-proposal")

        let response = try await harness.runtime.runTurn(
            AgentTurnRequest(
                threadID: threadID,
                userMessage: "add a task to buy milk",
                scope: "assistant",
                toolAllowlist: ["projects.list"]
            )
        )

        // tasks.create is a write (not in the allowlist): the runtime must leave the
        // proposal block intact for the VM-layer confirm card, and dispatch nothing.
        #expect(tool.callCount == 0)
        #expect(harness.provider.callCount == 1)
        #expect(response.finalAssistantContent?.contains("tasks.create") == true)
    }
}
