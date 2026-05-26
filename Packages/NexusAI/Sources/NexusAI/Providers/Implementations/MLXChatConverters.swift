import Foundation
import NexusCore

// MARK: - MLXChatConverters

/// Pure, stateless conversion layer between AI-domain contract types (`AIChatMessage`,
/// `AIToolSpec`, `AIToolCall`) and MLX-engine protocol types (`MLXChatMessage`,
/// `MLXToolSpec`, `MLXChunk`).
///
/// `MLXProvider` (Task 12) uses these helpers to build engine inputs from a structured
/// `AIRequest` and to fold engine outputs back into `[AIToolCall]` before populating
/// `AIResponse.toolCalls`.
///
/// All functions are pure and total:
/// - Role mapping is exhaustive (no `default:` case), so a future enum case fails
///   compilation rather than silently producing a wrong role.
/// - `toolCall(from:arguments:)` is malformed-tolerant: it never throws and never
///   drops a call. See the function doc comment for the full rationale.
public enum MLXChatConverters {

    // MARK: AIToolSpec → MLXToolSpec

    /// Converts a single `AIToolSpec` to an `MLXToolSpec` by copying all fields.
    public static func mlxToolSpec(from spec: AIToolSpec) -> MLXToolSpec {
        MLXToolSpec(
            name: spec.name,
            description: spec.description,
            parametersJSONSchema: spec.parametersJSONSchema
        )
    }

    /// Converts an array of `AIToolSpec` to `[MLXToolSpec]`.
    public static func mlxToolSpecs(from specs: [AIToolSpec]) -> [MLXToolSpec] {
        specs.map(mlxToolSpec)
    }

    // MARK: AIChatMessage → MLXChatMessage

    /// Converts a single `AIChatMessage` to an `MLXChatMessage`.
    ///
    /// The role mapping is exhaustive over `AIChatMessage.Role` with no `default:`
    /// branch so that any future case added to the source enum causes a compilation
    /// error rather than a silent wrong-role mapping.
    public static func mlxChatMessage(from message: AIChatMessage) -> MLXChatMessage {
        let role: MLXChatMessage.Role
        switch message.role {
        case .system: role = .system
        case .user: role = .user
        case .assistant: role = .assistant
        case .tool: role = .tool
        }
        return MLXChatMessage(
            role: role,
            text: message.text,
            toolName: message.toolName,
            toolCallID: message.toolCallID
        )
    }

    /// Converts an array of `AIChatMessage` to `[MLXChatMessage]`.
    public static func mlxChatMessages(from messages: [AIChatMessage]) -> [MLXChatMessage] {
        messages.map(mlxChatMessage)
    }

    // MARK: MLXChunk.toolCall → AIToolCall

    /// Converts a `.toolCall` chunk's payload into an `AIToolCall`.
    ///
    /// `arguments` is the compact JSON-object string produced by
    /// `LiveMLXChatContainer` from the model's native tool-call output.  It is
    /// decoded into a `JSONValue` tree via `JSONDecoder`.
    ///
    /// **Malformed-tolerant contract:** this function never throws and never silently
    /// drops the invocation.  If `arguments` is not valid JSON, or if the top-level
    /// decoded value is not `.object`, the function returns
    /// `AIToolCall(name: name, arguments: .object([:]))` — i.e. an empty-object
    /// argument map with the original tool name preserved.
    ///
    /// *Rationale:* a lost tool invocation is strictly worse than a call with empty
    /// arguments.  `ToolDispatcher` / the tool's own input validation will reject
    /// the empty arguments and surface an actionable error that the agent can recover
    /// from (retry, ask user).  Silently dropping the call produces no error and no
    /// forward progress — a harder failure mode to diagnose.
    public static func aiToolCall(name: String, arguments: String) -> AIToolCall {
        guard
            let data = arguments.data(using: .utf8),
            let decoded = try? JSONDecoder().decode(JSONValue.self, from: data),
            case .object = decoded
        else {
            return AIToolCall(name: name, arguments: .object([:]))
        }
        return AIToolCall(name: name, arguments: decoded)
    }
}
