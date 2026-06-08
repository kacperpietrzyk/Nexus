import NexusCore
import NexusUI
import SwiftUI

/// Editor for the custom-vocabulary list (spec §8): user-supplied terms the
/// transcriber tends to mishear, each paired with the canonical spelling to
/// substitute in. Persisted through ``UserDefaultsCustomVocabularyStore`` (settings
/// store, not schema — no model churn). The list cannot bind through `@AppStorage`
/// (it is `[CustomVocabularyEntry]`, not a scalar), so it lives in `@State`: loaded
/// on appear and written back to the store on every mutation. The store is
/// app-group-backed, so the recording helper picks up edits.
public struct MeetingsVocabularySettingsView: View {
    private let store: CustomVocabularyStoring
    @State private var entries: [CustomVocabularyEntry] = []
    @State private var newTerm = ""
    @State private var newReplacement = ""

    public init(store: CustomVocabularyStoring = UserDefaultsCustomVocabularyStore.shared) {
        self.store = store
    }

    private var trimmedNewTerm: String {
        newTerm.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: NexusSpacing.s3) {
            nexusSettingsCardSectionHeader("Custom vocabulary")
            NexusSettingsCard {
                VStack(alignment: .leading, spacing: 0) {
                    if entries.isEmpty {
                        emptyRow
                    } else {
                        ForEach(entries) { entry in
                            entryRow(entry)
                            NexusSettingsDivider()
                        }
                    }
                    addRow
                }
            }

            Text(
                "Add names or jargon the transcriber gets wrong, plus the spelling "
                    + "you want. Each term biases transcription and is substituted in "
                    + "the final transcript (e.g. \u{201C}threat forge\u{201D} \u{2192} "
                    + "\u{201C}ThreatForge\u{201D})."
            )
            .font(NexusType.meta)
            .foregroundStyle(NexusColor.Text.muted)
            .fixedSize(horizontal: false, vertical: true)
        }
        .onAppear {
            entries = store.load()
        }
    }

    private var emptyRow: some View {
        Text("No custom terms yet.")
            .font(NexusType.bodySmall)
            .foregroundStyle(NexusColor.Text.muted)
            .padding(.horizontal, NexusSpacing.s4)
            .frame(minHeight: 44, alignment: .leading)
    }

    private func entryRow(_ entry: CustomVocabularyEntry) -> some View {
        NexusSettingsRow(entry.term) {
            HStack(spacing: NexusSpacing.s3) {
                if !entry.replacement.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(NexusColor.Text.disabled)
                    Text(entry.replacement)
                        .font(NexusType.bodySmall)
                        .foregroundStyle(NexusColor.Text.secondary)
                }
                Button {
                    remove(entry)
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(NexusColor.Status.danger)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove \(entry.term)")
            }
        }
    }

    private var addRow: some View {
        HStack(spacing: NexusSpacing.s3) {
            TextField("Spoken term", text: $newTerm)
                .textFieldStyle(.roundedBorder)
                .font(NexusType.bodySmall)
            Image(systemName: "arrow.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(NexusColor.Text.disabled)
            TextField("Replacement", text: $newReplacement)
                .textFieldStyle(.roundedBorder)
                .font(NexusType.bodySmall)
            Button {
                add()
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(
                        trimmedNewTerm.isEmpty ? NexusColor.Text.disabled : NexusColor.Text.secondary
                    )
            }
            .buttonStyle(.plain)
            .disabled(trimmedNewTerm.isEmpty)
            .accessibilityLabel("Add term")
        }
        .padding(.horizontal, NexusSpacing.s4)
        .frame(minHeight: 44)
    }

    private func add() {
        let term = trimmedNewTerm
        guard !term.isEmpty else { return }
        let replacement = newReplacement.trimmingCharacters(in: .whitespacesAndNewlines)
        entries.append(CustomVocabularyEntry(term: term, replacement: replacement))
        newTerm = ""
        newReplacement = ""
        store.save(entries)
    }

    private func remove(_ entry: CustomVocabularyEntry) {
        entries.removeAll { $0.id == entry.id }
        store.save(entries)
    }
}
