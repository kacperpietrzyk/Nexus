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

struct ReminderQuickChoice: Equatable, Identifiable {
    let label: String
    let rule: ReminderRule

    var id: String { label }

    static let relativeChoices: [ReminderQuickChoice] = [
        ReminderQuickChoice(label: "30m due", rule: .relative(offset: -1800, anchor: .due)),
        ReminderQuickChoice(label: "1h due", rule: .relative(offset: -3600, anchor: .due)),
        ReminderQuickChoice(label: "1d due", rule: .relative(offset: -86400, anchor: .due)),
        ReminderQuickChoice(label: "30m deadline", rule: .relative(offset: -1800, anchor: .deadline)),
        ReminderQuickChoice(label: "1h deadline", rule: .relative(offset: -3600, anchor: .deadline)),
        ReminderQuickChoice(label: "1d deadline", rule: .relative(offset: -86400, anchor: .deadline)),
    ]
}

/// Inspector section content for configuring task reminders. Binds directly
/// to the task's `reminders` array; the caller persists on change. Renders
/// inside an `inspectorCard` host — it does not supply its own card chrome.
struct RemindersEditor: View {
    @Binding var reminders: [ReminderRule]
    @State private var absoluteDate = Date().addingTimeInterval(3600)
    @State private var absoluteRepeat: ReminderRepeat?

    private let quickChoiceColumns = [
        GridItem(.adaptive(minimum: 96), spacing: 6)
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

            LazyVGrid(columns: quickChoiceColumns, alignment: .leading, spacing: 6) {
                ForEach(ReminderQuickChoice.relativeChoices) { choice in
                    NexusButton(
                        variant: .outline,
                        size: .sm,
                        action: {
                            reminders = RemindersReducer.add(choice.rule, to: reminders)
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
                NexusSelect(
                    selection: $absoluteRepeat,
                    options: [ReminderRepeat?.none, .some(.daily), .some(.weekly)],
                    label: { value in
                        switch value {
                        case .none: return "Once"
                        case .some(.daily): return "Daily"
                        case .some(.weekly): return "Weekly"
                        }
                    },
                    accessibilityLabel: "Reminder repeat frequency"
                )
                .fixedSize()
                NexusButton(
                    variant: .outline,
                    size: .sm,
                    action: {
                        reminders = RemindersReducer.add(
                            .absolute(at: absoluteDate, repeats: absoluteRepeat), to: reminders)
                    },
                    label: { Text("Add") }
                )
            }
        }
    }

    static func describe(_ rule: ReminderRule) -> String {
        switch rule {
        case .absolute(let date, let repeats):
            let base = date.formatted(date: .abbreviated, time: .shortened)
            guard let repeats else { return base }
            return "\(base) · \(repeats == .daily ? "daily" : "weekly")"
        case .relative(let offset, let anchor):
            let minutes = Int(-offset / 60)
            let unit = anchor == .due ? "due" : "deadline"
            if minutes % 1440 == 0 { return "\(minutes / 1440)d before \(unit)" }
            if minutes % 60 == 0 { return "\(minutes / 60)h before \(unit)" }
            return "\(minutes)m before \(unit)"
        }
    }
}
