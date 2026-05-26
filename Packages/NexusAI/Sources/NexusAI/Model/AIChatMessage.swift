import Foundation

/// A single structured message in an AI conversation thread.
///
/// Used to populate `AIRequest.messages` for providers that support
/// multi-turn / structured-tool conversation (e.g. MLX, OpenAI).
/// Providers that do not support structured messages ignore this field
/// and fall back to the flat `AIRequest.prompt` string.
public struct AIChatMessage: Sendable, Codable, Equatable {
    public enum Role: String, Sendable, Codable {
        case system
        case user
        case assistant
        case tool
    }

    public let role: Role
    public let text: String
    /// Set for the `.tool` role: the tool that produced this result.
    public let toolName: String?
    /// Optional correlation id for tool call / tool result pairs.
    public let toolCallID: String?

    public init(
        role: Role,
        text: String,
        toolName: String? = nil,
        toolCallID: String? = nil
    ) {
        self.role = role
        self.text = text
        self.toolName = toolName
        self.toolCallID = toolCallID
    }
}
