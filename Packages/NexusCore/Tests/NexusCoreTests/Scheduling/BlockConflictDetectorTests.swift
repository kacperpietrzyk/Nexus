import Foundation
import Testing

@testable import NexusCore

@Suite("BlockConflictDetector")
struct BlockConflictDetectorTests {
    // 2026-06-08 09:00 UTC (the DayScheduler/DayPlanner fixture instant).
    private let nine = Date(timeIntervalSince1970: 1_780_650_000)

    private func at(_ hour: Int, _ minute: Int = 0) -> Date {
        nine.addingTimeInterval(TimeInterval((hour - 9) * 3600 + minute * 60))
    }

    private func event(_ id: String, _ start: Date, _ end: Date, isAllDay: Bool = false) -> CalendarEvent {
        CalendarEvent(id: id, title: "evt", start: start, end: end, isAllDay: isAllDay)
    }

    private func block(
        _ start: Date,
        _ end: Date,
        status: ScheduledBlockStatus = .proposed,
        origin: ScheduledBlockOrigin = .auto,
        externalEventID: String? = nil
    ) -> ScheduledBlock {
        ScheduledBlock(
            taskID: UUID(),
            start: start,
            end: end,
            title: "block",
            status: status,
            origin: origin,
            externalEventID: externalEventID
        )
    }

    @Test("non-overlapping blocks and events produce an empty report")
    func noOverlapNoConflict() {
        let report = BlockConflictDetector.detect(
            blocks: [block(at(9), at(10))],
            events: [event("e1", at(10), at(11))]
        )
        #expect(!report.hasConflicts)
        #expect(report.autoProposedBlockIDs.isEmpty)
        #expect(report.protectedBlockIDs.isEmpty)
    }

    @Test("an event overlapping an auto proposal lands in autoProposedBlockIDs")
    func autoProposalConflict() {
        let proposal = block(at(9), at(10))
        let report = BlockConflictDetector.detect(
            blocks: [proposal],
            events: [event("e1", at(9, 30), at(10, 30))]
        )
        #expect(report.autoProposedBlockIDs == [proposal.id])
        #expect(report.protectedBlockIDs.isEmpty)
    }

    @Test("accepted and manual blocks report as protected, never auto")
    func protectedConflicts() {
        let accepted = block(at(9), at(10), status: .accepted, externalEventID: "mirror-1")
        let manual = block(at(11), at(12), origin: .manual)
        let report = BlockConflictDetector.detect(
            blocks: [accepted, manual],
            events: [event("e1", at(9, 30), at(11, 30))]
        )
        #expect(report.autoProposedBlockIDs.isEmpty)
        #expect(Set(report.protectedBlockIDs) == Set([accepted.id, manual.id]))
    }

    @Test("a block's own mirror event is never a conflict")
    func ownMirrorExcluded() {
        let accepted = block(at(9), at(10), status: .accepted, externalEventID: "mirror-1")
        let report = BlockConflictDetector.detect(
            blocks: [accepted],
            events: [event("mirror-1", at(9), at(10))]
        )
        #expect(!report.hasConflicts)
    }

    @Test("all-day events are not obstacles")
    func allDayIgnored() {
        let proposal = block(at(9), at(10))
        let dayStart = at(0)
        let report = BlockConflictDetector.detect(
            blocks: [proposal],
            events: [event("e1", dayStart, dayStart.addingTimeInterval(86_400), isAllDay: true)]
        )
        #expect(!report.hasConflicts)
    }

    @Test("soft-deleted blocks are ignored")
    func deletedIgnored() {
        let proposal = block(at(9), at(10))
        proposal.deletedAt = at(9)
        let report = BlockConflictDetector.detect(
            blocks: [proposal],
            events: [event("e1", at(9), at(10))]
        )
        #expect(!report.hasConflicts)
    }

    @Test("a proposal overlapping a protected block conflicts; the protected side does not")
    func proposalVsProtectedBlock() {
        let accepted = block(at(9), at(10), status: .accepted, externalEventID: "mirror-1")
        let proposal = block(at(9, 30), at(10, 30))
        let report = BlockConflictDetector.detect(blocks: [accepted, proposal], events: [])
        #expect(report.autoProposedBlockIDs == [proposal.id])
        #expect(report.protectedBlockIDs.isEmpty)
    }

    @Test("two protected blocks overlapping flag each other")
    func protectedVsProtected() {
        let first = block(at(9), at(10), status: .accepted, externalEventID: "m1")
        let second = block(at(9, 30), at(10, 30), status: .accepted, externalEventID: "m2")
        let report = BlockConflictDetector.detect(blocks: [first, second], events: [])
        #expect(Set(report.protectedBlockIDs) == Set([first.id, second.id]))
    }

    @Test("report is deterministic regardless of input order")
    func deterministicOrdering() {
        let one = block(at(9), at(10))
        let two = block(at(9, 30), at(10, 30))
        let obstacle = event("e1", at(9), at(11))
        let reportA = BlockConflictDetector.detect(blocks: [one, two], events: [obstacle])
        let reportB = BlockConflictDetector.detect(blocks: [two, one], events: [obstacle])
        #expect(reportA == reportB)
        #expect(reportA.autoProposedBlockIDs == reportA.autoProposedBlockIDs.sorted { $0.uuidString < $1.uuidString })
    }
}
