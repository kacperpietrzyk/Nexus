import Foundation
import NexusCore
import SwiftData

// MARK: - project_overview

/// Returns the full state of a project in one read: project metadata (status, stage,
/// title), all live tasks, note references (canonical page note + linked notes via the
/// graph), linked meeting IDs (UUID refs only — `Meeting` lives in `NexusMeetings`,
/// which this package does not import), and ordered sections. Counts are included on
/// every collection.
///
/// Meeting link direction: the tool queries *both* backlinks from meetings to the
/// project **and** outgoing links from the project to meetings so the caller sees all
/// 1-hop meeting neighbours regardless of which side created the edge.
public struct ProjectOverviewTool: AgentTool {
    public let name = "projects.overview"
    public let description =
        "Returns the full state of a project in one call: project metadata (status, stage, title), "
        + "all live tasks (with count), note references (canonical page note + graph-linked notes, "
        + "with count), linked meeting IDs (with count — meeting data lives in a separate layer; "
        + "use meetings.get for details), and ordered sections (with count). "
        + "Throws notFound when the project_id is unknown or soft-deleted."
    public let inputSchema: JSONSchema = .object(
        properties: [
            "project_id": .string(description: "Project UUID to fetch.")
        ],
        required: ["project_id"]
    )

    public init() {}

    @MainActor
    public func call(args: JSONValue, context: AgentContext) async throws -> JSONValue {
        let id = try TasksToolArguments.requiredUUID(args["project_id"], field: "project_id")
        let project = try ProjectsToolSupport.liveProject(id: id, context: context)

        // --- Tasks ---
        let tasks = try context.taskRepository.repository.tasks(in: project.id)
        let taskDTOs = tasks.map { TaskDTO(from: $0) }

        // --- Sections ---
        let sections = try SectionRepository(context: context.modelContext.context, now: context.now)
            .sections(in: project.id)
        let sectionDTOs = sections.map { SectionDTO(from: $0) }

        // --- Links (fetch once, reuse for notes and meetings) ---
        let outgoing = try context.linkRepository.outgoing(from: (.project, project.id))
        let backlinks = try context.linkRepository.backlinks(to: (.project, project.id))

        // --- Notes ---
        // Collect note IDs from: canonicalNoteRef + outgoing project→note links +
        // backlinks note→project. Deduplicate while preserving insertion order so the
        // canonical note always comes first.
        var noteIDs: [UUID] = []
        var seenNoteIDs: Set<UUID> = []

        func insertNote(_ noteID: UUID) {
            guard seenNoteIDs.insert(noteID).inserted else { return }
            noteIDs.append(noteID)
        }

        if let canonical = project.canonicalNoteRef {
            insertNote(canonical)
        }
        for link in outgoing where link.toKind == .note {
            insertNote(link.toID)
        }
        for link in backlinks where link.fromKind == .note {
            insertNote(link.fromID)
        }

        var noteRefs: [NoteRef] = []
        for noteID in noteIDs {
            if let note = try context.noteRepository.find(id: noteID) {
                noteRefs.append(
                    NoteRef(
                        id: note.id.uuidString,
                        title: note.title.isEmpty ? "Untitled" : note.title,
                        isCanonical: note.id == project.canonicalNoteRef
                    ))
            }
        }

        // --- Meetings (IDs only — Meeting entity is in NexusMeetings, not importable here) ---
        var meetingIDs: [UUID] = []
        var seenMeetingIDs: Set<UUID> = []

        func insertMeeting(_ meetingID: UUID) {
            guard seenMeetingIDs.insert(meetingID).inserted else { return }
            meetingIDs.append(meetingID)
        }

        for link in backlinks where link.fromKind == .meeting {
            insertMeeting(link.fromID)
        }
        for link in outgoing where link.toKind == .meeting {
            insertMeeting(link.toID)
        }
        let meetingRefs = meetingIDs.map { MeetingRef(id: $0.uuidString) }

        // --- Project metadata ---
        let projectDTO = ProjectDTO(from: project, sections: sections, taskCount: tasks.count)

        // --- Composite payload ---
        let payload = ProjectOverviewPayload(
            project: projectDTO,
            tasks: TasksCollection(items: taskDTOs, count: taskDTOs.count),
            notes: NotesCollection(items: noteRefs, count: noteRefs.count),
            meetings: MeetingsCollection(items: meetingRefs, count: meetingRefs.count),
            sections: SectionsCollection(items: sectionDTOs, count: sectionDTOs.count)
        )
        return try TasksToolJSON.encode(payload)
    }
}

// MARK: - Slim ref types

private struct NoteRef: Encodable {
    let id: String
    let title: String
    let isCanonical: Bool

    private enum CodingKeys: String, CodingKey {
        case id, title
        case isCanonical = "is_canonical"
    }
}

private struct MeetingRef: Encodable {
    let id: String
}

// MARK: - Collection wrappers

private struct TasksCollection: Encodable {
    let items: [TaskDTO]
    let count: Int
}

private struct NotesCollection: Encodable {
    let items: [NoteRef]
    let count: Int
}

private struct MeetingsCollection: Encodable {
    let items: [MeetingRef]
    let count: Int
}

private struct SectionsCollection: Encodable {
    let items: [SectionDTO]
    let count: Int
}

// MARK: - Root payload

private struct ProjectOverviewPayload: Encodable {
    let project: ProjectDTO
    let tasks: TasksCollection
    let notes: NotesCollection
    let meetings: MeetingsCollection
    let sections: SectionsCollection
}
