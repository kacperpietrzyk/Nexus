import Foundation
import NexusCore
import SwiftData
import SwiftUI

public struct ActionItemsReviewView: View {
    private let meetingID: UUID
    private let composition: MeetingsComposition

    @Environment(\.dismiss) private var dismiss
    @State private var autoItems: [TaskItem] = []
    @State private var selection: Set<UUID> = []

    public init(meetingID: UUID, composition: MeetingsComposition) {
        self.meetingID = meetingID
        self.composition = composition
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Review auto-created action items")
                    .font(.title3.weight(.semibold))

                Text("Select the ones to remove. Unchecked items stay in your Inbox.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)

            if autoItems.isEmpty {
                ContentUnavailableView(
                    "No action items",
                    systemImage: "checklist",
                    description: Text("There are no active auto-created tasks for this meeting.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(autoItems, id: \.id, selection: $selection) { task in
                    ActionItemsReviewRow(task: task)
                }
                .listStyle(.inset)
            }

            HStack {
                Button("Cancel") {
                    dismiss()
                }

                Spacer()

                Button("Delete selected", role: .destructive) {
                    deleteSelected()
                }
                .disabled(selection.isEmpty)
            }
            .padding([.horizontal, .bottom], 20)
        }
        .frame(minWidth: 420, minHeight: 360)
        .onAppear {
            reload()
        }
        .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { _ in
            reload()
        }
    }

    private func reload() {
        guard let meeting = try? composition.meetingRepository.find(id: meetingID) else {
            autoItems = []
            selection = []
            return
        }

        let ids = meeting.actionItemIDs
        guard !ids.isEmpty else {
            autoItems = []
            selection = []
            return
        }

        let descriptor = FetchDescriptor<TaskItem>(
            predicate: #Predicate { task in
                ids.contains(task.id) && task.deletedAt == nil
            }
        )

        guard let fetched = try? composition.taskItemRepository.context.fetch(descriptor) else {
            autoItems = []
            selection = []
            return
        }

        // Synced TaskItem ids are not unique (CloudKit forbids @Attribute(.unique)); a sync
        // conflict can yield duplicate ids. Dedup keep-first instead of trapping on the dup.
        let tasksByID = Dictionary(fetched.map { ($0.id, $0) }, uniquingKeysWith: { current, _ in current })
        autoItems = ids.compactMap { tasksByID[$0] }
        selection.formIntersection(Set(autoItems.map(\.id)))
    }

    private func deleteSelected() {
        guard !selection.isEmpty,
            let meeting = try? composition.meetingRepository.find(id: meetingID)
        else {
            return
        }

        let selectedIDs = selection
        let originalActionItemIDs = meeting.actionItemIDs
        let repository = composition.taskItemRepository
        var successfullyDeletedIDs = Set<UUID>()

        for task in autoItems where selectedIDs.contains(task.id) {
            removeActionItemID(task.id, from: meeting)
            do {
                try repository.softDelete(task)
                successfullyDeletedIDs.insert(task.id)
            } catch {
                restoreActionItemID(
                    task.id,
                    in: meeting,
                    originalActionItemIDs: originalActionItemIDs
                )
                continue
            }
        }

        guard !successfullyDeletedIDs.isEmpty else {
            reload()
            return
        }

        deleteActionItemLinks(
            meetingID: meeting.id,
            taskIDs: successfullyDeletedIDs
        )
        selection.subtract(successfullyDeletedIDs)
        reload()
    }

    private func removeActionItemID(_ taskID: UUID, from meeting: Meeting) {
        meeting.actionItemIDs.removeAll { $0 == taskID }
    }

    private func restoreActionItemID(
        _ taskID: UUID,
        in meeting: Meeting,
        originalActionItemIDs: [UUID]
    ) {
        guard !meeting.actionItemIDs.contains(taskID) else { return }

        let insertionIndex =
            originalActionItemIDs
            .prefix { $0 != taskID }
            .reduce(0) { count, id in
                count + (meeting.actionItemIDs.contains(id) ? 1 : 0)
            }
        meeting.actionItemIDs.insert(
            taskID,
            at: min(insertionIndex, meeting.actionItemIDs.count)
        )
    }

    private func deleteActionItemLinks(meetingID: UUID, taskIDs: Set<UUID>) {
        let linkRepository = LinkRepository(context: composition.meetingRepository.context)
        guard let links = try? linkRepository.outgoing(from: (.meeting, meetingID)) else { return }

        let actionItemLinks = links.filter { link in
            link.linkKind == .actionItem
                && link.toKind == .task
                && taskIDs.contains(link.toID)
        }

        for link in actionItemLinks {
            try? linkRepository.delete(link)
        }
    }
}

private struct ActionItemsReviewRow: View {
    let task: TaskItem
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(task.title)
                .font(.body.weight(.medium))

            let taskBody = ((try? TaskNoteContent.plainText(for: task, in: modelContext)) ?? task.body)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !taskBody.isEmpty {
                Text(taskBody)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }
}
