import NexusCore
import NexusUI
import SwiftUI

// "Save as Template" / "New Task from Template" card (Tranche 2 Plan D).
// Split into its own file mirroring `TaskDetailInspector+Promote.swift` to
// keep the main file under the length budget.
extension TaskDetailInspector {
    var templateCard: some View {
        inspectorCard("Template") {
            if task.isTemplate {
                Text(
                    "This task is a template. It stays out of Today, Upcoming, Inbox, and stats, and can't be completed."
                )
                .font(DS.FontToken.body)
                .foregroundStyle(DS.ColorToken.textSecondary)
                NexusButton(variant: .outline, size: .sm, action: instantiateFromTemplate) {
                    HStack(spacing: 6) {
                        Image(systemName: "plus.square.on.square")
                            .accessibilityHidden(true)
                        Text("New Task from Template")
                    }
                }
            } else {
                NexusButton(variant: .outline, size: .sm, action: saveTaskAsTemplate) {
                    HStack(spacing: 6) {
                        Image(systemName: "doc.on.doc")
                            .accessibilityHidden(true)
                        Text("Save as Template")
                    }
                }
            }
        }
    }

    @MainActor
    func saveTaskAsTemplate() {
        guard let repository, !task.isTemplate else { return }
        _ = try? TemplateInstantiator(tasks: repository).saveAsTemplate(task)
    }

    @MainActor
    func instantiateFromTemplate() {
        guard let repository, task.isTemplate else { return }
        _ = try? TemplateInstantiator(tasks: repository).instantiate(task)
    }
}
