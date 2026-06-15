import Foundation
import Testing

@testable import NexusCore

@Suite("ActivityEntry")
struct ActivityEntryTests {
    @Test("ActivityEventKind raw values are pinned — they land in CloudKit, never rename after introduction")
    func eventKindRawValuesAreStable() {
        #expect(ActivityEventKind.created.rawValue == "created")
        #expect(ActivityEventKind.completed.rawValue == "completed")
        #expect(ActivityEventKind.reopened.rawValue == "reopened")
        #expect(ActivityEventKind.workflowChanged.rawValue == "workflowChanged")
        #expect(ActivityEventKind.projectMoved.rawValue == "projectMoved")
        #expect(ActivityEventKind.priorityChanged.rawValue == "priorityChanged")
        #expect(ActivityEventKind.dueChanged.rawValue == "dueChanged")
        #expect(ActivityEventKind.cycleChanged.rawValue == "cycleChanged")
        #expect(ActivityEventKind.deleted.rawValue == "deleted")
        #expect(
            ActivityEventKind.allCases == [
                .created, .completed, .reopened, .workflowChanged, .projectMoved,
                .priorityChanged, .dueChanged, .cycleChanged, .deleted,
            ]
        )
    }

    @Test("ActivityEventKind is Codable round-trip")
    func eventKindIsCodable() throws {
        for kind in ActivityEventKind.allCases {
            let encoded = try JSONEncoder().encode(kind)
            let decoded = try JSONDecoder().decode(ActivityEventKind.self, from: encoded)
            #expect(decoded == kind)
        }
    }

    @Test("init sets the polymorphic anchor and defaults")
    func initSetsAnchorAndDefaults() {
        let itemID = UUID()
        let entry = ActivityEntry(itemID: itemID, itemKind: .task, eventKind: .created)

        #expect(entry.itemID == itemID)
        #expect(entry.itemKindRaw == "task")
        #expect(entry.eventKindRaw == "created")
        #expect(entry.payloadJSON == nil)
    }

    @Test("accessors decode known raws and nil out unknown raws (forward compat — render generic, never crash)")
    func accessorsFollowWorkflowStateIdiom() {
        let entry = ActivityEntry(
            itemID: UUID(),
            itemKind: .task,
            eventKind: .workflowChanged,
            payloadJSON: "{\"old\":\"todo\",\"new\":\"inProgress\"}"
        )
        #expect(entry.itemKind == .task)
        #expect(entry.eventKind == .workflowChanged)
        #expect(entry.payloadJSON == "{\"old\":\"todo\",\"new\":\"inProgress\"}")

        entry.itemKindRaw = "not-a-kind"
        entry.eventKindRaw = "future-event-kind"
        #expect(entry.itemKind == nil)
        #expect(entry.eventKind == nil)
    }
}
