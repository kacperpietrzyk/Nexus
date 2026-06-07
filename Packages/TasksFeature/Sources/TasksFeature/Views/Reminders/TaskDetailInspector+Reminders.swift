import NexusCore
import SwiftUI

/// Reminders card + binding, split out of `TaskDetailInspector.swift` to keep
/// that file under the 600-line budget.
extension TaskDetailInspector {

    var remindersCard: some View {
        inspectorCard("Reminders") {
            RemindersEditor(reminders: remindersBinding)
        }
    }

    var remindersBinding: Binding<[ReminderRule]> {
        Binding(
            get: { task.reminders },
            set: {
                task.reminders = $0
                saveDeadlineChange()
            }
        )
    }
}
