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
    @Test("T4: instantiate carries repeating absolute reminders, still drops one-shots")
    func instantiateCarriesRepeatingAbsoluteReminders() throws {
        let harness = try Harness()
        let template = TaskItem(title: "tpl", isTemplate: true)
        template.reminders = [
            .absolute(harness.now),
            .absolute(at: harness.now, repeats: .weekly),
        ]
        harness.context.insert(template)
        try harness.context.save()

        let instance = try harness.instantiator.instantiate(template)
        #expect(instance.reminders == [.absolute(at: harness.now, repeats: .weekly)])
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

    @MainActor
    @Test("instantiate recreates the subtask tree with remapped parents")
    func instantiateRecreatesSubtaskTree() throws {
        let harness = try Harness()
        let root = TaskItem(title: "tpl root", isTemplate: true)
        harness.context.insert(root)
        let child = TaskItem(title: "tpl child", parentTaskID: root.id, isTemplate: true)
        harness.context.insert(child)
        let grandchild = TaskItem(title: "tpl grandchild", parentTaskID: child.id, isTemplate: true)
        harness.context.insert(grandchild)
        try harness.context.save()

        let instance = try harness.instantiator.instantiate(root)

        let all = try harness.context.fetch(FetchDescriptor<TaskItem>())
        let copies = all.filter { !$0.isTemplate }
        #expect(copies.count == 3)
        let newChild = try #require(copies.first { $0.title == "tpl child" })
        let newGrandchild = try #require(copies.first { $0.title == "tpl grandchild" })
        #expect(newChild.parentTaskID == instance.id)
        #expect(newGrandchild.parentTaskID == newChild.id)
        #expect(copies.allSatisfy { $0.status == .open && $0.dueAt == nil })
    }

    @MainActor
    @Test("saveAsTemplate marks every copied node as a template")
    func saveAsTemplateMarksWholeTree() throws {
        let harness = try Harness()
        let root = TaskItem(title: "live root")
        try harness.repo.insert(root)
        let child = TaskItem(title: "live child", parentTaskID: root.id)
        try harness.repo.insert(child)

        let template = try harness.instantiator.saveAsTemplate(root)

        let all = try harness.context.fetch(FetchDescriptor<TaskItem>())
        let templates = all.filter(\.isTemplate)
        #expect(templates.count == 2)
        let templateChild = try #require(templates.first { $0.title == "live child" })
        #expect(templateChild.parentTaskID == template.id)
        // Originals untouched.
        #expect(root.isTemplate == false)
        #expect(child.isTemplate == false)
    }

    @MainActor
    @Test("instantiate recreates outgoing links, remaps intra-tree targets, skips scheduledAs")
    func instantiateRecreatesLinks() throws {
        let harness = try Harness()
        let links = LinkRepository(context: harness.context)
        let root = TaskItem(title: "tpl root", isTemplate: true)
        harness.context.insert(root)
        let child = TaskItem(title: "tpl child", parentTaskID: root.id, isTemplate: true)
        harness.context.insert(child)
        try harness.context.save()

        let labelID = UUID()
        let blockID = UUID()
        try links.create(from: (.task, root.id), to: (.label, labelID), linkKind: .labeled)
        try links.create(from: (.task, root.id), to: (.task, child.id), linkKind: .blocks)
        try links.create(from: (.task, root.id), to: (.scheduledBlock, blockID), linkKind: .scheduledAs)

        let instance = try harness.instantiator.instantiate(root)

        let outgoing = try links.outgoing(from: (.task, instance.id))
        #expect(outgoing.count == 2)
        let labeled = try #require(outgoing.first { $0.linkKind == .labeled })
        #expect(labeled.toKind == .label)
        #expect(labeled.toID == labelID)
        let blocks = try #require(outgoing.first { $0.linkKind == .blocks })
        let newChild = try #require(
            try harness.context.fetch(FetchDescriptor<TaskItem>())
                .first { !$0.isTemplate && $0.title == "tpl child" }
        )
        #expect(blocks.toID == newChild.id)  // intra-tree target remapped
        #expect(outgoing.allSatisfy { $0.linkKind != .scheduledAs })
        // Template's own links untouched.
        #expect(try links.outgoing(from: (.task, root.id)).count == 3)
    }
}
