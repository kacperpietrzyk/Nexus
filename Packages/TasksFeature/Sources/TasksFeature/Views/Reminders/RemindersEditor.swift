import NexusCore
import NexusUI
import SwiftUI

/// Pure list operations for the reminders editor, kept separate from the view
/// so they are unit-testable.
enum RemindersReducer {
    static func add(_ rule: ReminderRule, to rules: [ReminderRule]) -> [ReminderRule] {
        guard !rules.contains(rule) else { return rules }
        return rules + [rule]
    }

    static func remove(at index: Int, from rules: [ReminderRule]) -> [ReminderRule] {
        guard rules.indices.contains(index) else { return rules }
        var copy = rules
        copy.remove(at: index)
        return copy
    }
}

/// Inspector section content for configuring task reminders. Binds directly
/// to the task's `reminders` array; the caller persists on change. Renders
/// inside an `inspectorCard` host — it does not supply its own card chrome.
struct RemindersEditor: View {
    @Binding var reminders: [ReminderRule]
    @State private var absoluteDate = Date().addingTimeInterval(3600)

    private static let relativeChoices: [(label: String, offset: TimeInterval)] = [
        ("30 min before", -1800),
        ("1 hour before", -3600),
        ("1 day before", -86400),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !reminders.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(reminders.enumerated()), id: \.offset) { index, rule in
                        NexusChip(Self.describe(rule), tone: .neutral) {
                            reminders = RemindersReducer.remove(at: index, from: reminders)
                        }
                    }
                }
            }

            HStack(spacing: 6) {
                ForEach(Self.relativeChoices, id: \.offset) { choice in
                    NexusButton(
                        variant: .outline,
                        size: .sm,
                        action: {
                            reminders = RemindersReducer.add(
                                .relative(offset: choice.offset, anchor: .due),
                                to: reminders
                            )
                        },
                        label: { Text(choice.label) }
                    )
                }
            }

            HStack(spacing: 6) {
                NexusDateField(
                    date: $absoluteDate,
                    components: [.date, .hourAndMinute],
                    accessibilityLabel: "Reminder date and time"
                )
                NexusButton(
                    variant: .outline,
                    size: .sm,
                    action: {
                        reminders = RemindersReducer.add(.absolute(absoluteDate), to: reminders)
                    },
                    label: { Text("Add") }
                )
            }
        }
    }

    static func describe(_ rule: ReminderRule) -> String {
        switch rule {
        case .absolute(let date):
            return date.formatted(date: .abbreviated, time: .shortened)
        case .relative(let offset, let anchor):
            let minutes = Int(-offset / 60)
            let unit = anchor == .due ? "due" : "deadline"
            if minutes % 1440 == 0 { return "\(minutes / 1440)d before \(unit)" }
            if minutes % 60 == 0 { return "\(minutes / 60)h before \(unit)" }
            return "\(minutes)m before \(unit)"
        }
    }
}
