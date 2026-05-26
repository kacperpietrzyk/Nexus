import Foundation

/// Declarative description of a tool the AI provider may call.
///
/// `parametersJSONSchema` is a JSON-object string representing the JSON Schema
/// for the tool's input parameters (e.g. `{"type":"object","properties":{...}}`).
/// Providers forward it to the underlying model in whatever format the model expects.
public struct AIToolSpec: Sendable, Codable, Equatable {
    public let name: String
    public let description: String
    /// JSON Schema for the tool's parameters, encoded as a compact JSON string.
    public let parametersJSONSchema: String

    public init(name: String, description: String, parametersJSONSchema: String) {
        self.name = name
        self.description = description
        self.parametersJSONSchema = parametersJSONSchema
    }
}
