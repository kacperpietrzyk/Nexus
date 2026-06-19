// Packages/NexusAgent/Tests/NexusAgentTests/DailyBriefProjectorTests.swift
import Foundation
import Testing
import InboxShell
@testable import NexusAgent

@Suite struct DailyBriefProjectorTests {
    private let day = Date(timeIntervalSince1970: 1_700_000_000)

    @Test func emitsBriefRowFromSnapshot() async throws {
        let projector = DailyBriefProjector(
            dayKeyProvider: { "brief:2026-06-19" },
            snapshotProvider: { (text: "Three priorities today.\nMore detail.", updatedAt: self.day) }
        )
        let items = try await projector.project()
        #expect(items.count == 1)
        #expect(items.first?.key == "brief:2026-06-19")
        #expect(items.first?.stream == .agent)
        #expect(items.first?.subtitle == "Three priorities today.")
        #expect(items.first?.route == .dailyBrief)
    }

    @Test func emitsNothingWhenNoBrief() async throws {
        let projector = DailyBriefProjector(dayKeyProvider: { "brief:x" }, snapshotProvider: { nil })
        #expect(try await projector.project().isEmpty)
    }
}
