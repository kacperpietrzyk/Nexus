import Foundation
import Testing

@testable import NexusAgentTools

@Suite("Tool schema specificity")
struct ToolSchemaSpecificityTests {
    @Test("comments tools advertise task/project item_kind enum")
    func commentsToolsAdvertiseItemKindEnum() throws {
        for schema in [CommentsListTool().inputSchema, CommentsAddTool().inputSchema] {
            let properties = try objectProperties(schema)
            let itemKind = try #require(properties["item_kind"] as? [String: Any])
            #expect(itemKind["enum"] as? [String] == ["task", "project"])
        }
    }

    @Test("task create tools advertise reminder type and anchor enums")
    func taskCreateToolsAdvertiseReminderEnums() throws {
        for schema in [TasksCreateTool().inputSchema, TasksCreateIdempotentTool().inputSchema] {
            let properties = try objectProperties(schema)
            let reminderProperties = try reminderProperties(from: properties["reminders"])
            let type = try #require(reminderProperties["type"] as? [String: Any])
            let anchor = try #require(reminderProperties["anchor"] as? [String: Any])

            #expect(type["enum"] as? [String] == ["relative", "absolute"])
            #expect(anchor["enum"] as? [String] == ["due", "deadline"])
        }
    }

    @Test("tasks.update advertises nullable reminder patch with nested enums")
    func tasksUpdateAdvertisesNullableReminderEnums() throws {
        let properties = try objectProperties(TasksUpdateTool().inputSchema)
        let patch = try #require(properties["patch"] as? [String: Any])
        let patchProperties = try #require(patch["properties"] as? [String: Any])
        let reminders = try #require(patchProperties["reminders"] as? [String: Any])
        let alternatives = try #require(reminders["anyOf"] as? [[String: Any]])

        #expect(alternatives.contains { $0["type"] as? String == "null" })

        let reminderProperties = try reminderProperties(from: reminders)
        let type = try #require(reminderProperties["type"] as? [String: Any])
        let anchor = try #require(reminderProperties["anchor"] as? [String: Any])

        #expect(type["enum"] as? [String] == ["relative", "absolute"])
        #expect(anchor["enum"] as? [String] == ["due", "deadline"])
    }

    private func objectProperties(_ schema: JSONSchema) throws -> [String: Any] {
        let data = try JSONEncoder().encode(schema)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        return try #require(object["properties"] as? [String: Any])
    }

    private func reminderProperties(from rawSchema: Any?) throws -> [String: Any] {
        let schema = try #require(rawSchema as? [String: Any])
        let arraySchema: [String: Any]
        if let alternatives = schema["anyOf"] as? [[String: Any]] {
            arraySchema = try #require(alternatives.first { $0["type"] as? String == "array" })
        } else {
            arraySchema = schema
        }

        let items = try #require(arraySchema["items"] as? [String: Any])
        return try #require(items["properties"] as? [String: Any])
    }
}
