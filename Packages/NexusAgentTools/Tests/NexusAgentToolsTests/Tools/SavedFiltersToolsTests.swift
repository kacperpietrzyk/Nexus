import Foundation
import SwiftData
import Testing

@testable import NexusAgentTools
@testable import NexusCore

@Suite("saved filters")
struct SavedFiltersToolsTests {
    @Test("create then list returns the filter")
    @MainActor
    func createAndList() async throws {
        let (context, container, _) = try await InMemoryAgentContext.make()
        _ = container
        _ = try context.savedFilterRepository.create(name: "Overdue", definition: .overdue)
        let out = try await SavedFiltersListTool().call(args: .object([:]), context: context)
        #expect(out["filters"]?.arrayValue?.first?["name"]?.stringValue == "Overdue")
    }

    @Test("create tool decodes the definition JSON and persists it")
    @MainActor
    func createToolRoundTripsDefinition() async throws {
        let (context, container, _) = try await InMemoryAgentContext.make()
        _ = container
        // Generate the arg symmetrically so the test never guesses the enum's
        // synthesized JSON shape; encode/decode are inverse round-trips.
        let defValue = try TasksToolJSON.encode(FilterDefinition.byTag("work"))
        let out = try await SavedFiltersCreateTool().call(
            args: .object(["name": .string("Work"), "definition": defValue]),
            context: context
        )
        #expect(out["name"]?.stringValue == "Work")
        let idString = try #require(out["id"]?.stringValue)
        let id = try #require(UUID(uuidString: idString))
        let persisted = try #require(try context.savedFilterRepository.find(id))
        #expect(try persisted.decodedDefinition() == .byTag("work"))
    }

    @Test("update tool replaces name and definition")
    @MainActor
    func updateToolReplacesFields() async throws {
        let (context, container, _) = try await InMemoryAgentContext.make()
        _ = container
        let filter = try context.savedFilterRepository.create(name: "Old", definition: .byTag("old"))
        let defValue = try TasksToolJSON.encode(FilterDefinition.byTag("new"))
        let out = try await SavedFiltersUpdateTool().call(
            args: .object([
                "filter_id": .string(filter.id.uuidString),
                "name": .string("New"),
                "definition": defValue,
            ]),
            context: context
        )
        #expect(out["name"]?.stringValue == "New")
        let persisted = try #require(try context.savedFilterRepository.find(filter.id))
        #expect(persisted.name == "New")
        #expect(try persisted.decodedDefinition() == .byTag("new"))
    }

    @Test("update tool with only name leaves the definition intact")
    @MainActor
    func updateToolNameOnly() async throws {
        let (context, container, _) = try await InMemoryAgentContext.make()
        _ = container
        let filter = try context.savedFilterRepository.create(name: "Old", definition: .byTag("keep"))
        _ = try await SavedFiltersUpdateTool().call(
            args: .object([
                "filter_id": .string(filter.id.uuidString),
                "name": .string("Renamed"),
            ]),
            context: context
        )
        let persisted = try #require(try context.savedFilterRepository.find(filter.id))
        #expect(persisted.name == "Renamed")
        #expect(try persisted.decodedDefinition() == .byTag("keep"))
    }

    @Test("update tool with only definition leaves the name intact")
    @MainActor
    func updateToolDefinitionOnly() async throws {
        let (context, container, _) = try await InMemoryAgentContext.make()
        _ = container
        let filter = try context.savedFilterRepository.create(name: "Keep", definition: .byTag("old"))
        let defValue = try TasksToolJSON.encode(FilterDefinition.byTag("new"))
        _ = try await SavedFiltersUpdateTool().call(
            args: .object([
                "filter_id": .string(filter.id.uuidString),
                "definition": defValue,
            ]),
            context: context
        )
        let persisted = try #require(try context.savedFilterRepository.find(filter.id))
        #expect(persisted.name == "Keep")
        #expect(try persisted.decodedDefinition() == .byTag("new"))
    }

    @Test("create tool stores a custom icon when provided")
    @MainActor
    func createToolStoresCustomIcon() async throws {
        let (context, container, _) = try await InMemoryAgentContext.make()
        _ = container
        let defValue = try TasksToolJSON.encode(FilterDefinition.unsorted)
        let out = try await SavedFiltersCreateTool().call(
            args: .object([
                "name": .string("Work"),
                "definition": defValue,
                "icon": .string("briefcase"),
            ]),
            context: context
        )
        #expect(out["icon"]?.stringValue == "briefcase")
        let idString = try #require(out["id"]?.stringValue)
        let id = try #require(UUID(uuidString: idString))
        let persisted = try #require(try context.savedFilterRepository.find(id))
        #expect(persisted.icon == "briefcase")
    }

    @Test("update tool rejects unknown filter id")
    @MainActor
    func updateUnknownIDThrows() async throws {
        let (context, container, _) = try await InMemoryAgentContext.make()
        _ = container
        await #expect {
            _ = try await SavedFiltersUpdateTool().call(
                args: .object(["filter_id": .string(UUID().uuidString), "name": .string("X")]),
                context: context
            )
        } throws: { error in
            guard case .notFound = error as? AgentError else { return false }
            return true
        }
    }

    @Test("delete tool rejects unknown filter id")
    @MainActor
    func deleteUnknownIDThrows() async throws {
        let (context, container, _) = try await InMemoryAgentContext.make()
        _ = container
        await #expect {
            _ = try await SavedFiltersDeleteTool().call(
                args: .object(["filter_id": .string(UUID().uuidString)]),
                context: context
            )
        } throws: { error in
            guard case .notFound = error as? AgentError else { return false }
            return true
        }
    }

    @Test("create tool rejects malformed definition JSON")
    @MainActor
    func createToolRejectsMalformedDefinition() async throws {
        let (context, container, _) = try await InMemoryAgentContext.make()
        _ = container
        await #expect(throws: AgentError.self) {
            _ = try await SavedFiltersCreateTool().call(
                args: .object([
                    "name": .string("Bad"),
                    "definition": .object(["not_a_filter_case": .string("nope")]),
                ]),
                context: context
            )
        }
    }

    @Test("delete tool soft-deletes the filter")
    @MainActor
    func deleteToolRemovesFilter() async throws {
        let (context, container, _) = try await InMemoryAgentContext.make()
        _ = container
        let filter = try context.savedFilterRepository.create(name: "Temp", definition: .unsorted)
        let out = try await SavedFiltersDeleteTool().call(
            args: .object(["filter_id": .string(filter.id.uuidString)]),
            context: context
        )
        #expect(out["deleted"]?.boolValue == true)
        #expect(try context.savedFilterRepository.find(filter.id) == nil)
    }

    @Test("apply returns matching tasks")
    @MainActor
    func apply() async throws {
        let (context, container, _) = try await InMemoryAgentContext.make()
        _ = container
        let filter = try context.savedFilterRepository.create(name: "Tagged", definition: .byTag("inbox"))
        let task = TaskItem(title: "Triage")
        task.tags = ["inbox"]
        context.modelContext.context.insert(task)
        try context.modelContext.context.save()

        let out = try await SavedFiltersApplyTool().call(
            args: .object(["filter_id": .string(filter.id.uuidString)]),
            context: context
        )
        let tasks = try #require(out["tasks"]?.arrayValue)
        #expect(tasks.contains { $0["title"]?.stringValue == "Triage" })
    }

    @Test("apply rejects unknown filter id")
    @MainActor
    func applyUnknownIDThrows() async throws {
        let (context, container, _) = try await InMemoryAgentContext.make()
        _ = container
        let unknownID = UUID()
        await #expect {
            _ = try await SavedFiltersApplyTool().call(
                args: .object(["filter_id": .string(unknownID.uuidString)]),
                context: context
            )
        } throws: { error in
            guard case .notFound = error as? AgentError else { return false }
            return true
        }
    }
}
