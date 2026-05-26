import Foundation
import NexusCore

/// A structured tool invocation returned by an AI provider.
///
/// When a provider returns structured tool calls (e.g. via MLX native tool-calling),
/// `AIResponse.toolCalls` is populated with one or more `AIToolCall` values.
/// `AgentRuntime` checks this field first; if non-empty it routes directly to
/// `ToolDispatcher` without JSON text-envelope parsing.
public struct AIToolCall: Sendable, Codable, Equatable {
    /// The name of the tool to invoke (must match a registered `AgentTool.name`).
    public let name: String
    /// Parsed arguments as a `JSONValue` tree (same type used by `AgentTool.call`).
    public let arguments: JSONValue

    public init(name: String, arguments: JSONValue) {
        self.name = name
        self.arguments = arguments
    }
}
