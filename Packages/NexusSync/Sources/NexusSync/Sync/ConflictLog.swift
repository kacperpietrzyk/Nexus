import Foundation
import NexusCore
import SwiftData

/// Resolution strategy used to settle a CloudKit merge.
public enum ConflictResolution: String, Codable, Sendable, CaseIterable {
    case lastWriteWins
    case setMerge
    case tombstoneWins
}

// TODO(Phase 1): add `purgeOld(keeping:)` to cap retained entries once Phase 1 wires
// CloudKit conflict detection to ConflictLog writes.

/// Diagnostic record of a sync conflict and how it was resolved. UI surfaces this in Settings →
/// Sync Status.
@Model
public final class ConflictLog {
    public var id: UUID = UUID()
    public var timestamp: Date = Date.now
    public var itemKind: ItemKind = ItemKind.debug
    public var itemID: UUID = UUID()
    public var resolution: ConflictResolution = ConflictResolution.lastWriteWins
    public var summary: String = ""

    public init(
        itemKind: ItemKind,
        itemID: UUID,
        resolution: ConflictResolution,
        summary: String,
        timestamp: Date = .now
    ) {
        self.id = UUID()
        self.timestamp = timestamp
        self.itemKind = itemKind
        self.itemID = itemID
        self.resolution = resolution
        self.summary = summary
    }
}
