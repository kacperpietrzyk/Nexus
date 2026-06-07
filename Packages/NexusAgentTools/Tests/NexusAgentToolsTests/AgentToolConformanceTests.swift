import Foundation
import Testing

@testable import NexusAgentTools

@Suite("AgentTool conformance - all 20 core tools")
struct AgentToolConformanceTests {
    @Test("each core tool has non-empty name and description")
    func nonEmptyMetadata() {
        for tool in CoreTaskTools.all() {
            #expect(!tool.name.isEmpty, "name empty for tool")
            #expect(!tool.description.isEmpty, "description empty for tool \(tool.name)")
        }
    }

    @Test("each core tool name matches MCP convention")
    func namePattern() {
        for tool in CoreTaskTools.all() {
            #expect(isValidToolName(tool.name), "tool name \(tool.name) does not match convention")
        }
    }

    @Test("each core tool produces JSON-encodable object input schema")
    func schemaEncodes() throws {
        for tool in CoreTaskTools.all() {
            let data = try JSONEncoder().encode(tool.inputSchema)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            #expect(json != nil, "schema did not encode for \(tool.name)")
            #expect((json?["type"] as? String) == "object", "expected object schema for \(tool.name)")
        }
    }

    @Test("core tool names are unique")
    func uniqueNames() {
        let names = CoreTaskTools.all().map(\.name)
        #expect(names.count == Set(names).count, "duplicate tool names: \(names)")
    }

    @Test("registry built from CoreTaskTools.all has 20 tools")
    func registryCount() {
        let registry = ToolRegistry(tools: CoreTaskTools.all())

        #expect(registry.tools.count == 20)
        #expect(registry.manifest().tools.count == 20)
    }

    private func isValidToolName(_ name: String) -> Bool {
        let parts = name.split(separator: ".", omittingEmptySubsequences: false)
        let knownNamespaces: Set<Substring> = ["tasks", "comments", "note"]
        guard parts.count >= 2, let first = parts.first, knownNamespaces.contains(first) else { return false }
        return parts.allSatisfy { part in
            !part.isEmpty
                && part.allSatisfy { character in
                    character.isLowercase || character == "_"
                }
        }
    }
}
