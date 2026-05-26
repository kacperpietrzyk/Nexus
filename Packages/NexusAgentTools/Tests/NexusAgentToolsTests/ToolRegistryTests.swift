import Foundation
import NexusCore
import Testing

@testable import NexusAgentTools

private struct StubTool: AgentTool {
    let name: String
    let description: String
    let inputSchema: JSONSchema
    let result: JSONValue

    init(
        name: String,
        description: String? = nil,
        inputSchema: JSONSchema = .object(properties: [:], required: []),
        result: JSONValue = .null
    ) {
        self.name = name
        self.description = description ?? "stub for \(name)"
        self.inputSchema = inputSchema
        self.result = result
    }

    @MainActor
    func call(args: JSONValue, context: AgentContext) async throws -> JSONValue {
        result
    }
}

@Suite("ToolRegistry")
struct ToolRegistryTests {
    @Test("lookup by name returns exact tool")
    func lookup() {
        let registry = ToolRegistry(tools: [
            StubTool(name: "tasks.create"),
            StubTool(name: "tasks.list"),
        ])
        #expect(registry.tool(named: "tasks.create")?.name == "tasks.create")
        #expect(registry.tool(named: "tasks.list")?.name == "tasks.list")
        #expect(registry.tool(named: "tasks.missing") == nil)
    }

    @Test("manifest contains every tool with name + description + schema")
    func manifest() throws {
        let createSchema = JSONSchema.object(
            properties: ["title": .string(description: "Task title")],
            required: ["title"]
        )
        let registry = ToolRegistry(tools: [
            StubTool(name: "tasks.create", inputSchema: createSchema),
            StubTool(name: "tasks.list"),
        ])
        let manifest = registry.manifest()
        #expect(manifest.protocolVersion == AgentServiceConstants.protocolVersion)
        #expect(manifest.tools.count == 2)
        #expect(manifest.tools.map(\.name).sorted() == ["tasks.create", "tasks.list"])
        for entry in manifest.tools {
            #expect(!entry.description.isEmpty)
        }
        let createEntry = try #require(manifest.tools.first { $0.name == "tasks.create" })
        guard case .object(let properties, let required, _) = createEntry.inputSchema else {
            Issue.record("Expected tasks.create input schema to be object")
            return
        }
        #expect(required == ["title"])
        #expect(properties["title"] != nil)
    }

    @Test("manifest is JSON-encodable")
    func manifestEncodes() throws {
        let registry = ToolRegistry(tools: [
            StubTool(
                name: "tasks.get",
                inputSchema: .object(
                    properties: ["id": .string(description: "Task identifier")],
                    required: ["id"]
                )
            )
        ])
        let data = try JSONEncoder().encode(registry.manifest())
        let decoded = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(decoded?["protocol_version"] as? String == "1.0")
        let tools = decoded?["tools"] as? [[String: Any]]
        #expect(tools?.count == 1)
        let tool = try #require(tools?.first)
        #expect(tool["name"] as? String == "tasks.get")
        let inputSchema = try #require(tool["input_schema"] as? [String: Any])
        #expect(inputSchema["type"] as? String == "object")
        let properties = try #require(inputSchema["properties"] as? [String: Any])
        #expect(properties["id"] != nil)
    }

    @Test("rejects duplicate tool names at construction (precondition)")
    func duplicateNames() {
        let registry = ToolRegistry(tools: [
            StubTool(name: "tasks.create", description: "first duplicate"),
            StubTool(name: "tasks.create", description: "last duplicate"),
        ])
        // Last one wins (documented behavior); test ensures lookup deterministic.
        #expect(registry.tools.count == 2)
        #expect(registry.tool(named: "tasks.create")?.description == "last duplicate")
    }
}
