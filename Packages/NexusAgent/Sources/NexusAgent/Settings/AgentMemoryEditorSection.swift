import NexusUI
import SwiftUI

public struct AgentMemoryEditorSection: View {
    public static let defaultAutoSaveEnabled = true

    public let context: AgentSettingsContext
    @StateObject private var viewModel: AgentMemoryEditorViewModel
    @AppStorage(NexusPreferences.Keys.agentMemoryAutoSaveEnabled)
    private var autoSave = AgentMemoryEditorSection.defaultAutoSaveEnabled

    public init(context: AgentSettingsContext) {
        self.context = context
        _viewModel = StateObject(wrappedValue: AgentMemoryEditorViewModel(store: context.memoryStore))
    }

    public var body: some View {
        SwiftUI.Section("Memory") {
            Toggle("Auto-save high-confidence memory", isOn: $autoSave)

            Picker("Scope", selection: $viewModel.scope) {
                Text("Global").tag("global")
                Text("Project").tag("project")
                Text("Tag").tag("tag")
            }
            .pickerStyle(.segmented)
            .onChange(of: viewModel.scope) { _, _ in
                viewModel.reload()
            }

            if viewModel.entries.isEmpty {
                Text("No memories in this scope yet.")
                    .font(NexusType.caption)
                    .foregroundStyle(NexusColor.Text.muted)
            } else {
                ForEach(viewModel.entries, id: \.id) { entry in
                    memoryRow(entry)
                }
            }
        }
        .onAppear {
            viewModel.reload()
        }
    }

    private func memoryRow(_ entry: AgentMemoryEntry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(entry.key)
                    .font(NexusType.bodySmall)
                    .fontWeight(.bold)
                    .foregroundStyle(NexusColor.Text.primary)

                Spacer(minLength: 12)

                Button(role: .destructive) {
                    viewModel.delete(id: entry.id)
                } label: {
                    // §3 categorical: Semantic.negative → Text.secondary.
                    // This is a trailing destructive *action affordance*,
                    // not a status — the `trash` glyph + role:.destructive
                    // + .help carry intent. Ink steps below the row's
                    // most-salient element (the entry key, Text.primary)
                    // so it invites without faking primary salience (§2
                    // LabPalette.read).
                    Image(systemName: "trash")
                        .foregroundStyle(NexusColor.Text.secondary)
                }
                .buttonStyle(.borderless)
                .help("Delete memory")
            }

            Text(entry.content)
                .font(NexusType.caption)
                .foregroundStyle(NexusColor.Text.muted)
        }
        .padding(.vertical, 2)
    }
}
