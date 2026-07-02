import Foundation
import Testing

@testable import NexusMeetings

// Regression coverage for the ghost-row (duplicate CloudKit id) and crash-recovery
// fixes from the Meetings bug hunt (2026-07-02).

@Test func transcriptCompleteCoversSummaryAndReadyStates() {
    let complete: [MeetingProcessingStatus] = [
        .processingSummary, .processingActions,
        .awaitingExternalSummary, .claimedExternalSummary, .ready,
    ]
    for status in complete {
        #expect(MeetingProcessingStatus.transcriptComplete(status.rawValue))
    }

    let incomplete: [MeetingProcessingStatus] = [
        .recording, .queued, .processingVAD, .processingASR,
        .processingDiarization, .processingMerge, .failed,
    ]
    for status in incomplete {
        #expect(MeetingProcessingStatus.transcriptComplete(status.rawValue) == false)
    }
}

@Test func awaitingSummaryOnlyForDeferredStates() {
    #expect(MeetingProcessingStatus.awaitingSummary(MeetingProcessingStatus.awaitingExternalSummary.rawValue))
    #expect(MeetingProcessingStatus.awaitingSummary(MeetingProcessingStatus.claimedExternalSummary.rawValue))
    #expect(MeetingProcessingStatus.awaitingSummary(MeetingProcessingStatus.ready.rawValue) == false)
    #expect(MeetingProcessingStatus.awaitingSummary(MeetingProcessingStatus.processingSummary.rawValue) == false)
    #expect(MeetingProcessingStatus.awaitingSummary(MeetingProcessingStatus.queued.rawValue) == false)
}

@Test func filterBeforeDedupKeepsLiveGhostTwin() {
    let id = UUID()
    let now = Date()
    let deletedTwin = Meeting(id: id, title: "deleted", startedAt: now, detectionSource: .manual)
    deletedTwin.deletedAt = now
    let liveTwin = Meeting(id: id, title: "live", startedAt: now, detectionSource: .manual)
    // The soft-deleted twin sorts first (equal startedAt → arbitrary order).
    let rows = [deletedTwin, liveTwin]

    // Correct order (the fix): filter soft-deleted, THEN collapse duplicate ids.
    let correct = rows.filter { $0.deletedAt == nil }.dedupedByID()
    #expect(correct.map(\.id) == [id])
    #expect(correct.first?.deletedAt == nil)

    // The inverted order (dedup-then-filter) keeps the deleted twin and then drops
    // it — silently hiding the still-live meeting. This is the bug the fix guards.
    let inverted = rows.dedupedByID().filter { $0.deletedAt == nil }
    #expect(inverted.isEmpty)
}
