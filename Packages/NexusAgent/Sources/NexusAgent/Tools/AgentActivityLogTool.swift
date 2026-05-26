import Foundation
import NexusAgentTools
import NexusCore
import SwiftData

public struct AgentActivityLogTool: AgentTool {
    public let name = "agent.activity_log"
    public let description = "Read recent agent tool audit log entries."
    public let inputSchema: JSONSchema = .object(
        properties: [
            "threadID": .string(description: "Optional thread UUID filter."),
            "since": .anyValue(description: "Optional ISO8601 string or Unix timestamp filter."),
            "limit": .integer(
                minimum: 0,
                maximum: AgentActivityLogArguments.maxLimit,
                description: "Maximum entries to return. Defaults to 50."
            ),
        ],
        required: []
    )

    private let modelContext: ModelContextRef

    @MainActor
    public init(context: ModelContext) {
        self.modelContext = ModelContextRef(context)
    }

    @MainActor
    public func call(args: JSONValue, context: AgentContext) async throws -> JSONValue {
        let input = try AgentActivityLogArguments.input(from: args)
        guard input.limit > 0 else {
            return .object(["entries": .array([])])
        }

        let descriptor = AgentActivityLogArguments.fetchDescriptor(for: input)
        let entries = try modelContext.context.fetch(descriptor)
            .map { entry in
                JSONValue.object([
                    "id": .string(entry.id.uuidString),
                    "timestamp": .string(Self.iso8601String(from: entry.timestamp)),
                    "threadID": entry.threadID.map { .string($0.uuidString) } ?? .null,
                    "toolName": .string(entry.toolName),
                    "hasInverse": .bool(entry.inverseAction != nil),
                    "undoneAt": entry.undoneAt.map { .string(Self.iso8601String(from: $0)) }
                        ?? .null,
                ])
            }

        return .object(["entries": .array(Array(entries))])
    }

    private static func iso8601String(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}

struct AgentActivityLogInput: Equatable {
    let threadID: UUID?
    let since: Date?
    let limit: Int
}

enum AgentActivityLogArguments {
    static let maxLimit = 500

    static func input(from args: JSONValue) throws -> AgentActivityLogInput {
        let object = try AgentMemoryToolArguments.object(from: args)
        let limit = try AgentMemoryToolArguments.optionalInt(object["limit"], field: "limit") ?? 50
        guard (0...maxLimit).contains(limit) else {
            throw AgentError.validation("limit must be between 0 and \(maxLimit)")
        }

        return AgentActivityLogInput(
            threadID: try optionalUUID(object["threadID"], field: "threadID"),
            since: try optionalDate(object["since"], field: "since"),
            limit: limit
        )
    }

    static func fetchDescriptor(for input: AgentActivityLogInput) -> FetchDescriptor<AgentAuditLog> {
        var descriptor: FetchDescriptor<AgentAuditLog>
        switch (input.threadID, input.since) {
        case (.some(let threadID), .some(let since)):
            descriptor = FetchDescriptor<AgentAuditLog>(
                predicate: #Predicate {
                    $0.threadID == threadID && $0.timestamp >= since
                },
                sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
            )
        case (.some(let threadID), .none):
            descriptor = FetchDescriptor<AgentAuditLog>(
                predicate: #Predicate {
                    $0.threadID == threadID
                },
                sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
            )
        case (.none, .some(let since)):
            descriptor = FetchDescriptor<AgentAuditLog>(
                predicate: #Predicate {
                    $0.timestamp >= since
                },
                sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
            )
        case (.none, .none):
            descriptor = FetchDescriptor<AgentAuditLog>(
                sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
            )
        }
        descriptor.fetchLimit = input.limit
        return descriptor
    }

    private static func optionalUUID(_ value: JSONValue?, field: String) throws -> UUID? {
        guard let value else { return nil }
        let text = try AgentMemoryToolArguments.requiredString(value, field: field)
        guard let id = UUID(uuidString: text) else {
            throw AgentError.validation("\(field) must be a UUID string")
        }
        return id
    }

    private static func optionalDate(_ value: JSONValue?, field: String) throws -> Date? {
        guard let value else { return nil }
        if let text = value.stringValue {
            return try date(from: text, field: field)
        }
        if let timestamp = value.doubleValue {
            return Date(timeIntervalSince1970: timestamp)
        }
        throw AgentError.validation("\(field) must be an ISO8601 string or Unix timestamp")
    }

    private static func date(from text: String, field: String) throws -> Date {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw AgentError.validation("\(field) cannot be empty")
        }

        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractionalFormatter.date(from: trimmed) {
            return date
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: trimmed) {
            return date
        }

        throw AgentError.validation("\(field) must be an ISO8601 string or Unix timestamp")
    }
}
