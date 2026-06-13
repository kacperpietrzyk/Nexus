import Foundation
import SwiftData
import Testing

@testable import NexusAgentTools
@testable import NexusCore

@Suite("labels write")
struct LabelsWriteToolsTests {
    @Test("labels.create makes a free user label")
    @MainActor
    func create() async throws {
        let (context, container, _) = try await InMemoryAgentContext.make()
        _ = container
        let out = try await LabelsCreateTool().call(args: .object(["name": .string("waiting")]), context: context)
        #expect(out["name"]?.stringValue == "waiting")
        #expect(out["group"]?.stringValue == "free")
        #expect(out["is_system"]?.boolValue == false)
    }

    @Test("labels.update renames a user label")
    @MainActor
    func update() async throws {
        let (context, container, _) = try await InMemoryAgentContext.make()
        _ = container
        let label = try context.labelRepository.create(name: "old", group: .free, isSystem: false)
        let out = try await LabelsUpdateTool().call(
            args: .object(["label_id": .string(label.id.uuidString), "name": .string("new")]), context: context
        )
        #expect(out["name"]?.stringValue == "new")
    }

    @Test("labels.update rejects a system label")
    @MainActor
    func rejectsSystem() async throws {
        let (context, container, _) = try await InMemoryAgentContext.make()
        _ = container
        let sys = try context.labelRepository.create(name: "bug", group: .domain, isSystem: true)
        await #expect(throws: AgentError.self) {
            _ = try await LabelsUpdateTool().call(
                args: .object(["label_id": .string(sys.id.uuidString), "name": .string("x")]), context: context
            )
        }
    }

    @Test("labels.delete removes a user label")
    @MainActor
    func delete() async throws {
        let (context, container, _) = try await InMemoryAgentContext.make()
        _ = container
        let label = try context.labelRepository.create(name: "tmp", group: .free, isSystem: false)
        _ = try await LabelsDeleteTool().call(args: .object(["label_id": .string(label.id.uuidString)]), context: context)
        #expect(try context.labelRepository.find(id: label.id)?.deletedAt != nil)
    }

    @Test("labels.delete rejects a system label")
    @MainActor
    func deleteRejectsSystem() async throws {
        let (context, container, _) = try await InMemoryAgentContext.make()
        _ = container
        let sys = try context.labelRepository.create(name: "bug", group: .domain, isSystem: true)
        await #expect(throws: AgentError.self) {
            _ = try await LabelsDeleteTool().call(
                args: .object(["label_id": .string(sys.id.uuidString)]), context: context
            )
        }
        #expect(try context.labelRepository.find(id: sys.id)?.deletedAt == nil)
    }

    @Test("labels.update rejects a non-system domain label (group arm)")
    @MainActor
    func rejectsNonSystemDomain() async throws {
        let (context, container, _) = try await InMemoryAgentContext.make()
        _ = container
        // isSystem == false isolates the `group != .free` arm of the guard.
        let domain = try context.labelRepository.create(name: "infra", group: .domain, isSystem: false)
        await #expect(throws: AgentError.self) {
            _ = try await LabelsUpdateTool().call(
                args: .object(["label_id": .string(domain.id.uuidString), "name": .string("x")]), context: context
            )
        }
    }
}
