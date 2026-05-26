import Foundation
import NexusCore
import Testing

@testable import TasksFeature

@Suite("NotificationSnapshot Codable")
struct NotificationSnapshotTests {

    @Test func roundtrip_preserves_all_fields() throws {
        let entry = NotificationSnapshotEntry(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            title: "Pay rent",
            dueAt: Date(timeIntervalSince1970: 1_700_000_000),
            projectName: "Home",
            snoozedUntil: Date(timeIntervalSince1970: 1_700_001_000)
        )
        let snapshot = NotificationSnapshot(
            entries: [entry],
            generatedAt: Date(timeIntervalSince1970: 1_699_000_000),
            horizon: 86_400
        )

        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(NotificationSnapshot.self, from: data)

        #expect(decoded == snapshot)
    }

    @Test func empty_entries_roundtrip() throws {
        let snapshot = NotificationSnapshot(
            entries: [],
            generatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            horizon: 86_400
        )
        let data = try JSONEncoder().encode(snapshot)
        #expect(try JSONDecoder().decode(NotificationSnapshot.self, from: data) == snapshot)
    }

    @Test func optional_fields_nil_roundtrip() throws {
        let entry = NotificationSnapshotEntry(
            id: UUID(),
            title: "x",
            dueAt: Date(timeIntervalSince1970: 0),
            projectName: nil,
            snoozedUntil: nil
        )
        let data = try JSONEncoder().encode(entry)
        #expect(try JSONDecoder().decode(NotificationSnapshotEntry.self, from: data) == entry)
    }
}
