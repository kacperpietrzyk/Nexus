import Foundation
import InboxShell
import NexusCore
import SwiftData

public actor MeetingActionItemsInboxSource: InboxSource {
    public static let identifier = "meetings.action-items"

    public let id = MeetingActionItemsInboxSource.identifier
    public let displayName = "Meeting action items"
    public let iconName = "person.wave.2"

    private let meetingRepository: MeetingRepository
    private let taskRepository: TaskItemRepository
    private let linkRepository: LinkRepository

    public init(
        meetingRepository: MeetingRepository,
        taskRepository: TaskItemRepository,
        linkRepository: LinkRepository
    ) {
        self.meetingRepository = meetingRepository
        self.taskRepository = taskRepository
        self.linkRepository = linkRepository
    }

    public func items() async throws -> [InboxItem] {
        let sourceID = id
        return try await MainActor.run {
            let meetings = try meetingRepository.allChronological().filter { $0.deletedAt == nil }
            let taskIDsByMeetingID = try meetings.reduce(into: [UUID: Set<UUID>]()) { result, meeting in
                let links = try linkRepository.outgoing(from: (.meeting, meeting.id))
                let taskIDs = links.compactMap { link -> UUID? in
                    guard link.linkKind == .actionItem, link.toKind == .task else { return nil }
                    return link.toID
                }
                if taskIDs.isEmpty == false {
                    result[meeting.id] = Set(taskIDs)
                }
            }
            let allTaskIDs = Set(taskIDsByMeetingID.values.flatMap { $0 })
            guard allTaskIDs.isEmpty == false else { return [] }

            let openStatus = TaskStatus.open.rawValue
            let taskDescriptor = FetchDescriptor<TaskItem>(
                predicate: #Predicate { task in
                    task.deletedAt == nil && task.statusRaw == openStatus
                }
            )
            // Synced TaskItem ids are not unique (CloudKit forbids @Attribute(.unique)); a sync
            // conflict can yield duplicate ids. Dedup keep-first instead of trapping on the dup.
            let tasksByID = Dictionary(
                try taskRepository.context.fetch(taskDescriptor)
                    .filter { allTaskIDs.contains($0.id) }
                    .map { ($0.id, $0) },
                uniquingKeysWith: { current, _ in current }
            )

            return meetings.flatMap { meeting -> [InboxItem] in
                guard let taskIDs = taskIDsByMeetingID[meeting.id] else { return [] }
                return taskIDs.compactMap { taskID in
                    guard let task = tasksByID[taskID] else { return nil }
                    return InboxItem(
                        id: task.id,
                        sourceID: sourceID,
                        title: task.title,
                        body: "from meeting: \(meeting.title)",
                        due: task.dueAt,
                        tags: task.tags,
                        createdAt: task.createdAt
                    )
                }
            }
            .sorted {
                if $0.createdAt != $1.createdAt {
                    return $0.createdAt > $1.createdAt
                }
                return $0.title < $1.title
            }
        }
    }

    public func archive(_ item: InboxItem) async throws {
        let id = item.id
        try await MainActor.run {
            guard let task = try self.task(id: id) else { return }
            try taskRepository.softDelete(task)
        }
    }

    public func snooze(_ item: InboxItem, until date: Date) async throws {
        let id = item.id
        try await MainActor.run {
            guard let task = try self.task(id: id) else { return }
            try taskRepository.snooze(task, until: date)
        }
    }

    @MainActor
    private func task(id: UUID) throws -> TaskItem? {
        var descriptor = FetchDescriptor<TaskItem>(
            predicate: #Predicate { task in
                task.id == id && task.deletedAt == nil
            }
        )
        descriptor.fetchLimit = 1
        return try taskRepository.context.fetch(descriptor).first
    }
}
