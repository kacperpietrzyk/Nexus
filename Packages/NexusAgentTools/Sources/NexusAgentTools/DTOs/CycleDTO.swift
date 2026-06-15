import Foundation
import NexusCore

/// Wire format for `Cycle` exposed via MCP (Tranche 2 Plan C). snake_case keys
/// per MCP convention; `status` is the `CycleStatus` raw value.
public struct CycleDTO: Codable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let status: String
    public let startAt: String
    public let endAt: String
    public let createdAt: String
    public let updatedAt: String

    private enum CodingKeys: String, CodingKey {
        case id, name, status
        case startAt = "start_at"
        case endAt = "end_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    public init(
        id: String,
        name: String,
        status: String,
        startAt: String,
        endAt: String,
        createdAt: String,
        updatedAt: String
    ) {
        self.id = id
        self.name = name
        self.status = status
        self.startAt = startAt
        self.endAt = endAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public init(from cycle: Cycle) {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        self.init(
            id: cycle.id.uuidString,
            name: cycle.name,
            status: cycle.status.rawValue,
            startAt: formatter.string(from: cycle.startAt),
            endAt: formatter.string(from: cycle.endAt),
            createdAt: formatter.string(from: cycle.createdAt),
            updatedAt: formatter.string(from: cycle.updatedAt)
        )
    }
}

/// `cycles.list` response envelope.
public struct CycleListResponseDTO: Codable, Sendable, Equatable {
    public let cycles: [CycleDTO]

    public init(cycles: [CycleDTO]) {
        self.cycles = cycles
    }
}
