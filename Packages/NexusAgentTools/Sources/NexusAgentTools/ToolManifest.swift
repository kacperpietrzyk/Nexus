import Foundation

/// Wire format for the manifest delivered via XPC `getToolManifest()`.
/// Sidecar consumes this to register tools with the MCP SDK.
public struct ToolManifestDTO: Codable, Sendable {
    public let protocolVersion: String
    public let tools: [ToolEntryDTO]

    public init(protocolVersion: String, tools: [ToolEntryDTO]) {
        self.protocolVersion = protocolVersion
        self.tools = tools
    }

    private enum CodingKeys: String, CodingKey {
        case protocolVersion = "protocol_version"
        case tools
    }
}

public struct ToolEntryDTO: Codable, Sendable {
    public let name: String
    public let description: String
    public let inputSchema: JSONSchema

    public init(name: String, description: String, inputSchema: JSONSchema) {
        self.name = name
        self.description = description
        self.inputSchema = inputSchema
    }

    private enum CodingKeys: String, CodingKey {
        case name, description
        case inputSchema = "input_schema"
    }
}
