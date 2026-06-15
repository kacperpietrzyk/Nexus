import Foundation
import SwiftData
import Testing

@testable import NexusCore

@Suite("NoteProperty / Note V13 fields")
struct NotePropertyTests {
    @Test("NotePropertyValue is Codable round-trip for every case")
    func valueIsCodableRoundTrip() throws {
        let values: [NotePropertyValue] = [
            .string("hello"),
            .number(42.5),
            .bool(true),
            .date(Date(timeIntervalSince1970: 1_700_000_000)),
            .list(["a", "b"]),
        ]
        for value in values {
            let encoded = try JSONEncoder().encode(value)
            let decoded = try JSONDecoder().decode(NotePropertyValue.self, from: encoded)
            #expect(decoded == value)
        }
    }

    /// Pins the persisted blob shape (synthesized Codable: case name key +
    /// `_0` payload key). The blob lands in CloudKit inside
    /// `Note.propertiesJSON` — the encoding must never silently change.
    @Test("persisted JSON shape is pinned")
    func persistedShapeIsPinned() throws {
        let json = #"[{"key":"status","value":{"string":{"_0":"active"}}}]"#
        let decoded = try JSONDecoder().decode([NoteProperty].self, from: Data(json.utf8))
        #expect(decoded == [NoteProperty(key: "status", value: .string("active"))])
    }

    /// Pins the ENCODE direction byte-for-byte through the real write path
    /// (`Note.properties` setter): `.sortedKeys` makes the blob deterministic
    /// across runs/devices, and `.date` persists via the default
    /// `.deferredToDate` strategy (Double, seconds since reference date).
    @Test("encoded blob is deterministic and byte-pinned")
    func encodedShapeIsPinned() {
        let note = Note(title: "n")
        note.properties = [NoteProperty(key: "status", value: .string("active"))]
        #expect(note.propertiesJSON == #"[{"key":"status","value":{"string":{"_0":"active"}}}]"#)

        note.properties = [NoteProperty(key: "when", value: .date(Date(timeIntervalSinceReferenceDate: 0)))]
        #expect(note.propertiesJSON == #"[{"key":"when","value":{"date":{"_0":0}}}]"#)
    }

    @Test("new Note fields default to nil / empty")
    func noteDefaultsAreNil() {
        let note = Note(title: "n")
        #expect(note.propertiesJSON == nil)
        #expect(note.folderPath == nil)
        #expect(note.properties.isEmpty)
    }

    @Test("properties accessor round-trips and clears the blob on empty (reminders idiom)")
    func accessorRoundTripsAndNilsEmpty() {
        let note = Note(title: "n")
        let props = [
            NoteProperty(key: "status", value: .string("active")),
            NoteProperty(key: "estimate", value: .number(3)),
        ]
        note.properties = props
        #expect(note.propertiesJSON != nil)
        #expect(note.properties == props)

        note.properties = []
        #expect(note.propertiesJSON == nil)
    }

    @Test("accessor de-duplicates keys last-wins, case-sensitively, preserving order of survivors")
    func accessorDeduplicatesLastWins() {
        let note = Note(title: "n")
        note.properties = [
            NoteProperty(key: "status", value: .string("draft")),
            NoteProperty(key: "owner", value: .string("me")),
            NoteProperty(key: "status", value: .string("active")),
            NoteProperty(key: "Status", value: .string("case-distinct")),
        ]
        #expect(
            note.properties == [
                NoteProperty(key: "owner", value: .string("me")),
                NoteProperty(key: "status", value: .string("active")),
                NoteProperty(key: "Status", value: .string("case-distinct")),
            ]
        )
    }

    @MainActor
    @Test("propertiesJSON and folderPath round-trip through an in-memory store")
    func roundTripsThroughStore() throws {
        let schema = Schema([Note.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)

        let note = Note(title: "filed")
        note.properties = [NoteProperty(key: "status", value: .string("active"))]
        note.folderPath = "area/subarea"
        context.insert(note)
        try context.save()

        let fetched = try #require(try context.fetch(FetchDescriptor<Note>()).first)
        #expect(fetched.properties == [NoteProperty(key: "status", value: .string("active"))])
        #expect(fetched.folderPath == "area/subarea")
    }
}
