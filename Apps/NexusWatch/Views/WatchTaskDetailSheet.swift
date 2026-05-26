import NexusCore
import NexusUI
import SwiftUI

struct WatchTaskDetailSheet: View {
    let task: TaskItem

    @Environment(\.dismiss) private var dismiss
    @Environment(\.watchTaskActions) private var actions

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(task.title)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(NexusColor.Text.primary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(4)

                Button {
                    Task {
                        if task.statusRaw == TaskStatus.done.rawValue {
                            try? await actions?.reopen(task)
                        } else {
                            try? await actions?.markDone(task)
                        }
                        dismiss()
                    }
                } label: {
                    Label(buttonTitle, systemImage: buttonIcon)
                        .font(.system(size: 16, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: 38)
                }
                .buttonStyle(.borderedProminent)
                .tint(buttonTint)

                if let due = task.dueAt {
                    Label {
                        Text(due, format: .dateTime.weekday(.abbreviated).hour().minute())
                            .font(.system(size: 13, weight: .medium))
                    } icon: {
                        Image(systemName: "calendar")
                    }
                    // §2 value-identical zero-pixel rename: Accent.solid and
                    // Text.primary are both 0xF2F2F4.
                    .foregroundStyle(NexusColor.Text.primary)
                }

                if task.priority != .none {
                    Label {
                        Text(label(for: task.priority))
                            .font(.system(size: 13, weight: .medium))
                    } icon: {
                        Image(systemName: priorityIcon(for: task.priority))
                    }
                    .foregroundStyle(NexusColor.Text.tertiary)
                }
            }
            .padding(.horizontal, 8)
        }
    }

    private var buttonTitle: String {
        task.statusRaw == TaskStatus.done.rawValue ? "Cofnij" : "Wykonane"
    }

    private var buttonIcon: String {
        task.statusRaw == TaskStatus.done.rawValue
            ? "arrow.uturn.backward.circle.fill"
            : "checkmark.circle.fill"
    }

    private var buttonTint: Color {
        task.statusRaw == TaskStatus.done.rawValue
            // §2 value-identical zero-pixel rename: Accent.solid and
            // Text.primary are both 0xF2F2F4.
            ? NexusColor.Text.primary
            // §2 value-identical zero-pixel rename: Semantic.positive and
            // Text.secondary are both 0xC7C8CE.
            : NexusColor.Text.secondary
    }

    private func priorityIcon(for priority: TaskPriority) -> String {
        switch priority {
        case .high: "exclamationmark.2"
        case .medium: "exclamationmark"
        case .low: "minus"
        case .none: "questionmark"
        }
    }

    private func label(for priority: TaskPriority) -> String {
        switch priority {
        case .high: "Wysoki"
        case .medium: "Średni"
        case .low: "Niski"
        case .none: ""
        }
    }
}
