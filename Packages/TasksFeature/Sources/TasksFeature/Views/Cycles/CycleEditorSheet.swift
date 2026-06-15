import NexusCore
import NexusUI
import SwiftData
import SwiftUI

/// Create/edit sheet for a `Cycle` (Tranche 2 Plan C). Mirrors
/// `ProjectEditorSheet`: local draft state, explicit Save through the
/// repository, inline error text. Status transitions are NOT edited here —
/// they live on the sidebar context menu (single status write path stays
/// `CycleRepository.setStatus`).
public struct CycleEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    private let cycle: Cycle?

    @State private var name: String
    @State private var startAt: Date
    @State private var endAt: Date
    @State private var error: String?

    public init(cycle: Cycle? = nil) {
        self.cycle = cycle
        self._name = State(initialValue: cycle?.name ?? "")
        // Default new cycles to a two-week box starting today.
        let defaultStart = Calendar.current.startOfDay(for: .now)
        self._startAt = State(initialValue: cycle?.startAt ?? defaultStart)
        self._endAt = State(initialValue: cycle?.endAt ?? defaultStart.addingTimeInterval(14 * 86_400))
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(cycle == nil ? "New Cycle" : "Edit Cycle")
                .font(NexusType.h2)
                .foregroundStyle(NexusColor.Text.primary)

            VStack(alignment: .leading, spacing: 8) {
                Text("Name")
                    .nexusType(.eyebrow)
                    .foregroundStyle(NexusColor.Text.muted)

                TextField("Cycle name", text: $name)
                    .textFieldStyle(.plain)
                    .nexusType(.body)
                    .foregroundStyle(NexusColor.Text.primary)
                    .padding(.horizontal, 12)
                    .frame(height: 36)
                    .background(NexusColor.Background.control, in: RoundedRectangle(cornerRadius: NexusRadius.r2))
                    .overlay {
                        RoundedRectangle(cornerRadius: NexusRadius.r2)
                            .strokeBorder(NexusColor.Line.regular, lineWidth: 1)
                    }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Dates")
                    .nexusType(.eyebrow)
                    .foregroundStyle(NexusColor.Text.muted)

                HStack(spacing: 8) {
                    Text("Start")
                        .nexusType(.bodySmall)
                        .foregroundStyle(NexusColor.Text.secondary)
                    Spacer(minLength: 8)
                    NexusDateField(
                        date: $startAt,
                        components: [.date],
                        accessibilityLabel: "Cycle start date"
                    )
                }

                HStack(spacing: 8) {
                    Text("End")
                        .nexusType(.bodySmall)
                        .foregroundStyle(NexusColor.Text.secondary)
                    Spacer(minLength: 8)
                    NexusDateField(
                        date: $endAt,
                        components: [.date],
                        minDate: startAt.addingTimeInterval(86_400),
                        accessibilityLabel: "Cycle end date"
                    )
                }
            }

            if let error {
                Text(error)
                    .nexusType(.caption)
                    .foregroundStyle(NexusColor.Text.primary)
            }

            HStack {
                Spacer()
                NexusButton(
                    variant: .ghost, size: .md, action: { dismiss() },
                    label: { Text("Cancel") }
                )
                NexusButton(
                    variant: .primary, size: .md, action: save,
                    label: { Text(cycle == nil ? "Create" : "Save") }
                )
            }
        }
        .padding(24)
        .frame(width: 440)
        .background(NexusColor.Background.panel)
    }

    @MainActor
    private func save() {
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            error = "Name is required."
            return
        }
        do {
            let repository = CycleRepository(context: modelContext)
            if let cycle {
                try repository.update(cycle, name: cleaned, startAt: startAt, endAt: endAt)
            } else {
                _ = try repository.create(name: cleaned, startAt: startAt, endAt: endAt)
            }
            dismiss()
        } catch CycleRepositoryError.invalidInterval {
            error = "End date must be after the start date."
        } catch {
            self.error = String(describing: error)
        }
    }
}
