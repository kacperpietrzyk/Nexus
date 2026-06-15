import Foundation

/// Readiness of a single *required* on-device model, derived from disk truth
/// cross-checked with local state.
public struct ModelReadinessItem: Sendable, Equatable, Identifiable {
    public enum Role: String, Sendable, Equatable { case chat, embedder }

    public enum Status: Sendable, Equatable {
        /// Canonical model present on disk and local state agrees — ready to work.
        case ready
        /// An older model still works while the canonical update has not landed yet.
        case updating
        /// Download in progress (0...1).
        case downloading(Double)
        /// Required here but not present on disk.
        case missing
        /// Last download attempt failed (message).
        case failed(String)
    }

    public let id: String  // manifest ID
    public let role: Role
    public let status: Status

    public init(id: String, role: Role, status: Status) {
        self.id = id
        self.role = role
        self.status = status
    }
}

/// Aggregate health of the assistant's required models.
public struct AssistantReadinessSummary: Sendable, Equatable {
    public enum Overall: Sendable, Equatable {
        case ready  // every required model is ready (or harmlessly updating)
        case downloading  // at least one model is downloading, none failed
        case incomplete  // at least one required model is missing, none failed/downloading
        case failed  // at least one model failed to download
        case noneRequired  // no on-device model is expected on this hardware
    }

    public let overall: Overall
    public let readyCount: Int
    public let requiredCount: Int

    public init(overall: Overall, readyCount: Int, requiredCount: Int) {
        self.overall = overall
        self.readyCount = readyCount
        self.requiredCount = requiredCount
    }
}

/// Disk-truth checklist of the assistant's *required* models for this device.
///
/// Two deliberate rules, both learned the hard way:
/// - **What is required comes from `DeviceTier`, not `ResolvedModelSet`.** A sub-8 GB
///   iPhone has no chat model — that is "not required here", a distinct state from
///   "required but missing", so it must not read as a health failure.
/// - **`ready` is asserted from the disk, never the UserDefaults flag alone.** The
///   canonical directory must actually be present on disk (size > 0) *and* local
///   state must agree. A flag that says "downloaded" while the bytes are gone reads
///   as `missing`, not a false green.
public struct AssistantReadinessChecklist: Sendable {
    private let tier: DeviceTier
    private let resolvedSet: ResolvedModelSet
    private let store: ModelManifestLocalState.Store

    public init(
        tier: DeviceTier,
        resolvedSet: ResolvedModelSet,
        store: ModelManifestLocalState.Store
    ) {
        self.tier = tier
        self.resolvedSet = resolvedSet
        self.store = store
    }

    /// Builds one item per *required* role, classified against the disk scan.
    public func items(scanEntries: [ModelStoreEntry]) -> [ModelReadinessItem] {
        var result: [ModelReadinessItem] = []
        if tier.recommendedChat != nil {
            result.append(
                item(
                    id: resolvedSet.chatManifestID, role: .chat, kind: .chat,
                    scanEntries: scanEntries))
        }
        if tier.recommendedEmbedder != nil {
            result.append(
                item(
                    id: resolvedSet.embedderManifestID, role: .embedder, kind: .embedder,
                    scanEntries: scanEntries))
        }
        return result
    }

    /// Folds the per-model items into an overall health summary.
    public func summary(for items: [ModelReadinessItem]) -> AssistantReadinessSummary {
        guard !items.isEmpty else {
            return AssistantReadinessSummary(overall: .noneRequired, readyCount: 0, requiredCount: 0)
        }
        let readyCount = items.filter { $0.status == .ready || $0.status == .updating }.count
        let overall: AssistantReadinessSummary.Overall
        if items.contains(where: { if case .failed = $0.status { return true } else { return false } }) {
            overall = .failed
        } else if readyCount == items.count {
            overall = .ready
        } else if items.contains(where: {
            if case .downloading = $0.status { return true } else { return false }
        }) {
            overall = .downloading
        } else {
            overall = .incomplete
        }
        return AssistantReadinessSummary(
            overall: overall, readyCount: readyCount, requiredCount: items.count)
    }

    // MARK: - Per-model classification

    private func item(
        id: String,
        role: ModelReadinessItem.Role,
        kind: ModelStoreEntry.Kind,
        scanEntries: [ModelStoreEntry]
    ) -> ModelReadinessItem {
        let state = store.load(manifestID: id)
        let canonicalOnDisk = scanEntries.contains {
            $0.id == id && $0.classification == .canonical && $0.sizeBytes > 0
        }
        let inFlight = scanEntries.contains { $0.id == id && $0.classification == .inFlight }
        let staleActive = scanEntries.contains {
            $0.kind == kind && $0.classification == .staleButActive && $0.sizeBytes > 0
        }

        let status: ModelReadinessItem.Status
        if state.status == .error {
            status = .failed(state.downloadError ?? "download failed")
        } else if canonicalOnDisk && state.status == .downloaded {
            status = .ready
        } else if state.status == .downloading || inFlight {
            let pct = min(max(state.downloadProgressPercent / 100.0, 0), 1)
            status = .downloading(pct)
        } else if staleActive {
            status = .updating
        } else {
            status = .missing
        }
        return ModelReadinessItem(id: id, role: role, status: status)
    }
}
