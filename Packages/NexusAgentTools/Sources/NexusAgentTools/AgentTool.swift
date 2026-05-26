import Foundation
import NexusCore

/// A tool exposed to external agents via the MCP server (or future in-app agent).
/// Each implementation declares its name, description, JSON Schema for inputs,
/// and a dispatch method invoked on @MainActor by `AgentToolBootstrap`.
public protocol AgentTool: Sendable {
    /// Snake-case dotted identifier, e.g. "tasks.create_from_text".
    var name: String { get }

    /// Human-readable description shown to LLMs when selecting tools.
    /// English. Multi-line OK.
    var description: String { get }

    /// JSON Schema (Draft 7) describing the input arguments object.
    var inputSchema: JSONSchema { get }

    /// Dispatch method. Args are pre-validated against `inputSchema` by the sidecar
    /// (Swift MCP SDK). Implementations perform semantic validation.
    @MainActor
    func call(args: JSONValue, context: AgentContext) async throws -> JSONValue
}
