import Foundation

struct ToolManifestCache {
    let protocolVersion: String
    let tools: [ToolEntry]
    let hasMinorVersionMismatch: Bool

    init(from data: Data) throws {
        let wire = try JSONDecoder().decode(WireManifest.self, from: data)
        let appMajor = Self.major(of: wire.protocolVersion)
        let sidecarMajor = Self.major(of: AgentServiceConstants.protocolVersion)
        guard appMajor == sidecarMajor else {
            let message =
                "Major protocol version mismatch: app=\(wire.protocolVersion), "
                + "sidecar=\(AgentServiceConstants.protocolVersion). "
                + "Restart Claude Desktop after updating Nexus."
            throw NSError(
                domain: "NexusMCPSidecar",
                code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey: message
                ]
            )
        }

        self.protocolVersion = wire.protocolVersion
        self.tools = wire.tools
        self.hasMinorVersionMismatch = wire.protocolVersion != AgentServiceConstants.protocolVersion
    }

    private static func major(of version: String) -> Int {
        Int(version.split(separator: ".").first ?? "0") ?? 0
    }
}

struct ToolEntry: Decodable {
    let name: String
    let description: String
    let inputSchema: [String: Any]?

    private enum CodingKeys: String, CodingKey {
        case name, description
        case inputSchema = "input_schema"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        description = try container.decode(String.self, forKey: .description)
        if let raw = try? container.decode(JSONAny.self, forKey: .inputSchema) {
            inputSchema = raw.value as? [String: Any]
        } else {
            inputSchema = nil
        }
    }
}

private struct WireManifest: Decodable {
    let protocolVersion: String
    let tools: [ToolEntry]

    private enum CodingKeys: String, CodingKey {
        case protocolVersion = "protocol_version"
        case tools
    }
}

private struct JSONAny: Decodable {
    let value: Any

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Bool.self) {
            self.value = value
        } else if let value = try? container.decode(Int.self) {
            self.value = value
        } else if let value = try? container.decode(Double.self) {
            self.value = value
        } else if let value = try? container.decode(String.self) {
            self.value = value
        } else if let value = try? container.decode([JSONAny].self) {
            self.value = value.map(\.value)
        } else if let value = try? container.decode([String: JSONAny].self) {
            self.value = value.mapValues(\.value)
        } else if container.decodeNil() {
            value = NSNull()
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unknown JSON value"
            )
        }
    }
}
