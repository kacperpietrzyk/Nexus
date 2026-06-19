// Packages/NexusAgent/Tests/NexusAgentTests/DailyBriefProjectorTests.swift
import Foundation
import InboxShell
import Testing

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

    @Test func dayKeyHasBriefPrefixAndIsoDate() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        // 2023-11-14T22:13:20Z — `dayKey` reads the calendar's start-of-day.
        let key = DailyBriefProjector.dayKey(for: day)
        #expect(key.hasPrefix("brief:"))
        #expect(key.dropFirst("brief:".count).count == "yyyy-MM-dd".count)
    }
}
