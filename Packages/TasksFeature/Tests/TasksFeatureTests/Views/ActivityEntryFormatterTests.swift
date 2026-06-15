import Foundation
import NexusCore
import Testing

@testable import TasksFeature

@Suite("ActivityEntryFormatter")
struct ActivityEntryFormatterTests {

    private func entry(
        _ kind: ActivityEventKind,
        old: String? = nil,
        new: String? = nil,
        hasPayload: Bool = false
    ) -> ActivityEntry {
        ActivityEntry(
            itemID: UUID(),
            itemKind: .task,
            eventKind: kind,
            payloadJSON: hasPayload ? ActivityChangePayload(old: old, new: new).encodedJSON : nil
        )
    }

    @Test("lifecycle kinds render fixed sentences")
    func lifecycleSentences() {
        #expect(ActivityEntryFormatter.sentence(for: entry(.created)) == "created")
        #expect(ActivityEntryFormatter.sentence(for: entry(.completed)) == "completed")
        #expect(ActivityEntryFormatter.sentence(for: entry(.reopened)) == "reopened")
        #expect(ActivityEntryFormatter.sentence(for: entry(.deleted)) == "deleted")
    }

    @Test("workflowChanged maps the new raw through WorkflowState display names")
    func workflowSentence() {
        let moved = entry(.workflowChanged, old: "todo", new: "inProgress", hasPayload: true)
        #expect(ActivityEntryFormatter.sentence(for: moved) == "moved to In Progress")
        let unknown = entry(.workflowChanged, old: "todo", new: "futureState", hasPayload: true)
        #expect(ActivityEntryFormatter.sentence(for: unknown) == "status changed")
    }

    @Test("projectMoved resolves the project name when the resolver knows it")
    func projectSentence() {
        let projectID = UUID()
        let moved = entry(.projectMoved, old: nil, new: projectID.uuidString, hasPayload: true)
        let named = ActivityEntryFormatter.sentence(for: moved) { id in
            id == projectID ? "Website" : nil
        }
        #expect(named == "moved to Website")
        let unnamed = ActivityEntryFormatter.sentence(for: moved)
        #expect(unnamed == "moved to another project")
        let removed = entry(.projectMoved, old: projectID.uuidString, new: nil, hasPayload: true)
        #expect(ActivityEntryFormatter.sentence(for: removed) == "removed from project")
    }

    @Test("priorityChanged renders the new priority's display name")
    func prioritySentence() {
        let raised = entry(.priorityChanged, old: "0", new: "3", hasPayload: true)
        #expect(ActivityEntryFormatter.sentence(for: raised) == "priority set to High")
        let garbage = entry(.priorityChanged, old: "0", new: "99", hasPayload: true)
        #expect(ActivityEntryFormatter.sentence(for: garbage) == "priority changed")
    }

    @Test("dueChanged renders set vs removed (locale-agnostic assertions)")
    func dueSentence() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let set = entry(.dueChanged, old: nil, new: ActivityChangePayload.dateString(date), hasPayload: true)
        #expect(ActivityEntryFormatter.sentence(for: set).hasPrefix("due "))
        let removed = entry(.dueChanged, old: ActivityChangePayload.dateString(date), new: nil, hasPayload: true)
        #expect(ActivityEntryFormatter.sentence(for: removed) == "due date removed")
    }

    @Test("cycleChanged renders moved vs removed")
    func cycleSentence() {
        let moved = entry(.cycleChanged, old: nil, new: UUID().uuidString, hasPayload: true)
        #expect(ActivityEntryFormatter.sentence(for: moved) == "moved to another cycle")
        let removed = entry(.cycleChanged, old: UUID().uuidString, new: nil, hasPayload: true)
        #expect(ActivityEntryFormatter.sentence(for: removed) == "removed from cycle")
    }

    @Test("unknown event kind (synced from a newer build) degrades to 'updated', never crashes")
    func unknownKindDegrades() {
        let future = ActivityEntry(itemID: UUID(), itemKind: .task, eventKind: .created)
        future.eventKindRaw = "somethingFromTheFuture"
        #expect(ActivityEntryFormatter.sentence(for: future) == "updated")
    }
}
