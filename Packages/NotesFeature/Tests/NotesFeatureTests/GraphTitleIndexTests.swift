import Foundation
import NexusCore
import SwiftData
import Testing

@testable import NotesFeature

@Suite("GraphTitleIndex - store-backed title resolution")
struct GraphTitleIndexTests {
    @MainActor
    private func makeContext() throws -> ModelContext {
        let schema = Schema([
            Note.self, TaskItem.self, Project.self, Person.self,
            Label.self, Cycle.self, Link.self,
        ])
        let config = ModelConfiguration(
            schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none
        )
        return ModelContext(try ModelContainer(for: schema, configurations: [config]))
    }

    @MainActor
    @Test("indexes live core items under their (kind, id)")
    func indexesCoreKinds() throws {
        let context = try makeContext()
        let note = Note(title: "My note")
        let task = TaskItem(title: "My task")
        let project = Project(name: "My project")
        context.insert(note)
        context.insert(task)
        context.insert(project)
        try context.save()

        let titles = try GraphTitleIndex.build(context: context)

        #expect(titles[GraphNodeID(.note, note.id)] == "My note")
        #expect(titles[GraphNodeID(.task, task.id)] == "My task")
        #expect(titles[GraphNodeID(.project, project.id)] == "My project")
    }

    @MainActor
    @Test("tombstoned items are not indexed")
    func excludesTombstones() throws {
        let context = try makeContext()
        let live = Note(title: "live")
        let dead = Note(title: "dead")
        dead.deletedAt = .now
        context.insert(live)
        context.insert(dead)
        try context.save()

        let titles = try GraphTitleIndex.build(context: context)
        #expect(titles[GraphNodeID(.note, live.id)] == "live")
        #expect(titles[GraphNodeID(.note, dead.id)] == nil)
    }

    @MainActor
    @Test("external titles (host-resolved kinds, e.g. meetings) merge in")
    func mergesExternalTitles() throws {
        let context = try makeContext()
        let meetingID = UUID()

        let titles = try GraphTitleIndex.build(
            context: context,
            external: [.meeting: [meetingID: "Sprint sync"]]
        )
        #expect(titles[GraphNodeID(.meeting, meetingID)] == "Sprint sync")
    }

    @MainActor
    @Test("GraphLinkRecord copies a Link row's endpoints + kind")
    func linkRecordMapping() throws {
        let context = try makeContext()
        let repo = LinkRepository(context: context)
        let from = UUID()
        let to = UUID()
        let link = try repo.create(from: (.note, from), to: (.task, to), linkKind: .containsTask)

        let record = GraphLinkRecord(link)
        #expect(record.from == GraphNodeID(.note, from))
        #expect(record.to == GraphNodeID(.task, to))
        #expect(record.linkKind == .containsTask)
    }
}
