import NexusCore
import NexusUI
import SwiftData
import SwiftUI

public struct SaveCurrentFilterSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    private let currentFilter: TaskFilter
    private let onSaved: (SavedFilter) -> Void

    @State private var name: String
    @State private var icon: String
    @State private var error: String?

    public init(
        currentFilter: TaskFilter,
        onSaved: @escaping (SavedFilter) -> Void = { _ in }
    ) {
        self.currentFilter = currentFilter
        self.onSaved = onSaved
        let descriptor = SaveCurrentFilterDescriptor.make(for: currentFilter)
        self._name = State(initialValue: descriptor?.defaultName ?? currentFilter.displayTitle)
        self._icon = State(initialValue: descriptor?.defaultIcon ?? "line.3.horizontal.decrease.circle")
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header

            VStack(alignment: .leading, spacing: 8) {
                Text("Name")
                    .nexusType(.eyebrow)
                    .foregroundStyle(NexusColor.Text.muted)

                TextField("Smart list name", text: $name)
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
                Text("Icon")
                    .nexusType(.eyebrow)
                    .foregroundStyle(NexusColor.Text.muted)

                HStack(spacing: 10) {
                    Image(systemName: cleanedIcon)
                        .font(.system(size: 14, weight: .semibold))
                        // MP-2 burned: decorative icon preview → tertiary ink
                        .foregroundStyle(NexusColor.Text.tertiary)
                        .frame(width: 28, height: 28)
                        // MP-2 burned: accent chip fill → achromatic neutral surface
                        .background(NexusColor.Background.controlHover, in: RoundedRectangle(cornerRadius: NexusRadius.r2))

                    TextField("SF Symbol", text: $icon)
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
            }

            // MP-6.2 §2 value-identical zero-pixel rename: Semantic.warning ≡ Text.secondary
            // (both Color(hex: 0xC7C8CE)). MP-2/3 Mac-sidebar leftover that escaped the
            // sidebar burn-down; the audit catch-up. else-branch Text.tertiary untouched.
            Text(statusMessage)
                .nexusType(.bodySmall)
                .foregroundStyle(descriptor == nil ? NexusColor.Text.secondary : NexusColor.Text.tertiary)

            if let error {
                Text(error)
                    .nexusType(.caption)
                    // MP-2 burned: error text renders via primary ink
                    .foregroundStyle(NexusColor.Text.primary)
            }

            HStack {
                Spacer()
                NexusButton(
                    variant: .ghost, size: .md, action: { dismiss() },
                    label: {
                        Text("Cancel")
                    })
                NexusButton(
                    variant: .primary, size: .md, action: save,
                    label: {
                        Text("Save")
                    }
                )
                .disabled(!canSave)
            }
        }
        .padding(24)
        .frame(minWidth: 380)
        .background(NexusColor.Background.panel)
    }

    private var descriptor: SaveCurrentFilterDescriptor? {
        SaveCurrentFilterDescriptor.make(for: currentFilter)
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var cleanedIcon: String {
        let trimmed = icon.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "line.3.horizontal.decrease.circle" : trimmed
    }

    private var statusMessage: String {
        descriptor?.summary ?? SaveCurrentFilterUnsupportedReason.message(for: currentFilter)
    }

    private var canSave: Bool {
        descriptor != nil && !trimmedName.isEmpty
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Save Smart List")
                .font(NexusType.h2)
                .foregroundStyle(NexusColor.Text.primary)

            Text("Capture the current sidebar filter for quick access.")
                .nexusType(.bodySmall)
                .foregroundStyle(NexusColor.Text.tertiary)
        }
    }

    @MainActor
    private func save() {
        guard let descriptor else { return }
        let cleanedName = trimmedName
        guard !cleanedName.isEmpty else { return }

        do {
            let repository = SavedFilterRepository(context: modelContext)
            let filter = try repository.create(
                name: cleanedName,
                definition: descriptor.definition,
                icon: cleanedIcon
            )
            onSaved(filter)
            dismiss()
        } catch {
            self.error = String(describing: error)
        }
    }
}

struct SaveCurrentFilterDescriptor: Equatable, Sendable {
    let definition: FilterDefinition
    let defaultName: String
    let defaultIcon: String
    let summary: String

    static func make(for filter: TaskFilter) -> SaveCurrentFilterDescriptor? {
        switch filter {
        case .byTag(let tag):
            return .init(
                definition: .byTag(tag),
                defaultName: "#\(tag)",
                defaultIcon: "tag",
                summary: "Matches open tasks tagged #\(tag)."
            )
        case .project(let id):
            return .init(
                definition: .byProject(id),
                defaultName: "Project",
                defaultIcon: "folder",
                summary: "Matches open tasks assigned to the selected project."
            )
        case .projectSection(_, let sectionID):
            return .init(
                definition: .bySection(sectionID),
                defaultName: "Section",
                defaultIcon: "rectangle.split.3x1",
                summary: "Matches open tasks assigned to the selected section."
            )
        case .all, .today, .upcoming, .inbox, .completed, .savedFilter:
            return nil
        }
    }
}

enum SaveCurrentFilterUnsupportedReason {
    static func message(for filter: TaskFilter) -> String {
        switch filter {
        case .today:
            return "Today cannot be saved yet because Smart Lists cannot encode its live overdue and due-today semantics exactly."
        case .upcoming:
            return "Upcoming cannot be saved yet because Smart Lists cannot encode the app's live upcoming range exactly."
        case .inbox:
            return "Inbox cannot be saved yet because it includes both no-date tasks and future snoozed tasks."
        case .savedFilter:
            return "Saved Smart Lists cannot be saved as another Smart List."
        case .all:
            return "All Tasks cannot be saved yet because Smart Lists currently represent narrower saved filters."
        case .completed:
            return "Done cannot be saved yet because Smart Lists currently match open tasks only."
        case .byTag, .project, .projectSection:
            return ""
        }
    }
}
