import SwiftUI

#if !os(watchOS)

// MARK: - Row model

/// A single model entry rendered inside `AssistantStorageSection`.
public struct AssistantStorageRow: Identifiable, Sendable {
    public enum Kind: Sendable { case chat, embedder, transcription }
    public let id: String
    public let title: String
    public let sizeBytes: Int64
    public let kind: Kind

    public init(id: String, title: String, sizeBytes: Int64, kind: Kind) {
        self.id = id
        self.title = title
        self.sizeBytes = sizeBytes
        self.kind = kind
    }
}

// MARK: - Section view

/// Slim Settings section: assistant readiness + per-model real disk usage + a
/// verified "Free up space" per model (chat / embedder / transcription).
/// Pure presentation — the stateful `AssistantStorageContainer` supplies rows + actions.
public struct AssistantStorageSection: View {
    private let readinessLabel: String
    private let rows: [AssistantStorageRow]
    private let onFreeUp: (AssistantStorageRow) -> Void
    @State private var confirming: AssistantStorageRow.ID?

    public init(
        readinessLabel: String,
        rows: [AssistantStorageRow],
        onFreeUp: @escaping (AssistantStorageRow) -> Void
    ) {
        self.readinessLabel = readinessLabel
        self.rows = rows
        self.onFreeUp = onFreeUp
    }

    public var body: some View {
        LiquidGlassCard("Storage") {
            VStack(alignment: .leading, spacing: 0) {
                statusRow
                if !rows.isEmpty {
                    Divider()
                        .overlay(DS.ColorToken.strokeHairline)
                }
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    if index > 0 {
                        Divider()
                            .overlay(DS.ColorToken.strokeHairline)
                    }
                    modelRow(row)
                }
            }
        }
    }

    private var statusRow: some View {
        HStack {
            Text("Status")
                .font(DS.FontToken.body)
                .foregroundStyle(DS.ColorToken.textPrimary)
            Spacer(minLength: DS.Space.l)
            Text(readinessLabel)
                .font(DS.FontToken.caption)
                .foregroundStyle(DS.ColorToken.textSecondary)
        }
        .padding(.horizontal, DS.Space.l)
        .padding(.vertical, DS.Space.m)
    }

    @ViewBuilder
    private func modelRow(_ row: AssistantStorageRow) -> some View {
        HStack(alignment: .center, spacing: DS.Space.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title)
                    .font(DS.FontToken.body)
                    .foregroundStyle(DS.ColorToken.textPrimary)
                Text(ByteCountFormatter.string(fromByteCount: row.sizeBytes, countStyle: .file))
                    .font(DS.FontToken.caption)
                    .foregroundStyle(DS.ColorToken.textSecondary)
            }
            Spacer(minLength: DS.Space.l)
            Button("Free up space") { confirming = row.id }
                .font(DS.FontToken.button)
                .foregroundStyle(
                    row.sizeBytes == 0 ? DS.ColorToken.textMuted : DS.ColorToken.textPrimary
                )
                .buttonStyle(LiquidPressButtonStyle())
                .disabled(row.sizeBytes == 0)
                .confirmationDialog(
                    "Free up space?",
                    isPresented: Binding(
                        get: { confirming == row.id },
                        set: { if !$0 { confirming = nil } }
                    ),
                    titleVisibility: .visible
                ) {
                    Button("Delete model", role: .destructive) { onFreeUp(row) }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("This model re-downloads the next time you use AI.")
                }
        }
        .padding(.horizontal, DS.Space.l)
        .padding(.vertical, DS.Space.m)
    }
}

#endif
