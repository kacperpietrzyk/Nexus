import Foundation
import NexusCore
import Testing

@testable import NexusAgentTools

@Suite("TasksInstantiateTemplateTool")
struct TasksInstantiateTemplateToolTests {
    @MainActor
    @Test("instantiates a template into a live task")
    func instantiatesTemplate() async throws {
        let template = TaskItem(title: "Release checklist", tags: ["release"], isTemplate: true)
        let fixture = try await InMemoryAgentContext.make(tasks: [template])

        let result = try await TasksInstantiateTemplateTool().call(
            args: .object(["template_id": .string(template.id.uuidString)]),
            context: fixture.context
        )

        let dto = try TasksToolJSON.decode(TaskDTO.self, from: result)
        #expect(dto.title == "Release checklist")
        #expect(dto.id != template.id.uuidString)
    }

    @MainActor
    @Test("rejects a non-template task")
    func rejectsNonTemplate() async throws {
        let live = TaskItem(title: "Live")
        let fixture = try await InMemoryAgentContext.make(tasks: [live])

        await #expect(throws: AgentError.self) {
            _ = try await TasksInstantiateTemplateTool().call(
                args: .object(["template_id": .string(live.id.uuidString)]),
                context: fixture.context
            )
        }
    }
}
