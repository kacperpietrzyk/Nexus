import Foundation
import NexusCore
import SwiftData
import SwiftUI

public struct ActionItemsTabView: View {
    private let meetingID: UUID
    private let composition: MeetingsComposition

    @State private var actionItems: [TaskItem] = []

    public init(meetingID: UUID, composition: MeetingsComposition) {
        self.meetingID = meetingID
        self.composition = composition
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Action items")
                .font(.headline)
                .padding(.horizontal, 16)
                .padding(.top, 16)

            if actionItems.isEmpty {
                ContentUnavailableView(
                    "No action items",
                    systemImage: "checklist",
                    description: Text("Nothing was extracted from this meeting.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(actionItems, id: \.id) { task in
                    ActionItemRow(task: task)
                }
                .listStyle(.inset)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            reload()
        }
        .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { _ in
            reload()
        }
    }

    private func reload() {
        guard let meeting = try? composition.meetingRepository.find(id: meetingID) else {
            actionItems = []
            return
        }

        let ids = meeting.actionItemIDs
        guard !ids.isEmpty else {
            actionItems = []
            return
        }

        let descriptor = FetchDescriptor<TaskItem>(
            predicate: #Predicate { task in
                ids.contains(task.id) && task.deletedAt == nil
            }
        )

        guard let fetched = try? composition.meetingRepository.context.fetch(descriptor) else {
            actionItems = []
            return
        }

        let tasksByID = Dictionary(uniqueKeysWithValues: fetched.map { ($0.id, $0) })
        actionItems = ids.compactMap { tasksByID[$0] }
    }
}

private struct ActionItemRow: View {
    let task: TaskItem

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Label(statusLabel, systemImage: statusSystemImage)
                .font(.caption.weight(.medium))
                .foregroundStyle(task.status == .done ? .secondary : .tertiary)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(task.title)
                    .font(.body.weight(.medium))

                if !task.body.isEmpty {
                    Text(task.body)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }

                if let dueAt = task.dueAt {
                    Text(dueAt, style: .date)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var statusLabel: String {
        switch task.status {
        case .done:
            "Done"
        case .open:
            "Open"
        case .snoozed:
            "Snoozed"
        }
    }

    private var statusSystemImage: String {
        switch task.status {
        case .done:
            "checkmark.circle.fill"
        case .open:
            "circle"
        case .snoozed:
            "clock"
        }
    }
}
