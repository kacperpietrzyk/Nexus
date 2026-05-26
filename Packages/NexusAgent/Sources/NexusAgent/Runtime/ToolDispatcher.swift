import Foundation
import NexusAgentTools
import NexusCore
import SwiftData

public enum ToolDispatcherError: Error, Equatable, Sendable {
    case toolNotFound(String)
}

public struct ToolDispatchResult: Sendable {
    public let output: JSONValue
    public let outputJSON: Data
    public let auditLogID: UUID

    public init(output: JSONValue, outputJSON: Data, auditLogID: UUID) {
        self.output = output
        self.outputJSON = outputJSON
        self.auditLogID = auditLogID
    }
}

@MainActor
public final class ToolDispatcher {
    private let registry: ToolRegistry
    private let modelContext: ModelContext
    private let agentContext: AgentContext
    private let encoder: JSONEncoder

    public init(
        registry: ToolRegistry,
        modelContext: ModelContext,
        agentContext: AgentContext,
        encoder: JSONEncoder? = nil
    ) {
        let encoder = encoder ?? Self.makeEncoder()
        encoder.outputFormatting.insert(.sortedKeys)
        self.registry = registry
        self.modelContext = modelContext
        self.agentContext = agentContext
        self.encoder = encoder
    }

    /// Read-only passthrough of the registry's tool manifest. Lets callers
    /// (e.g. `AgentRuntime.makeAIRequest`) advertise tools to native
    /// tool-calling providers without exposing the private `registry`.
    public var toolManifest: ToolManifestDTO { registry.manifest() }

    public func dispatch(
        toolName: String,
        input: JSONValue,
        threadID: UUID?,
        now: Date = .now
    ) async throws -> ToolDispatchResult {
        guard let tool = registry.tool(named: toolName) else {
            throw ToolDispatcherError.toolNotFound(toolName)
        }

        let inputJSON = try encoder.encode(input)
        let inverseJSON = try await inverseActionJSON(for: tool, input: input)
        let output = try await tool.call(args: input, context: agentContext)
        let outputJSON = try encoder.encode(output)

        let auditLog = AgentAuditLog(
            timestamp: now,
            threadID: threadID,
            toolName: toolName,
            inputJSON: inputJSON,
            outputJSON: outputJSON,
            affectedItemIDs: [],
            inverseAction: inverseJSON
        )
        do {
            modelContext.insert(auditLog)
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }

        return ToolDispatchResult(
            output: output,
            outputJSON: outputJSON,
            auditLogID: auditLog.id
        )
    }

    private func inverseActionJSON(for tool: any AgentTool, input: JSONValue) async throws -> Data? {
        guard let mutatingTool = tool as? any MutatingAgentTool else { return nil }
        let inverseAction = try await mutatingTool.inverse(input: input, context: agentContext)
        return try encoder.encode(inverseAction)
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}
