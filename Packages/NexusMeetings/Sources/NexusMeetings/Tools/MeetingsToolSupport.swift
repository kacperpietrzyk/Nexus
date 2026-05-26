import Foundation
import NexusAgentTools
import NexusCore
import SwiftData

enum MeetingsToolJSON {
    static func encode(_ value: some Encodable) throws -> JSONValue {
        let data = try JSONEncoder().encode(value)
        return try JSONDecoder().decode(JSONValue.self, from: data)
    }
}

enum MeetingsToolArguments {
    static func requiredString(_ value: JSONValue?, field: String) throws -> String {
        guard let text = value?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
            text.isEmpty == false
        else {
            throw AgentError.validation("Missing required string field: \(field)")
        }
        return text
    }

    static func requiredUUID(_ value: JSONValue?, field: String) throws -> UUID {
        let text = try requiredString(value, field: field)
        guard let id = UUID(uuidString: text) else {
            throw AgentError.validation("Invalid UUID for field: \(field)")
        }
        return id
    }

    static func optionalBool(_ value: JSONValue?, field: String, default defaultValue: Bool) throws -> Bool {
        guard let value else { return defaultValue }
        guard let boolValue = value.boolValue else {
            throw AgentError.validation("\(field) must be a boolean")
        }
        return boolValue
    }

    static func boundedInt(
        _ value: JSONValue?,
        field: String,
        default defaultValue: Int,
        range: ClosedRange<Int>
    ) throws -> Int {
        guard let value else { return defaultValue }
        guard let intValue = value.intValue, range.contains(intValue) else {
            throw AgentError.validation("Invalid integer for field: \(field)")
        }
        return intValue
    }

    static func requiredDate(_ value: JSONValue?, field: String) throws -> Date {
        let text = try requiredString(value, field: field)
        if let date = MeetingsToolFormatters.date(from: text) {
            return date
        }
        throw AgentError.validation("Invalid ISO8601 date for field: \(field)")
    }
}

enum MeetingsToolFormatters {
    static func string(from date: Date) -> String {
        fractionalFormatter().string(from: date)
    }

    static func date(from text: String) -> Date? {
        fractionalFormatter().date(from: text) ?? wholeSecondFormatter().date(from: text)
    }

    private static func fractionalFormatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }

    private static func wholeSecondFormatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }
}

struct MeetingSnapshotDTO: Codable, Equatable {
    let id: String
    let title: String
    let startedAt: String
    let durationSec: Int
    let summaryExcerpt: String

    init(meeting: Meeting) {
        self.id = meeting.id.uuidString
        self.title = meeting.title
        self.startedAt = MeetingsToolFormatters.string(from: meeting.startedAt)
        self.durationSec = meeting.durationSec
        self.summaryExcerpt = String(meeting.summaryText.prefix(200))
    }
}

struct MeetingTaskSnapshotDTO: Codable, Equatable {
    let id: String
    let title: String
    let state: String
    let dueAt: String?
    let createdAt: String

    init(task: TaskItem) {
        self.id = task.id.uuidString
        self.title = task.title
        self.state = task.statusRaw
        self.dueAt = task.dueAt.map(MeetingsToolFormatters.string(from:))
        self.createdAt = MeetingsToolFormatters.string(from: task.createdAt)
    }
}

extension MeetingRepository {
    func existingMeeting(id: UUID) throws -> Meeting {
        guard let meeting = try find(id: id), meeting.deletedAt == nil else {
            throw AgentError.notFound("Meeting not found: \(id.uuidString)")
        }
        return meeting
    }
}
