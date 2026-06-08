import Foundation
import NexusCore

/// A graph endpoint (task or project) referenced by a `blocks` edge (spec §9 / §10).
public struct EndpointRefDTO: Codable, Sendable, Equatable {
    public let kind: String
    public let id: String

    public init(kind: String, id: String) {
        self.kind = kind
        self.id = id
    }
}

/// The dependency view of an endpoint (spec §9): the items it `blocks` (outgoing)
/// and the items that block it (`blocked_by` = incoming).
public struct BlocksDTO: Codable, Sendable, Equatable {
    public let blocks: [EndpointRefDTO]
    public let blockedBy: [EndpointRefDTO]

    private enum CodingKeys: String, CodingKey {
        case blocks
        case blockedBy = "blocked_by"
    }

    public init(blocks: [EndpointRefDTO], blockedBy: [EndpointRefDTO]) {
        self.blocks = blocks
        self.blockedBy = blockedBy
    }
}
