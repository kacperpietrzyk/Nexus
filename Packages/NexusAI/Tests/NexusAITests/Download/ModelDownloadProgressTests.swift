import Foundation
import Testing
@testable import NexusAI

@MainActor
@Test func progressReportsPercentAndETA() {
    let progress = ModelDownloadProgress(manifestID: "qwen3.5-9b-instruct-4bit", totalBytes: 5_800_000_000)
    progress.transferred(
        bytes: 1_450_000_000,
        at: Date(timeIntervalSince1970: 1_780_000_010),
        startedAt: Date(timeIntervalSince1970: 1_780_000_000)
    )
    #expect(abs(progress.percent - 25.0) < 0.5)
    #expect(progress.bytesPerSecond > 0)
    #expect(progress.etaSeconds ?? 0 > 20 && progress.etaSeconds ?? 0 < 40)
}

@MainActor
@Test func progressTransitionsThroughStates() {
    let progress = ModelDownloadProgress(manifestID: "qwen3.5-4b-instruct-4bit", totalBytes: 3_200_000_000)
    #expect(progress.state == .pending)
    progress.markStarted(at: Date())
    #expect(progress.state == .active)
    progress.markPaused()
    #expect(progress.state == .paused)
    progress.markCompleted()
    #expect(progress.state == .completed)
    #expect(progress.percent == 100.0)
}

@MainActor
@Test func progressRecordsErrorWithReason() {
    let progress = ModelDownloadProgress(manifestID: "qwen3.5-4b-instruct-4bit", totalBytes: 3_200_000_000)
    progress.markFailed(reason: "Network unreachable")
    #expect(progress.state == .failed)
    #expect(progress.errorReason == "Network unreachable")
}
