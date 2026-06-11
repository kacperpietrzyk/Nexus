import Foundation

/// Outcome of a conflict scan (M1 auto-replan, gap matrix 2026-06-11): which
/// live blocks now collide with calendar obstacles, partitioned by what the
/// pipeline is allowed to do about them.
///
/// - `autoProposedBlockIDs` — `proposed`/`auto` blocks. Ephemeral by design
///   (spec §6: a re-plan regenerates them), so the pipeline reschedules these
///   automatically.
/// - `protectedBlockIDs` — `accepted` blocks and `manual`-origin blocks. The
///   anti-thrash invariant (spec §1/§14: the scheduler never moves what the
///   user committed to) forbids touching them; the UI surfaces a non-blocking
///   "Replan" affordance instead.
public struct BlockConflictReport: Equatable, Sendable {
    public var autoProposedBlockIDs: [UUID]
    public var protectedBlockIDs: [UUID]

    public init(autoProposedBlockIDs: [UUID] = [], protectedBlockIDs: [UUID] = []) {
        self.autoProposedBlockIDs = autoProposedBlockIDs
        self.protectedBlockIDs = protectedBlockIDs
    }

    public var hasConflicts: Bool {
        !autoProposedBlockIDs.isEmpty || !protectedBlockIDs.isEmpty
    }
}

/// Pure overlap detection between live `ScheduledBlock`s and calendar
/// obstacles (M1). Deterministic, zero EventKit, no ambient clock — the
/// `DayScheduler` pattern. Obstacles are:
///
/// - timed (non-all-day) calendar events, excluding each block's OWN mirror
///   event (`externalEventID` — an accepted block always exactly overlaps its
///   mirror; that is identity, not conflict);
/// - other protected blocks (accepted/manual), so block-vs-block collisions
///   are caught even when the "Nexus" calendar is excluded from the read set.
///
/// `bufferMinutes` violations are deliberately NOT conflicts (suggestive, not
/// aggressive): only true `[start, end)` interval overlap counts.
public enum BlockConflictDetector {
    public static func detect(blocks: [ScheduledBlock], events: [CalendarEvent]) -> BlockConflictReport {
        let live = blocks.filter { $0.deletedAt == nil }
        let timedEvents = events.filter { !$0.isAllDay }

        var autoProposed: Set<UUID> = []
        var protectedBlocks: Set<UUID> = []

        for block in live {
            let hitsEvent = timedEvents.contains { event in
                event.id != block.externalEventID
                    && event.start < block.end
                    && event.end > block.start
            }
            let hitsProtectedBlock = live.contains { other in
                other.id != block.id
                    && isProtected(other)
                    && other.start < block.end
                    && other.end > block.start
            }
            guard hitsEvent || hitsProtectedBlock else { continue }
            if isProtected(block) {
                protectedBlocks.insert(block.id)
            } else {
                autoProposed.insert(block.id)
            }
        }

        return BlockConflictReport(
            autoProposedBlockIDs: autoProposed.sorted { $0.uuidString < $1.uuidString },
            protectedBlockIDs: protectedBlocks.sorted { $0.uuidString < $1.uuidString }
        )
    }

    /// Accepted blocks and manual-origin blocks are user commitments — the
    /// anti-thrash invariant (spec §14) shields them from auto-replan.
    static func isProtected(_ block: ScheduledBlock) -> Bool {
        block.status == .accepted || block.origin == .manual
    }
}
