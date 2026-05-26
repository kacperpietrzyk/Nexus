import Foundation
import NexusAgentTools
import Testing

struct JSONSchemaTests {
    @Test
    func encodesObjectSchemaWithRequiredFields() throws {
        let schema = JSONSchema.object(
            properties: [
                "title": .string(description: "Task title"),
                "priority": .integer(minimum: 1, maximum: 4, description: "Priority"),
            ],
            required: ["title"],
            description: "Create task input"
        )

        let object = try encodeJSONObject(schema)

        #expect(object["type"] as? String == "object")
        #expect(object["required"] as? [String] == ["title"])
        #expect(object["description"] as? String == "Create task input")

        let properties = try #require(object["properties"] as? [String: Any])
        let title = try #require(properties["title"] as? [String: Any])
        let priority = try #require(properties["priority"] as? [String: Any])

        #expect(title["type"] as? String == "string")
        #expect(title["description"] as? String == "Task title")
        #expect(priority["type"] as? String == "integer")
        #expect(priority["minimum"] as? Int == 1)
        #expect(priority["maximum"] as? Int == 4)
    }

    @Test
    func encodesStringEnumSchema() throws {
        let schema = JSONSchema.string(enumValues: ["low", "medium", "high"], description: "Priority")
        let object = try encodeJSONObject(schema)

        #expect(object["type"] as? String == "string")
        #expect(object["enum"] as? [String] == ["low", "medium", "high"])
        #expect(object["description"] as? String == "Priority")
    }

    @Test
    func encodesArraySchemaWithItems() throws {
        let schema = JSONSchema.array(items: .string(), description: "Tags")
        let object = try encodeJSONObject(schema)

        #expect(object["type"] as? String == "array")
        #expect(object["description"] as? String == "Tags")

        let items = try #require(object["items"] as? [String: Any])
        #expect(items["type"] as? String == "string")
    }

    private func encodeJSONObject(_ schema: JSONSchema) throws -> [String: Any] {
        let data = try JSONEncoder().encode(schema)
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
