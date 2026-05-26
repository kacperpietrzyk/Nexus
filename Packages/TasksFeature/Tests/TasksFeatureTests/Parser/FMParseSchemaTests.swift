import Foundation
import Testing

@testable import TasksFeature

@Suite("FMParseSchema")
struct FMParseSchemaTests {
    @Test("decodes minimal payload")
    func minimal() throws {
        let json = #"{"title":"Buy milk"}"#
        let data = json.data(using: .utf8)!
        let schema = try JSONDecoder().decode(FMParseSchema.self, from: data)
        #expect(schema.title == "Buy milk")
        #expect(schema.dueAt == nil)
        #expect(schema.startAt == nil)
        #expect(schema.endAt == nil)
        #expect(schema.deadlineAt == nil)
        #expect(schema.priority == nil)
        #expect(schema.tags == nil)
        #expect(schema.recurrence == nil)
    }

    @Test("decodes full payload")
    func full() throws {
        let json = """
            {
                "title": "Buy milk",
                "dueAt": "2026-05-15T00:00:00Z",
                "startAt": "2026-05-15T08:00:00Z",
                "endAt": "2026-05-15T09:00:00Z",
                "deadlineAt": "2026-05-20T00:00:00Z",
                "priority": 2,
                "tags": ["shopping","home"],
                "recurrence": "FREQ=WEEKLY;BYDAY=MO"
            }
            """
        let data = json.data(using: .utf8)!
        let schema = try JSONDecoder().decode(FMParseSchema.self, from: data)
        #expect(schema.title == "Buy milk")
        #expect(schema.dueAt == "2026-05-15T00:00:00Z")
        #expect(schema.startAt == "2026-05-15T08:00:00Z")
        #expect(schema.endAt == "2026-05-15T09:00:00Z")
        #expect(schema.deadlineAt == "2026-05-20T00:00:00Z")
        #expect(schema.priority == 2)
        #expect(schema.tags == ["shopping", "home"])
        #expect(schema.recurrence == "FREQ=WEEKLY;BYDAY=MO")
    }

    @Test("prompt template includes input verbatim")
    func promptIncludesInput() {
        let prompt = FMPromptTemplate.make(input: "kup mleko", now: Date(), locale: Locale(identifier: "pl"))
        #expect(prompt.contains("kup mleko"))
    }

    @Test("prompt template asks for JSON")
    func promptAsksJSON() {
        let prompt = FMPromptTemplate.make(input: "buy milk", now: Date(), locale: Locale(identifier: "en"))
        #expect(prompt.lowercased().contains("json"))
    }

    @Test("prompt template includes endAt schema key")
    func promptIncludesEndAt() {
        let prompt = FMPromptTemplate.make(input: "meeting 9-10", now: Date(), locale: Locale(identifier: "en"))
        #expect(prompt.contains(#""endAt": string | null"#))
        #expect(prompt.contains("duration/end time"))
    }

    @Test("prompt template includes deadlineAt schema key")
    func promptIncludesDeadlineAt() {
        let prompt = FMPromptTemplate.make(input: "ship deck by friday", now: Date(), locale: Locale(identifier: "en"))
        #expect(prompt.contains(#""deadlineAt": string | null"#))
        #expect(prompt.contains("deadline/by/termin"))
    }
}
