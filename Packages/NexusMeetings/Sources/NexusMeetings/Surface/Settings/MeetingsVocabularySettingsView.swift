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
        VStack(alignment: .leading, spacing: DS.Space.m) {
            LiquidGlassCard("Custom vocabulary") {
                VStack(alignment: .leading, spacing: 0) {
                    if entries.isEmpty {
                        emptyRow
                    } else {
                        ForEach(entries) { entry in
                            entryRow(entry)
                            Divider()
                                .overlay(DS.ColorToken.strokeHairline)
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
            .font(DS.FontToken.caption)
            .foregroundStyle(DS.ColorToken.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .onAppear {
            entries = store.load()
        }
    }

    private var emptyRow: some View {
        Text("No custom terms yet.")
            .font(DS.FontToken.body)
            .foregroundStyle(DS.ColorToken.textMuted)
            .padding(.horizontal, DS.Space.l)
            .frame(minHeight: 44, alignment: .leading)
    }

    private func entryRow(_ entry: CustomVocabularyEntry) -> some View {
        HStack {
            Text(entry.term)
                .font(DS.FontToken.body)
                .foregroundStyle(DS.ColorToken.textPrimary)
            Spacer()
            HStack(spacing: DS.Space.m) {
                if !entry.replacement.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(DS.ColorToken.textMuted)
                    Text(entry.replacement)
                        .font(DS.FontToken.body)
                        .foregroundStyle(DS.ColorToken.textSecondary)
                }
                Button {
                    remove(entry)
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(DS.ColorToken.statusDanger)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove \(entry.term)")
            }
        }
        .frame(minHeight: 44)
    }

    private var addRow: some View {
        HStack(spacing: DS.Space.m) {
            TextField("Spoken term", text: $newTerm)
                .textFieldStyle(.roundedBorder)
                .font(DS.FontToken.body)
            Image(systemName: "arrow.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(DS.ColorToken.textMuted)
            TextField("Replacement", text: $newReplacement)
                .textFieldStyle(.roundedBorder)
                .font(DS.FontToken.body)
            Button {
                add()
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(
                        trimmedNewTerm.isEmpty ? DS.ColorToken.textMuted : DS.ColorToken.textSecondary
                    )
            }
            .buttonStyle(.plain)
            .disabled(trimmedNewTerm.isEmpty)
            .accessibilityLabel("Add term")
        }
        .padding(.horizontal, DS.Space.l)
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
