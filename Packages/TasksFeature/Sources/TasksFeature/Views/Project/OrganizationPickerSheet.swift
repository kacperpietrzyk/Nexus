import NexusCore
import NexusUI
import SwiftData
import SwiftUI

struct OrganizationPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let onSelected: (UUID) -> Void

    @State private var searchText = ""
    @State private var candidates: [Organization] = []
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Select client")
                    .nexusType(.h3)
                    .foregroundStyle(NexusColor.Text.primary)
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.plain)
                    .foregroundStyle(NexusColor.Text.tertiary)
            }

            TextField("Find or create organization", text: $searchText)
                .onChange(of: searchText) { _, _ in reload() }

            if let error {
                Text(error)
                    .font(.caption)
                    // MP-2 burned: error text renders via primary ink
                    .foregroundStyle(NexusColor.Text.primary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    if candidates.isEmpty && !showCreateButton {
                        Text("No organizations found.")
                            .font(.caption)
                            .foregroundStyle(NexusColor.Text.tertiary)
                    }

                    ForEach(candidates, id: \.id) { org in
                        Button {
                            onSelected(org.id)
                            dismiss()
                        } label: {
                            HStack {
                                Text(org.name)
                                    .foregroundStyle(NexusColor.Text.primary)
                                if let sector = org.sector {
                                    Text(sector)
                                        .font(.caption)
                                        .foregroundStyle(NexusColor.Text.tertiary)
                                }
                                Spacer()
                                Image(systemName: "arrow.turn.down.right")
                                    .foregroundStyle(NexusColor.Text.tertiary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }

                    if showCreateButton {
                        Button(action: createAndSelect) {
                            Label("Create \"\(trimmedSearch)\"", systemImage: "plus.circle")
                                .foregroundStyle(NexusColor.Text.tertiary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(20)
        .frame(minWidth: 360, minHeight: 280, alignment: .topLeading)
        .background(NexusColor.Background.base)
        .task { reload() }
    }

    private var trimmedSearch: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var showCreateButton: Bool {
        guard !trimmedSearch.isEmpty else { return false }
        return !candidates.contains {
            $0.name.localizedCaseInsensitiveCompare(trimmedSearch) == .orderedSame
        }
    }

    @MainActor
    private func reload() {
        do {
            let all = try OrganizationRepository(context: modelContext).allActive()
            if trimmedSearch.isEmpty {
                candidates = all
            } else {
                candidates = all.filter { $0.name.localizedCaseInsensitiveContains(trimmedSearch) }
            }
            error = nil
        } catch {
            candidates = []
            self.error = String(describing: error)
        }
    }

    @MainActor
    private func createAndSelect() {
        do {
            let org = try OrganizationRepository(context: modelContext).create(name: trimmedSearch)
            onSelected(org.id)
            dismiss()
        } catch {
            self.error = String(describing: error)
        }
    }
}
