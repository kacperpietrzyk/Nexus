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
        LiquidGlassCard("Memory") {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Auto-save high-confidence memory")
                        .font(DS.FontToken.body)
                        .foregroundStyle(DS.ColorToken.textPrimary)
                    Spacer()
                    Toggle("", isOn: $autoSave)
                        .labelsHidden()
                }
                .frame(minHeight: 44)
                Divider()
                    .overlay(DS.ColorToken.strokeHairline)

                Picker("Scope", selection: $viewModel.scope) {
                    Text("Global").tag("global")
                    Text("Project").tag("project")
                    Text("Tag").tag("tag")
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .onChange(of: viewModel.scope) { _, _ in
                    viewModel.reload()
                }
                .padding(.vertical, DS.Space.s)
                Divider()
                    .overlay(DS.ColorToken.strokeHairline)

                if viewModel.entries.isEmpty {
                    NexusEmptyState(
                        systemImage: "brain",
                        title: "No memories in this scope yet."
                    )
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(viewModel.entries.enumerated()), id: \.element.id) { index, entry in
                            if index > 0 {
                                Divider()
                                    .overlay(DS.ColorToken.strokeHairline)
                            }
                            memoryRow(entry)
                                .padding(.vertical, DS.Space.s)
                        }
                    }
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
                    .font(DS.FontToken.body)
                    .fontWeight(.bold)
                    .foregroundStyle(DS.ColorToken.textPrimary)

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
                        .foregroundStyle(DS.ColorToken.textSecondary)
                }
                .buttonStyle(NexusPressableButtonStyle())
                .help("Delete memory")
            }

            Text(entry.content)
                .font(DS.FontToken.caption)
                .foregroundStyle(DS.ColorToken.textMuted)
        }
        .padding(.vertical, 2)
    }
}
