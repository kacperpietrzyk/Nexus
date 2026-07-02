// Mac-only surface: the readiness panel and its commands. Permission requests and
// model downloads run IN-PROCESS in the main app (which has `audio-input` +
// `network.client` entitlements and needs no sandboxed helper). Only the
// helper-only Accessibility/system-audio concerns still cross to the helper.
#if os(macOS)

import AVFoundation
import AppKit
import Foundation

@MainActor
@Observable
public final class MeetingsReadinessViewModel {
    public private(set) var sections: [ReadinessSection] = []

    private let reader: any MeetingsReadinessReading
    private let writer: (any MeetingsReadinessWriting)?
    private let computer: MeetingsReadinessComputer?
    private let prefetcher: any MeetingsModelPrefetching
    private let requestMicrophoneAccess: @Sendable (@escaping @Sendable (Bool) -> Void) -> Void
    private let openAccessibilitySettings: @MainActor () -> Void
    private let mapper: ReadinessRowMapper
    private let now: () -> Date
    private let post: (Notification.Name) -> Void

    /// In-flight per-model download fractions, merged over the persisted snapshot
    /// at render time so the rows show live `.downloading` / progress without
    /// waiting for the directory probe to observe the finished files.
    private var inFlightDownloads: [MeetingsModelID: Double] = [:]

    /// Delay before a transient-looking loud regression is surfaced. A re-probe
    /// (helper toggle, permission round-trip) briefly flips calm rows into taller
    /// warning/error cards; holding the calm state for this window absorbs the
    /// flicker, then the current truth is rendered regardless.
    private let debounceInterval: Duration

    /// Pending re-probe that surfaces the settled state after `debounceInterval`.
    /// Ignored by observation: it is bookkeeping, not rendered state.
    @ObservationIgnored private var debounceTask: Task<Void, Never>?

    public init(
        reader: any MeetingsReadinessReading = UserDefaultsMeetingsReadinessStore.shared,
        writer: (any MeetingsReadinessWriting)? = UserDefaultsMeetingsReadinessStore.shared,
        computer: MeetingsReadinessComputer? = MeetingsReadinessFactory.makeComputer(),
        prefetcher: any MeetingsModelPrefetching = LiveMeetingsModelPrefetcher(),
        requestMicrophoneAccess: @escaping @Sendable (@escaping @Sendable (Bool) -> Void) -> Void = { completion in
            AVCaptureDevice.requestAccess(for: .audio) { granted in completion(granted) }
        },
        openAccessibilitySettings: @escaping @MainActor () -> Void = {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        },
        mapper: ReadinessRowMapper = ReadinessRowMapper(),
        now: @escaping () -> Date = { Date() },
        post: @escaping (Notification.Name) -> Void = { name in
            DistributedNotificationCenter.default().postNotificationName(
                name, object: nil, userInfo: nil, deliverImmediately: true
            )
        },
        debounceInterval: Duration = .milliseconds(400)
    ) {
        self.reader = reader
        self.writer = writer
        self.computer = computer
        self.prefetcher = prefetcher
        self.requestMicrophoneAccess = requestMicrophoneAccess
        self.openAccessibilitySettings = openAccessibilitySettings
        self.mapper = mapper
        self.now = now
        self.post = post
        self.debounceInterval = debounceInterval
    }

    /// Recomputes readiness IN-PROCESS from the live probes, persists the fresh
    /// snapshot, and re-renders — so the panel is never blank/stale regardless of
    /// whether the helper agent is running. Falls back to the last persisted
    /// snapshot if no in-process computer was injected (e.g. in tests).
    public func refresh() {
        apply(probe(), debounced: true)
    }

    /// Recomputes a snapshot from the live probes (persisting it) or falls back
    /// to the last persisted snapshot when no in-process computer was injected.
    private func probe() -> MeetingsReadinessSnapshot? {
        guard let computer else { return reader.read() }
        let snapshot = computer.snapshot()
        writer?.write(snapshot)
        return snapshot
    }

    /// Renders a freshly-probed snapshot. When `debounced` and the snapshot turns
    /// a previously-calm row loud, the loud state is treated as a transient
    /// re-probe glitch and held for `debounceInterval` before the current truth
    /// is shown. A row that was ALREADY loud (settled needs-setup) and the very
    /// first render are surfaced immediately — real setup prompts are never
    /// hidden, only a brand-new loud transition is briefly delayed.
    private func apply(_ snapshot: MeetingsReadinessSnapshot?, debounced: Bool) {
        let newSections = mapper.sections(from: merge(inFlightDownloads, into: snapshot), now: now())
        if debounced, Self.introducesLoudRegression(from: sections, to: newSections) {
            scheduleDebouncedReprobe()
        } else {
            debounceTask?.cancel()
            debounceTask = nil
            sections = newSections
        }
    }

    private func scheduleDebouncedReprobe() {
        debounceTask?.cancel()
        debounceTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: self.debounceInterval)
            guard !Task.isCancelled else { return }
            self.debounceTask = nil
            // Show whatever is true now: a cleared transient renders calm; a
            // state that stayed loud renders its (real) needs-setup prompt.
            self.apply(self.probe(), debounced: false)
        }
    }

    private func render(from snapshot: MeetingsReadinessSnapshot?) {
        sections = mapper.sections(from: merge(inFlightDownloads, into: snapshot), now: now())
    }

    /// A row is "loud" when its state is `.warning`/`.error` — the taller
    /// warning/error card (with an action button) the tab reflows around.
    static func isLoud(_ state: ReadinessRowState) -> Bool {
        state == .warning || state == .error
    }

    /// True when the new sections turn a previously-calm row loud — the visible
    /// "flip". Rows already loud (settled needs-setup) and rows with no prior
    /// reading (first render) are NOT regressions, so genuine setup prompts
    /// surface immediately.
    static func introducesLoudRegression(
        from old: [ReadinessSection],
        to new: [ReadinessSection]
    ) -> Bool {
        var previous: [String: ReadinessRowState] = [:]
        for section in old {
            for row in section.rows { previous[row.id] = row.state }
        }
        for section in new {
            for row in section.rows where isLoud(row.state) {
                if let prior = previous[row.id], !isLoud(prior) { return true }
            }
        }
        return false
    }

    /// Overlays any in-flight download progress onto the snapshot's model rows so
    /// the UI reflects an active download before the directory probe sees files.
    private func merge(
        _ downloads: [MeetingsModelID: Double],
        into snapshot: MeetingsReadinessSnapshot?
    ) -> MeetingsReadinessSnapshot? {
        guard !downloads.isEmpty, let snapshot else { return snapshot }
        let models = MeetingsModelID.allCases.map { id -> ModelReadiness in
            let existing = snapshot.models.first { $0.id == id }
            if let fraction = downloads[id] {
                return ModelReadiness(id: id, sizeBytes: existing?.sizeBytes, state: .downloading(fraction: fraction))
            }
            return existing ?? ModelReadiness(id: id, sizeBytes: nil, state: .absent)
        }
        return MeetingsReadinessSnapshot(
            permissions: snapshot.permissions,
            models: models,
            environment: snapshot.environment,
            lastUpdated: snapshot.lastUpdated
        )
    }

    /// Asks the helper to recompute and write a fresh snapshot. Retained as a
    /// best-effort nudge so a running helper's auto-record/environment view stays
    /// in sync; the in-process `refresh()` is what actually populates the panel.
    public func requestHelperRefresh() {
        post(MeetingsReadinessNotification.refreshReadiness)
    }

    public func perform(_ action: ReadinessRowAction) {
        switch action {
        case .requestMicrophone:
            requestMicrophone()
        case .openAccessibilitySettings:
            // Helper-only concern (the helper owns Accessibility-gated window
            // detection). We can still open the pane directly (no helper needed),
            // and post to the helper as a fallback.
            // The running helper (AX owner) consumes `requestPermissions` and shows the prompt.
            openAccessibilitySettings()
            post(MeetingsReadinessNotification.requestPermissions)
        case .downloadModel(let id):
            download([id])
        case .downloadAllModels:
            download(MeetingsModelID.allCases)
        case .startHelper, .enableAutoRecord:
            post(MeetingsReadinessNotification.refreshReadiness)
        case .info:
            break
        }
    }

    private func requestMicrophone() {
        requestMicrophoneAccess { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    private func download(_ ids: [MeetingsModelID]) {
        for id in ids where inFlightDownloads[id] == nil {
            inFlightDownloads[id] = 0
        }
        render(from: computer?.snapshot() ?? reader.read())

        let prefetcher = prefetcher
        Task { @MainActor in
            for id in ids {
                do {
                    try await prefetcher.prefetch(id) { [weak self] fraction in
                        Task { @MainActor in self?.updateProgress(id, fraction: fraction) }
                    }
                } catch {
                    // Leave the row to the directory probe, which will keep
                    // reporting the model as absent/failed; clear in-flight state.
                }
                inFlightDownloads[id] = nil
            }
            refresh()
        }
    }

    private func updateProgress(_ id: MeetingsModelID, fraction: Double) {
        guard inFlightDownloads[id] != nil else { return }
        inFlightDownloads[id] = fraction
        render(from: computer?.snapshot() ?? reader.read())
    }
}

#endif
