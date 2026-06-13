import Foundation
import Testing

@testable import NexusAgentTools

@Suite("AgentTool conformance - all 61 core tools")
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

    @Test("registry built from CoreTaskTools.all has 61 tools")
    func registryCount() {
        let registry = ToolRegistry(tools: CoreTaskTools.all())

        #expect(registry.tools.count == 61)
        #expect(registry.manifest().tools.count == 61)
    }

    // MARK: - Calendar / schedule tools (injected at app level, so otherwise
    // uncovered by the CoreTaskTools enumeration above).

    @MainActor
    private func calendarTools() -> [any AgentTool] {
        CalendarAgentTools.tools(provider: FakeCalendarProvider())
    }

    @MainActor
    @Test("each calendar/schedule tool has non-empty metadata, valid name, object schema")
    func calendarToolConformance() throws {
        for tool in calendarTools() {
            #expect(!tool.name.isEmpty, "name empty for tool")
            #expect(!tool.description.isEmpty, "description empty for tool \(tool.name)")
            #expect(isValidToolName(tool.name), "tool name \(tool.name) does not match convention")
            let data = try JSONEncoder().encode(tool.inputSchema)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            #expect((json?["type"] as? String) == "object", "expected object schema for \(tool.name)")
        }
    }

    @MainActor
    @Test("combined served set (core + calendar) has no name collisions")
    func combinedSetIsCollisionFree() {
        let names = (CoreTaskTools.all() + calendarTools()).map(\.name)
        #expect(names.count == Set(names).count, "duplicate tool names across sets: \(names)")
    }

    private func isValidToolName(_ name: String) -> Bool {
        let parts = name.split(separator: ".", omittingEmptySubsequences: false)
        let knownNamespaces: Set<Substring> = [
            "tasks", "comments", "note", "schedule", "calendar",
            "projects", "agents", "labels", "blocks", "people", "activity", "cycles", "search",
        ]
        guard parts.count >= 2, let first = parts.first, knownNamespaces.contains(first) else { return false }
        return parts.allSatisfy { part in
            !part.isEmpty
                && part.allSatisfy { character in
                    character.isLowercase || character == "_"
                }
        }
    }
}
