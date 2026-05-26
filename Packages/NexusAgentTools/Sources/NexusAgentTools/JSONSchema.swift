import Foundation

/// Minimal Draft 7 JSON Schema types for tool input descriptions.
/// Hand-written per tool - no auto-derivation from Swift Codable.
public indirect enum JSONSchema: Sendable, Codable {
    case object(properties: [String: JSONSchema], required: [String], description: String? = nil)
    case string(enumValues: [String]? = nil, description: String? = nil)
    case integer(minimum: Int? = nil, maximum: Int? = nil, description: String? = nil)
    case number(description: String? = nil)
    case boolean(description: String? = nil)
    case array(items: JSONSchema, description: String? = nil)
    case anyValue(description: String? = nil)

    private enum CodingKeys: String, CodingKey {
        case type, properties, required, items, description
        case enumValues = "enum"
        case minimum, maximum
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .object(let properties, let required, let description):
            try container.encode("object", forKey: .type)
            try container.encode(properties, forKey: .properties)
            if !required.isEmpty {
                try container.encode(required, forKey: .required)
            }
            try container.encodeIfPresent(description, forKey: .description)
        case .string(let enumValues, let description):
            try container.encode("string", forKey: .type)
            try container.encodeIfPresent(enumValues, forKey: .enumValues)
            try container.encodeIfPresent(description, forKey: .description)
        case .integer(let minimum, let maximum, let description):
            try container.encode("integer", forKey: .type)
            try container.encodeIfPresent(minimum, forKey: .minimum)
            try container.encodeIfPresent(maximum, forKey: .maximum)
            try container.encodeIfPresent(description, forKey: .description)
        case .number(let description):
            try container.encode("number", forKey: .type)
            try container.encodeIfPresent(description, forKey: .description)
        case .boolean(let description):
            try container.encode("boolean", forKey: .type)
            try container.encodeIfPresent(description, forKey: .description)
        case .array(let items, let description):
            try container.encode("array", forKey: .type)
            try container.encode(items, forKey: .items)
            try container.encodeIfPresent(description, forKey: .description)
        case .anyValue(let description):
            try container.encodeIfPresent(description, forKey: .description)
        }
    }

    public init(from decoder: Decoder) throws {
        throw DecodingError.dataCorruptedError(
            in: try decoder.singleValueContainer(),
            debugDescription: "JSONSchema decoding is not implemented"
        )
    }
}
