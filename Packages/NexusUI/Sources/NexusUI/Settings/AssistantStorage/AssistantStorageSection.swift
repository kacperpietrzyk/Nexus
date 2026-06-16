import SwiftUI

#if !os(watchOS)

// MARK: - Row model

/// A single required/installed model rendered inside `AssistantStorageSection`:
/// its health (is it ready to work?) plus its real disk usage and reclaim action.
public struct AssistantStorageRow: Identifiable, Sendable {
    public enum Kind: Sendable { case chat, embedder, transcription }

    /// Disk-truth health of the model. Mirrors `NexusAI.ModelReadinessItem.Status`
    /// but kept UI-local so this view stays free of the NexusAI import.
    public enum Health: Sendable, Equatable {
        case ready
        case updating
        case downloading(Double)  // 0...1
        case missing
        case failed
    }

    public let id: String
    public let title: String
    public let sizeBytes: Int64
    public let kind: Kind
    public let health: Health

    public init(id: String, title: String, sizeBytes: Int64, kind: Kind, health: Health) {
        self.id = id
        self.title = title
        self.sizeBytes = sizeBytes
        self.kind = kind
        self.health = health
    }
}

/// Overall tone of the assistant-readiness headline pill.
public enum AssistantReadinessTone: Sendable {
    case ready, working, incomplete, failed, none
}

// MARK: - Section view

/// Settings section answering "are the models the assistant needs downloaded and
/// ready to work?" — an overall readiness pill, a per-model health checklist, and
/// a verified "Free up space" on each model that is actually on disk.
/// Pure presentation — the stateful `AssistantStorageContainer` supplies rows + actions.
public struct AssistantStorageSection: View {
    private let headline: String
    private let tone: AssistantReadinessTone
    private let rows: [AssistantStorageRow]
    private let onFreeUp: (AssistantStorageRow) -> Void
    private let onDownload: (AssistantStorageRow) -> Void
    @State private var confirming: AssistantStorageRow.ID?

    public init(
        headline: String,
        tone: AssistantReadinessTone,
        rows: [AssistantStorageRow],
        onFreeUp: @escaping (AssistantStorageRow) -> Void,
        onDownload: @escaping (AssistantStorageRow) -> Void = { _ in }
    ) {
        self.headline = headline
        self.tone = tone
        self.rows = rows
        self.onFreeUp = onFreeUp
        self.onDownload = onDownload
    }

    public var body: some View {
        LiquidGlassCard("Assistant models") {
            VStack(alignment: .leading, spacing: 0) {
                headlineRow
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

    private var headlineRow: some View {
        HStack(spacing: DS.Space.s) {
            Circle()
                .fill(toneColor)
                .frame(width: 9, height: 9)
            Text(headline)
                .font(DS.FontToken.body)
                .foregroundStyle(DS.ColorToken.textPrimary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DS.Space.l)
        .padding(.vertical, DS.Space.m)
    }

    @ViewBuilder
    private func modelRow(_ row: AssistantStorageRow) -> some View {
        HStack(alignment: .center, spacing: DS.Space.m) {
            Image(systemName: icon(for: row.health))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(color(for: row.health))
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title)
                    .font(DS.FontToken.body)
                    .foregroundStyle(DS.ColorToken.textPrimary)
                Text(detail(for: row))
                    .font(DS.FontToken.caption)
                    .foregroundStyle(DS.ColorToken.textSecondary)
            }
            Spacer(minLength: DS.Space.l)
            if let label = downloadLabel(for: row) {
                Button(label) { onDownload(row) }
                    .font(DS.FontToken.button)
                    .foregroundStyle(DS.ColorToken.statusInfo)
                    .buttonStyle(LiquidPressButtonStyle())
            } else if canFreeUp(row) {
                Button("Free up space") { confirming = row.id }
                    .font(DS.FontToken.button)
                    .foregroundStyle(DS.ColorToken.textPrimary)
                    .buttonStyle(LiquidPressButtonStyle())
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
        }
        .padding(.horizontal, DS.Space.l)
        .padding(.vertical, DS.Space.m)
    }

    // MARK: - Presentation helpers

    /// Free-up is offered only for a model that is genuinely on disk and not the
    /// last working copy mid-update — never for a missing or downloading model.
    private func canFreeUp(_ row: AssistantStorageRow) -> Bool {
        row.health == .ready && row.sizeBytes > 0
    }

    /// The download affordance label for an actionable row, or `nil` when the row
    /// needs no action (ready, or already downloading). A failed model offers a
    /// retry; a missing one a download; a model still running on an older build
    /// (`updating`) offers to fetch the new canonical. Transcription has no
    /// download here (it is fetched on first meeting use).
    private func downloadLabel(for row: AssistantStorageRow) -> String? {
        guard row.kind != .transcription else { return nil }
        switch row.health {
        case .missing: return "Download"
        case .failed: return "Retry"
        case .updating: return "Update"
        case .ready, .downloading: return nil
        }
    }

    private func detail(for row: AssistantStorageRow) -> String {
        let status: String
        switch row.health {
        case .ready: status = "Ready"
        case .updating: status = "Updating…"
        case .downloading(let p): status = "Downloading \(Int((p * 100).rounded()))%"
        case .missing: return "Not downloaded"
        case .failed: return "Download failed"
        }
        guard row.sizeBytes > 0 else { return status }
        let size = ByteCountFormatter.string(fromByteCount: row.sizeBytes, countStyle: .file)
        return "\(status) · \(size)"
    }

    private func icon(for health: AssistantStorageRow.Health) -> String {
        switch health {
        case .ready: return "checkmark.circle.fill"
        case .updating: return "arrow.triangle.2.circlepath.circle.fill"
        case .downloading: return "arrow.down.circle.fill"
        case .missing: return "exclamationmark.circle.fill"
        case .failed: return "xmark.octagon.fill"
        }
    }

    private func color(for health: AssistantStorageRow.Health) -> Color {
        switch health {
        case .ready: return DS.ColorToken.statusSuccess
        case .updating, .downloading: return DS.ColorToken.statusInfo
        case .missing: return DS.ColorToken.statusWarning
        case .failed: return DS.ColorToken.statusDanger
        }
    }

    private var toneColor: Color {
        switch tone {
        case .ready: return DS.ColorToken.statusSuccess
        case .working: return DS.ColorToken.statusInfo
        case .incomplete: return DS.ColorToken.statusWarning
        case .failed: return DS.ColorToken.statusDanger
        case .none: return DS.ColorToken.statusNeutral
        }
    }
}

#endif
