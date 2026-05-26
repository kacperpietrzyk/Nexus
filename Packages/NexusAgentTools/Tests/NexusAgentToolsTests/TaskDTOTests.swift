import Foundation
import NexusCore
import Testing

@testable import NexusAgentTools

@Suite("TaskDTO")
struct TaskDTOTests {
    @MainActor
    @Test("encodes TaskItem to snake_case JSON")
    func basicEncoding() throws {
        let task = TaskItem(
            title: "Plan tomorrow",
            body: "Draft the morning plan",
            tags: ["planning", "today"]
        )

        let object = try encodedObject(TaskDTO(from: task))

        #expect(object["title"] as? String == "Plan tomorrow")
        #expect(object["notes"] as? String == "Draft the morning plan")
        #expect(object["state"] as? String == "open")
        #expect(object["tags"] as? [String] == ["planning", "today"])
        #expect(object["due_date"] == nil)
        #expect(object["deadline_date"] == nil)
    }

    @MainActor
    @Test("encodes due_date and deadline_date when present")
    func dates() throws {
        let dueAt = try #require(ISO8601DateFormatter().date(from: "2026-05-07T09:30:00Z"))
        let deadlineAt = try #require(ISO8601DateFormatter().date(from: "2026-05-09T17:00:00Z"))
        let task = TaskItem(title: "Submit report", dueAt: dueAt, deadlineAt: deadlineAt)
        task.createdAt = dueAt
        task.updatedAt = dueAt

        let object = try encodedObject(TaskDTO(from: task))

        #expect(object["due_date"] as? String == "2026-05-07T09:30:00.000Z")
        #expect(object["deadline_date"] as? String == "2026-05-09")
        #expect(object["created_at"] as? String == "2026-05-07T09:30:00.000Z")
        #expect(object["updated_at"] as? String == "2026-05-07T09:30:00.000Z")
    }

    @MainActor
    @Test("deadline_date preserves local date for non-UTC all-day deadlines")
    func deadlineDateUsesLocalCalendarSemantics() throws {
        var warsawCalendar = Calendar(identifier: .iso8601)
        warsawCalendar.timeZone = try #require(TimeZone(identifier: "Europe/Warsaw"))
        let deadlineAt = try #require(
            warsawCalendar.date(from: DateComponents(year: 2026, month: 5, day: 5, hour: 0, minute: 0))
        )
        let task = TaskItem(title: "Submit report", deadlineAt: deadlineAt)

        let object = try encodedObject(TaskDTO(from: task, deadlineCalendar: warsawCalendar))

        #expect(object["deadline_date"] as? String == "2026-05-05")
    }

    @MainActor
    @Test("state reflects done vs open vs deleted")
    func stateMapping() {
        let openTask = TaskItem(title: "Open")
        let doneTask = TaskItem(title: "Done", status: .done)
        let deletedTask = TaskItem(title: "Deleted", status: .done)
        deletedTask.deletedAt = Date()
        let deletedSnoozedTask = TaskItem(title: "Deleted Snoozed", status: .snoozed)
        deletedSnoozedTask.deletedAt = Date()

        #expect(TaskDTO(from: openTask).state == "open")
        #expect(TaskDTO(from: doneTask).state == "done")
        #expect(TaskDTO(from: deletedTask).state == "deleted")
        #expect(TaskDTO(from: deletedSnoozedTask).state == "deleted")
    }

    @MainActor
    @Test("snoozed tasks encode open state plus snooze_until")
    func snoozedStateMapping() throws {
        let snoozedUntil = try #require(ISO8601DateFormatter().date(from: "2026-05-08T18:45:00Z"))
        let task = TaskItem(title: "Follow up", status: .snoozed)
        task.snoozedUntil = snoozedUntil

        let dto = TaskDTO(from: task)
        let object = try encodedObject(dto)

        #expect(dto.state == "open")
        #expect(object["state"] as? String == "open")
        #expect(object["snooze_until"] as? String == "2026-05-08T18:45:00.000Z")
    }

    @MainActor
    @Test("priority maps to 1=highest..4=lowest")
    func priorityMapping() {
        #expect(TaskDTO(from: TaskItem(title: "High", priority: .high)).priority == 1)
        #expect(TaskDTO(from: TaskItem(title: "Medium", priority: .medium)).priority == 2)
        #expect(TaskDTO(from: TaskItem(title: "Low", priority: .low)).priority == 3)
        #expect(TaskDTO(from: TaskItem(title: "None", priority: .none)).priority == 4)
    }

    @MainActor
    @Test("includes externalSourceID when set")
    func externalSourceID() throws {
        let task = TaskItem(title: "Imported")
        task.externalSourceID = "todoist:8237162"

        let object = try encodedObject(TaskDTO(from: task))

        #expect(object["external_source_id"] as? String == "todoist:8237162")
    }

    @MainActor
    @Test("response DTOs encode snake_case keys")
    func responseDTOKeys() throws {
        let taskDTO = TaskDTO(from: TaskItem(title: "Draft"))

        let list = try encodedObject(TaskListResponseDTO(tasks: [taskDTO], total: 1, hasMore: true))
        #expect(list["tasks"] is [[String: Any]])
        #expect(list["total"] as? Int == 1)
        #expect(list["has_more"] as? Bool == true)

        let idempotent = try encodedObject(IdempotentResponseDTO(task: taskDTO, wasCreated: false))
        #expect(idempotent["task"] is [String: Any])
        #expect(idempotent["was_created"] as? Bool == false)

        let summary = try encodedObject(
            DailySummaryDTO(
                heroBrief: "Clear the inbox",
                today: [taskDTO],
                upcoming: [],
                focusBuckets: FocusBucketsDTO(am: [taskDTO], pm: [], evening: [])
            )
        )
        let focusBuckets = try #require(summary["focus_buckets"] as? [String: Any])
        #expect(summary["hero_brief"] as? String == "Clear the inbox")
        #expect(focusBuckets["am"] is [[String: Any]])
        #expect(focusBuckets["pm"] is [[String: Any]])
        #expect(focusBuckets["evening"] is [[String: Any]])

        let error = try encodedObject(ErrorDTO(from: .validation("Title is required")))
        #expect(error["code"] as? Int == -32004)
        #expect(error["name"] as? String == "validation")
        #expect(error["message"] as? String == "Title is required")
    }

    private func encodedObject(_ value: some Encodable) throws -> [String: Any] {
        let data = try JSONEncoder().encode(value)
        let object = try JSONSerialization.jsonObject(with: data)
        return try #require(object as? [String: Any])
    }
}
