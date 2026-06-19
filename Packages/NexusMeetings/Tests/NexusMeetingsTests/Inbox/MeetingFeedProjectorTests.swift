// Packages/NexusMeetings/Tests/NexusMeetingsTests/MeetingFeedProjectorTests.swift
import Foundation
import Testing
import InboxShell
@testable import NexusMeetings

@Suite struct MeetingFeedProjectorTests {
    private let t0 = Date(timeIntervalSince1970: 100)

    @Test func emitsRowWithSummaryAndActionItems() async throws {
        let projector = MeetingFeedProjector(snapshotProvider: {
            [.init(id: UUID(), title: "Standup", hasSummary: true, actionItemCount: 3, eventDate: self.t0)]
        })
        let items = try await projector.project()
        #expect(items.count == 1)
        #expect(items.first?.stream == .meeting)
        #expect(items.first?.title == "Standup")
        #expect(items.first?.subtitle == "Summary ready · 3 action items")
        #expect(items.first?.key.hasPrefix("meeting:") == true)
    }

    @Test func summaryOnlySubtitle() async throws {
        let projector = MeetingFeedProjector(snapshotProvider: {
            [.init(id: UUID(), title: "1:1", hasSummary: true, actionItemCount: 0, eventDate: self.t0)]
        })
        #expect(try await projector.project().first?.subtitle == "Summary ready")
    }

    @Test func skipsMeetingsWithNeitherSummaryNorActionItems() async throws {
        let projector = MeetingFeedProjector(snapshotProvider: {
            [.init(id: UUID(), title: "Empty", hasSummary: false, actionItemCount: 0, eventDate: self.t0)]
        })
        #expect(try await projector.project().isEmpty)
    }
}
