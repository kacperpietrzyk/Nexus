import SwiftUI

#if !os(watchOS)

import NexusAI

/// The reconciler + resolved set + device tier an app composes to drive
/// `AssistantStorageContainer`. A named value (not a tuple) so call sites and the
/// app composition roots stay within the lint's tuple-arity limit.
public struct ModelStorageInputs: Sendable {
    public let reconciler: ModelStoreReconciler
    public let resolvedSet: ResolvedModelSet
    public let tier: DeviceTier

    public init(reconciler: ModelStoreReconciler, resolvedSet: ResolvedModelSet, tier: DeviceTier) {
        self.reconciler = reconciler
        self.resolvedSet = resolvedSet
        self.tier = tier
    }
}

/// Stateful host for `AssistantStorageSection`: owns the `ModelStoreReconciler`,
/// runs a single disk scan, and from it derives both the per-model **readiness
/// checklist** (disk-truth health of the models the assistant requires here) and
/// the verified "Free up space" action. Replaces the old chat-only readiness label.
public struct AssistantStorageContainer: View {
    private let reconciler: ModelStoreReconciler
    private let resolvedSet: ResolvedModelSet
    private let tier: DeviceTier
    private let onReloadChat: () async -> Void
    private let onReloadEmbedder: () async -> Void

    @State private var rows: [AssistantStorageRow] = []
    @State private var headline: String = ""
    @State private var tone: AssistantReadinessTone = .none

    public init(
        reconciler: ModelStoreReconciler,
        resolvedSet: ResolvedModelSet,
        tier: DeviceTier,
        onReloadChat: @escaping () async -> Void,
        onReloadEmbedder: @escaping () async -> Void
    ) {
        self.reconciler = reconciler
        self.resolvedSet = resolvedSet
        self.tier = tier
        self.onReloadChat = onReloadChat
        self.onReloadEmbedder = onReloadEmbedder
    }

    public var body: some View {
        AssistantStorageSection(
            headline: headline,
            tone: tone,
            rows: rows,
            onFreeUp: freeUp
        )
        .task { await refresh() }
    }

    // MARK: - Scan → checklist + disk rows

    private func refresh() async {
        let reconciler = self.reconciler
        let scanned = await Task.detached(priority: .utility) { reconciler.scan() }.value

        let checklist = AssistantReadinessChecklist(
            tier: tier, resolvedSet: resolvedSet, store: ModelManifestLocalState.Store())
        let items = checklist.items(scanEntries: scanned)
        let summary = checklist.summary(for: items)

        var built: [AssistantStorageRow] = items.map { item in
            Self.row(from: item, scanEntries: scanned)
        }
        // Transcription is feature-gated (meetings only): not part of the assistant
        // health checklist, but if it is on disk we still surface it for reclaim.
        built.append(contentsOf: Self.transcriptionRows(from: scanned))

        rows = built
        headline = Self.headline(for: summary)
        tone = Self.tone(for: summary.overall)
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
            await refresh()
        }
    }

    // MARK: - Mapping

    private static func row(
        from item: ModelReadinessItem,
        scanEntries: [ModelStoreEntry]
    ) -> AssistantStorageRow {
        let kind: AssistantStorageRow.Kind = item.role == .chat ? .chat : .embedder
        let entryKind: ModelStoreEntry.Kind = item.role == .chat ? .chat : .embedder
        let size =
            scanEntries.first {
                $0.kind == entryKind
                    && ($0.classification == .canonical || $0.classification == .staleButActive)
                    && $0.sizeBytes > 0
            }?.sizeBytes ?? 0
        return AssistantStorageRow(
            id: item.id,
            title: item.role == .chat ? "Assistant model" : "Search model",
            sizeBytes: size,
            kind: kind,
            health: health(from: item.status)
        )
    }

    private static func transcriptionRows(
        from scanEntries: [ModelStoreEntry]
    ) -> [AssistantStorageRow] {
        scanEntries
            .filter {
                $0.kind == .transcription
                    && ($0.classification == .canonical || $0.classification == .staleButActive)
                    && $0.sizeBytes > 0
            }
            .map {
                AssistantStorageRow(
                    id: $0.id,
                    title: "Transcription model",
                    sizeBytes: $0.sizeBytes,
                    kind: .transcription,
                    health: .ready
                )
            }
    }

    private static func health(
        from status: ModelReadinessItem.Status
    ) -> AssistantStorageRow.Health {
        switch status {
        case .ready: return .ready
        case .updating: return .updating
        case .downloading(let p): return .downloading(p)
        case .missing: return .missing
        case .failed: return .failed
        }
    }

    private static func headline(for summary: AssistantReadinessSummary) -> String {
        switch summary.overall {
        case .ready:
            return "Assistant ready"
        case .downloading:
            return "Downloading models…"
        case .incomplete:
            return summary.readyCount == 0
                ? "Models not downloaded"
                : "\(summary.readyCount)/\(summary.requiredCount) models ready"
        case .failed:
            return "A model failed to download"
        case .noneRequired:
            return "No on-device assistant on this device"
        }
    }

    private static func tone(
        for overall: AssistantReadinessSummary.Overall
    ) -> AssistantReadinessTone {
        switch overall {
        case .ready: return .ready
        case .downloading: return .working
        case .incomplete: return .incomplete
        case .failed: return .failed
        case .noneRequired: return .none
        }
    }
}

#endif
