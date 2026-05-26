import NexusCore
import NexusUI
import OSLog
import SwiftData
import SwiftUI

/// Custom snooze date picker sheet. Surface trigger: deep-link
/// `nexus://task/{id}/snooze` from the SNOOZE_CUSTOM notification action,
/// or future contextual menus.
public struct CustomSnoozeSheet: View {
    private static let logger = Logger(
        subsystem: "com.kacperpietrzyk.Nexus",
        category: "CustomSnoozeSheet"
    )

    @Environment(\.taskRepository) private var repository
    @Environment(\.dismiss) private var dismiss

    @Bindable public var task: TaskItem
    public let onSnoozed: ((Date) -> Void)?

    @State private var pickedDate: Date

    public init(task: TaskItem, initialDate: Date = .now, onSnoozed: ((Date) -> Void)? = nil) {
        self.task = task
        self.onSnoozed = onSnoozed
        self._pickedDate = State(initialValue: initialDate)
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text(task.title.isEmpty ? "Drzemka" : task.title)
                    .nexusType(.h3)
                    .foregroundStyle(NexusColor.Text.primary)
                DatePicker(
                    "Drzemka do",
                    selection: $pickedDate,
                    in: Date.now...,
                    displayedComponents: [.date, .hourAndMinute]
                )
                .datePickerStyle(.graphical)
                .labelsHidden()
                Spacer()
            }
            .padding(20)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Anuluj") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Zapisz") { commit() }
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
    }

    @MainActor
    private func commit() {
        guard let repository else {
            dismiss()
            return
        }
        do {
            try repository.snooze(task, until: pickedDate)
            onSnoozed?(pickedDate)
        } catch {
            Self.logger.error(
                "snooze failed for taskID \(task.id, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
        }
        dismiss()
    }
}
