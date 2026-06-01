import NexusCore
import NexusUI
import SwiftUI

struct WatchAgendaRow: View {
    let task: TaskItem
    let now: Date
    var onMarkedDone: ((TaskItem) -> Void)?
    var onReopened: ((TaskItem) -> Void)?

    @Environment(\.watchTaskActions) private var actions

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // Ruling-4 §3 state-via-glyph: the achromatic cure for the
            // deleted hue-state `chipColor`. Mirrors the oracle row's leading
            // LabStatusGlyph placement and the MP-2 TaskRowView achromatic
            // status mapping. Leading element of the existing HStack.
            // Wrist legibility: the shared glyph renders at a 12pt frame tuned
            // for Mac/iOS density. Scale it up so the status read survives at
            // wrist distance while keeping the achromatic token semantics.
            NexusStatusGlyph(glyphStatus)
                .scaleEffect(1.5, anchor: .center)
                .frame(width: 18, height: 18)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(task.title)
                    .font(NexusType.body.weight(.semibold))
                    .foregroundStyle(NexusColor.Text.primary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.86)

                HStack(spacing: 6) {
                    if let due = task.dueAt {
                        let isOverdue = due < Calendar.current.startOfDay(for: now)
                        Label {
                            Text(due, format: timeFormat(for: due))
                                .lineLimit(1)
                        } icon: {
                            Image(systemName: isOverdue ? "exclamationmark.circle" : "clock")
                                .font(.system(size: 12, weight: isOverdue ? .semibold : .medium))
                        }
                        .font(NexusType.meta)
                        .foregroundStyle(isOverdue ? NexusColor.Text.primary : NexusColor.Text.tertiary)
                    }

                    if task.priority != .none {
                        Image(systemName: "flag.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(NexusColor.Text.tertiary)
                            .accessibilityLabel(priorityLabel)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 3)
        .frame(minHeight: 52)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            if task.statusRaw == TaskStatus.open.rawValue {
                Button {
                    Task {
                        try? await actions?.markDone(task)
                        onMarkedDone?(task)
                    }
                } label: {
                    Label("Done", systemImage: "checkmark")
                }
                // watchOS swipe-action chrome: neutral done indicator.
                .tint(NexusColor.Text.secondary)
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            if task.statusRaw == TaskStatus.done.rawValue {
                Button {
                    Task {
                        try? await actions?.reopen(task)
                        onReopened?(task)
                    }
                } label: {
                    Label("Reopen", systemImage: "arrow.uturn.backward")
                }
                // watchOS swipe-action chrome: neutral reopen indicator.
                .tint(NexusColor.Text.primary)
            }
        }
    }

    private func timeFormat(for due: Date) -> Date.FormatStyle {
        if Calendar.current.isDateInToday(due) {
            return Date.FormatStyle(date: .omitted, time: .shortened)
        }
        return Date.FormatStyle(date: .numeric, time: .omitted)
    }

    // Mirrors the MP-2 TaskRowView achromatic mapping. `taskNexusStatus(for:)`
    // is internal to the TasksFeature package (module boundary) so the Watch
    // row carries its own exhaustive switch — no `default`, so a new
    // TaskStatus case is a compile error. §11-clean: pure switch over the
    // already-loaded status enum, zero new query/transform/behavior.
    private var glyphStatus: NexusStatus {
        switch task.status {
        case .open: return .todo
        case .done: return .done
        case .snoozed: return .inReview
        }
    }

    private var priorityLabel: String {
        switch task.priority {
        case .high: return "High priority"
        case .medium: return "Medium priority"
        case .low: return "Low priority"
        case .none: return ""
        }
    }
}
