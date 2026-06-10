import NexusCore
import NexusUI
import SwiftUI

// MARK: - Recurrence card (incl. T1 completion-anchor "Repeat from" control)

extension TaskDetailInspector {
    var recurrenceCard: some View {
        inspectorCard("Recurrence") {
            Picker("Repeat", selection: $recurrenceChoice) {
                ForEach(RecurrenceChoice.allCases) { choice in
                    Text(choice.label).tag(choice)
                }
            }
            .onChange(of: recurrenceChoice) { _, choice in
                if let rule = choice.rrule {
                    task.recurrenceRule = RRuleAnchorToken.applying(
                        completionAnchor: completionAnchored, to: rule)
                } else if choice == .custom {
                    customRRule = task.recurrenceRule ?? ""
                } else {
                    task.recurrenceRule = nil
                }
                save()
            }
            if recurrenceChoice != .none {
                anchorPicker
            }
            if recurrenceChoice == .custom {
                TextField("RRULE", text: $customRRule)
                    .textFieldStyle(.plain)
                    .padding(10)
                    .background(
                        NexusColor.Background.control,
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                    )
                    .onSubmit {
                        task.recurrenceRule = customRRule.isEmpty ? nil : customRRule
                        // The typed text is the source of truth for the anchor;
                        // resync the segmented control instead of rewriting it.
                        completionAnchored = RRuleAnchorToken.isCompletionAnchored(customRRule)
                        save()
                    }
            }
        }
    }

    /// "Repeat from" anchor mode (T1 completion-based recurrence): due date
    /// (RFC default) vs completion (Todoist "every!"). Mirrors the
    /// `priorityPicker` eyebrow + segmented-control idiom.
    private var anchorPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("REPEAT FROM")
                .font(NexusType.eyebrow)
                .foregroundStyle(NexusColor.Text.tertiary)
            Picker("Repeat from", selection: $completionAnchored) {
                Text("Due date").tag(false)
                Text("Completion").tag(true)
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .onChange(of: completionAnchored) { _, anchored in
                guard let rule = task.recurrenceRule, !rule.isEmpty else { return }
                task.recurrenceRule = RRuleAnchorToken.applying(completionAnchor: anchored, to: rule)
                customRRule = task.recurrenceRule ?? ""
                save()
            }
        }
    }
}

enum TaskDetailRecurrenceChoice: String, Identifiable, CaseIterable {
    case none, daily, weekly, monthly, custom
    var id: String { rawValue }
    var label: String {
        switch self {
        case .none: return "None"
        case .daily: return "Daily"
        case .weekly: return "Weekly"
        case .monthly: return "Monthly"
        case .custom: return "Custom RRULE"
        }
    }
    var rrule: String? {
        switch self {
        case .none: return nil
        case .daily: return "FREQ=DAILY"
        case .weekly: return "FREQ=WEEKLY"
        case .monthly: return "FREQ=MONTHLY"
        case .custom: return nil
        }
    }
    static func from(rrule: String?) -> Self {
        guard let rrule else { return .none }
        // The ANCHOR token orthogonally modifies any curated rule; strip it so
        // "FREQ=DAILY;ANCHOR=COMPLETION" still renders as "Daily" (the anchor
        // is surfaced by the separate "Repeat from" control).
        switch RRuleAnchorToken.strippingAnchor(rrule) {
        case "FREQ=DAILY": return .daily
        case "FREQ=WEEKLY": return .weekly
        case "FREQ=MONTHLY": return .monthly
        default: return .custom
        }
    }
}
