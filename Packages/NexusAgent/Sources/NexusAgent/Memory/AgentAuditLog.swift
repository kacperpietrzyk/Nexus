import Foundation
import SwiftData

@Model
public final class AgentAuditLog {
    public var id: UUID
    public var timestamp: Date
    public var threadID: UUID?
    public var toolName: String
    public var inputJSON: Data
    public var outputJSON: Data
    public var affectedItemIDs: [UUID]
    public var inverseAction: Data?
    public var undoneAt: Date?

    public init(
        id: UUID = UUID(),
        timestamp: Date = .now,
        threadID: UUID? = nil,
        toolName: String,
        inputJSON: Data,
        outputJSON: Data,
        affectedItemIDs: [UUID] = [],
        inverseAction: Data? = nil,
        undoneAt: Date? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.threadID = threadID
        self.toolName = toolName
        self.inputJSON = inputJSON
        self.outputJSON = outputJSON
        self.affectedItemIDs = affectedItemIDs
        self.inverseAction = inverseAction
        self.undoneAt = undoneAt
    }
}
