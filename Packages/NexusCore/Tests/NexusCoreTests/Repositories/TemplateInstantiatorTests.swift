import Foundation
import SwiftData
import Testing

@testable import NexusCore

@Suite("TemplateInstantiator")
struct TemplateInstantiatorTests {
    @MainActor
    struct Harness {
        let context: ModelContext
        let repo: TaskItemRepository
        let instantiator: TemplateInstantiator
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        init() throws {
            let schema = Schema([TaskItem.self, Note.self, Link.self])
            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
            let container = try ModelContainer(for: schema, configurations: [config])
            self.context = ModelContext(container)
            self.repo = TaskItemRepository(
                context: context,
                scheduler: RRuleScheduler(),
                now: { Date(timeIntervalSince1970: 1_800_000_000) }
            )
            self.instantiator = TemplateInstantiator(tasks: repo)
        }
    }

    @MainActor
    @Test("instantiate copies scalars verbatim and nils every date")
    func instantiateCopyRules() throws {
        let harness = try Harness()
        let projectID = UUID()
        let template = TaskItem(
            title: "Weekly report",
            dueAt: harness.now,
            startAt: harness.now,
            endAt: harness.now.addingTimeInterval(3_600),
            deadlineAt: harness.now.addingTimeInterval(7_200),
            priority: .high,
            tags: ["work"],
            recurrenceRule: "FREQ=WEEKLY",
            projectID: projectID,
            orderIndex: 4,
            pinnedAsFocus: true,
            workflowState: .inProgress,
            estimatedDurationSeconds: 1_800,
            isTemplate: true
        )
        harness.context.insert(template)
        try harness.context.save()

        let instance = try harness.instantiator.instantiate(template)

        #expect(instance.id != template.id)
        #expect(instance.isTemplate == false)
        #expect(instance.title == "Weekly report")
        #expect(instance.tags == ["work"])
        #expect(instance.priority == .high)
        #expect(instance.projectID == projectID)
        #expect(instance.orderIndex == 4)
        #expect(instance.pinnedAsFocus == true)
        #expect(instance.estimatedDurationSeconds == 1_800)
        #expect(instance.recurrenceRule == "FREQ=WEEKLY")
        #expect(instance.recurrenceParentId == nil)
        #expect(instance.dueAt == nil)
        #expect(instance.startAt == nil)
        #expect(instance.endAt == nil)
        #expect(instance.deadlineAt == nil)
        #expect(instance.snoozedUntil == nil)
        #expect(instance.status == .open)
        #expect(instance.lastCompletedAt == nil)
        #expect(instance.externalSourceID == nil)
        #expect(instance.externalSourceMetadata == nil)
        // Project-tier workflow resets to .todo (makeNextOccurrence precedent).
        #expect(instance.workflowState == .todo)
        // Persisted (went through repository.insert).
        let titles = try harness.context.fetch(FetchDescriptor<TaskItem>()).map(\.title)
        #expect(titles.sorted() == ["Weekly report", "Weekly report"])
    }

    @MainActor
    @Test("instantiate keeps a GTD template's workflow nil (I7)")
    func instantiateKeepsGTDWorkflowNil() throws {
        let harness = try Harness()
        let template = TaskItem(title: "gtd tpl", isTemplate: true)
        harness.context.insert(template)
        try harness.context.save()

        let instance = try harness.instantiator.instantiate(template)
        #expect(instance.workflowState == nil)
        #expect(instance.workflowStateRaw == nil)
    }

    @MainActor
    @Test("instantiate carries relative reminders only (carriedReminders filter)")
    func instantiateCarriesRelativeRemindersOnly() throws {
        let harness = try Harness()
        let template = TaskItem(title: "tpl", isTemplate: true)
        template.reminders = [
            .relative(offset: -3_600, anchor: .due),
            .absolute(harness.now),
        ]
        harness.context.insert(template)
        try harness.context.save()

        let instance = try harness.instantiator.instantiate(template)
        #expect(instance.reminders == [.relative(offset: -3_600, anchor: .due)])
    }

    @MainActor
    @Test("instantiate deep-copies the backing note (duplicatedNoteRef / T1)")
    func instantiateDuplicatesNote() throws {
        let harness = try Harness()
        let note = Note(title: "Checklist", plainText: "step 1")
        harness.context.insert(note)
        let template = TaskItem(title: "tpl", noteRef: note.id, isTemplate: true)
        harness.context.insert(template)
        try harness.context.save()

        let instance = try harness.instantiator.instantiate(template)

        let copyRef = try #require(instance.noteRef)
        #expect(copyRef != note.id)
        let notes = try harness.context.fetch(FetchDescriptor<Note>())
        let copy = try #require(notes.first { $0.id == copyRef })
        #expect(copy.title == "Checklist")
        #expect(copy.plainText == "step 1")
    }

    @MainActor
    @Test("saveAsTemplate copies into an inert blueprint and leaves the source untouched")
    func saveAsTemplateRules() throws {
        let harness = try Harness()
        let source = TaskItem(title: "Ship release", dueAt: harness.now, tags: ["release"])
        try harness.repo.insert(source)

        let template = try harness.instantiator.saveAsTemplate(source)

        #expect(template.isTemplate == true)
        #expect(template.id != source.id)
        #expect(template.title == "Ship release")
        #expect(template.tags == ["release"])
        #expect(template.dueAt == nil)
        #expect(template.status == .open)
        // Source untouched.
        #expect(source.isTemplate == false)
        #expect(source.dueAt == harness.now)
    }

    @MainActor
    @Test("instantiate rejects non-templates; saveAsTemplate rejects templates")
    func guardErrors() throws {
        let harness = try Harness()
        let live = TaskItem(title: "live")
        let template = TaskItem(title: "tpl", isTemplate: true)
        harness.context.insert(live)
        harness.context.insert(template)
        try harness.context.save()

        #expect(throws: TemplateInstantiatorError.notATemplate(taskID: live.id)) {
            try harness.instantiator.instantiate(live)
        }
        #expect(throws: TemplateInstantiatorError.alreadyATemplate(taskID: template.id)) {
            try harness.instantiator.saveAsTemplate(template)
        }
    }
}
