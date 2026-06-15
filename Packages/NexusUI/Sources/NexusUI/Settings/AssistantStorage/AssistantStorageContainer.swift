import NexusAI
import SwiftUI

#if !os(watchOS)

/// Stateful host for `AssistantStorageSection`: owns the `ModelStoreReconciler`,
/// computes live rows from a disk scan, and performs verified "Free up space"
/// (re-downloads on next AI use). Replaces the old `ManageModelsSection` storage UI.
public struct AssistantStorageContainer: View {
    private let reconciler: ModelStoreReconciler
    private let readinessProvider: () -> AssistantReadiness
    private let onReloadChat: () async -> Void
    private let onReloadEmbedder: () async -> Void
    @State private var rows: [AssistantStorageRow] = []

    public init(
        reconciler: ModelStoreReconciler,
        readinessProvider: @escaping () -> AssistantReadiness,
        onReloadChat: @escaping () async -> Void,
        onReloadEmbedder: @escaping () async -> Void
    ) {
        self.reconciler = reconciler
        self.readinessProvider = readinessProvider
        self.onReloadChat = onReloadChat
        self.onReloadEmbedder = onReloadEmbedder
    }

    public var body: some View {
        AssistantStorageSection(
            readinessLabel: Self.label(for: readinessProvider()),
            rows: rows,
            onFreeUp: freeUp
        )
        .task { await refreshRows() }
    }

    // MARK: - Scan

    private func refreshRows() async {
        let reconciler = self.reconciler
        let scanned = await Task.detached(priority: .utility) { reconciler.scan() }.value
        rows = scanned.compactMap(Self.row(from:))
    }

    // MARK: - Free up space

    private func freeUp(_ row: AssistantStorageRow) {
        let reconciler = self.reconciler
        let id = row.id
        let kind = row.kind
        Task {
            await Task.detached(priority: .utility) {
                switch kind {
                case .transcription:
                    _ = WhisperKitProvider.deleteDownloadedModel()
                case .chat, .embedder:
                    _ = reconciler.reclaim(canonicalID: id)
                }
            }.value
            await onReloadChat()
            await onReloadEmbedder()
            await refreshRows()
        }
    }

    // MARK: - Mapping

    private static func row(from entry: ModelStoreEntry) -> AssistantStorageRow? {
        guard entry.classification == .canonical || entry.classification == .staleButActive
        else { return nil }
        let kind: AssistantStorageRow.Kind
        let title: String
        switch entry.kind {
        case .chat:
            kind = .chat
            title = "Assistant model"
        case .embedder:
            kind = .embedder
            title = "Search model"
        case .transcription:
            kind = .transcription
            title = "Transcription model"
        case .unknown:
            return nil
        }
        return AssistantStorageRow(
            id: entry.id,
            title: title,
            sizeBytes: entry.sizeBytes,
            kind: kind
        )
    }

    private static func label(for readiness: AssistantReadiness) -> String {
        switch readiness {
        case .ready:
            return "Ready"
        case .notDownloaded:
            return "Not downloaded"
        case .downloading(let progress):
            return "Downloading \(Int(progress * 100))%"
        case .failed(let message):
            return "Failed: \(message)"
        }
    }
}

#endif
