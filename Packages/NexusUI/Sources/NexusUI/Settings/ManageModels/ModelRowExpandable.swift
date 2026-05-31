import SwiftUI

#if !os(watchOS)

import NexusAI
import NexusCore

/// A `DisclosureGroup` row for one catalog model.
///
/// Collapsed label: display name (bold) + CHAT/EMBED assignment chips + size.
/// Expanded body: for chat models only — Temperature / Max-tokens / Idle-timeout
/// sliders plus a system-prompt override `NavigationLink`; then a relative
/// "Last used" timestamp; then conditional actions (Re-download + Delete when
/// the model is on disk, otherwise a prominent Download).
///
/// `manifest` is a SwiftData `@Model`, so it is held via `@Bindable` (the same
/// pattern as `TaskDetailInspector`/`DownloadModelStep`) — the slider/editor
/// `Binding(get:set:)` closures write the user-preference overrides straight
/// back through the model and SwiftUI observes the mutation. `localState` is an
/// immutable value snapshot; its mutations flow through the action callbacks to
/// the parent's persistence store (Task 27), never from this row.
public struct ModelRowExpandable: View {
    @Bindable public var manifest: ModelManifest
    public let localState: ModelManifestLocalState

    /// The live, `@Observable` progress for an in-flight download of THIS model,
    /// or `nil` when none is running. Observing it here is what gives the row a
    /// moving percent — the `UserDefaults`-backed `localState` snapshot only
    /// records the final status, never intermediate bytes.
    public let progress: ModelDownloadProgress?

    @State private var expanded = false

    // Invoked by the parent's assignment affordance (Task 27), not by this row's own controls.
    private let onAssignChat: () -> Void
    private let onAssignEmbedder: () -> Void
    private let onDownload: () -> Void
    private let onDelete: () -> Void
    private let onReDownload: () -> Void
    /// Fired when `progress` reaches a terminal state (completed / failed /
    /// cancelled) so the parent can reload its `localState` snapshots — without
    /// this the row would stay on the spinner until the screen reappears.
    private let onDownloadFinished: () -> Void

    public init(
        manifest: ModelManifest,
        localState: ModelManifestLocalState,
        progress: ModelDownloadProgress? = nil,
        onAssignChat: @escaping () -> Void = {},
        onAssignEmbedder: @escaping () -> Void = {},
        onDownload: @escaping () -> Void = {},
        onDelete: @escaping () -> Void = {},
        onReDownload: @escaping () -> Void = {},
        onDownloadFinished: @escaping () -> Void = {}
    ) {
        self.manifest = manifest
        self.localState = localState
        self.progress = progress
        self.onAssignChat = onAssignChat
        self.onAssignEmbedder = onAssignEmbedder
        self.onDownload = onDownload
        self.onDelete = onDelete
        self.onReDownload = onReDownload
        self.onDownloadFinished = onDownloadFinished
    }

    // MARK: - Tested contract

    /// Conditional action buttons, in render order.
    public enum Action: String, Sendable, Equatable {
        case assignChat
        case assignEmbedder
        case download
        case reDownload
        case delete
    }

    /// Pure, view-free description of everything the row renders that depends on
    /// `manifest`/`localState`. Mirrors the `DownloadModelStep.downloadPlan`
    /// precedent so the decision logic can be unit-tested without a SwiftUI
    /// host. `body` resolves this once and consumes it.
    public struct RowState: Equatable, Sendable {
        /// Whether the per-model sliders + system-prompt override block render
        /// (chat models only — embedders have no sampling parameters).
        public let showsChatSliders: Bool

        /// `"default"` when no system-prompt override is set, else `"custom"`.
        public let systemPromptLabel: String

        /// Assignment chips, in render order. Subset of `["CHAT", "EMBED"]`.
        public let tags: [String]

        /// Conditional actions for the current download status.
        public let actions: [Action]

        /// Whether the row renders a live download-progress indicator in place of
        /// any action button. True only while `status == .downloading`, so the
        /// "Download" button is replaced by progress (and never sits there inert
        /// next to an in-flight transfer — the old behaviour that made a tapped
        /// download look like nothing happened).
        public let showsProgress: Bool

        /// Max-tokens slider seed, clamped so it never exceeds the model's
        /// context window (a 2048-context model must not seed 4096).
        public let maxTokensDefault: Int

        /// Max-tokens slider upper bound, floored at 256 so a malformed
        /// `contextLength` (e.g. 0) can never produce a degenerate
        /// `256...n, n < 256` range that traps `Slider`.
        public let maxTokensUpperBound: Int
    }

    /// Catalog/runtime default max tokens before the user overrides. Backs
    /// `RowState.maxTokensDefault`, which clamps this to the model's context
    /// window (a smaller-context model never seeds a value above its limit).
    static let maxTokensFallback = 4096

    public static func rowState(
        manifest: ModelManifest,
        localState: ModelManifestLocalState
    ) -> RowState {
        var tags: [String] = []
        if localState.assignedAsChat { tags.append("CHAT") }
        if localState.assignedAsEmbedder { tags.append("EMBED") }

        var actions: [Action] = []
        if localState.status == .downloaded {
            // Assign affordance (primary action, rendered first): only for a
            // downloaded model, only for its own purpose, and only when it is
            // not already the active model for that purpose (the CHAT/EMBED
            // tag already communicates the active state — a redundant assign
            // button would be noise).
            if manifest.purpose == "chat", !localState.assignedAsChat {
                actions.append(.assignChat)
            }
            if manifest.purpose == "embedder", !localState.assignedAsEmbedder {
                actions.append(.assignEmbedder)
            }
            actions.append(contentsOf: [.reDownload, .delete])
        } else if localState.status == .downloading {
            // A live transfer renders a progress indicator instead of any
            // button — no `.download` here, so a second tap can't spawn a
            // racing worker and the row visibly reflects the in-flight state.
        } else {
            // `.available` and `.error` both offer Download (retry from error;
            // the error reason is surfaced separately above the action row).
            actions.append(.download)
        }

        return RowState(
            showsChatSliders: manifest.purpose == "chat",
            systemPromptLabel: manifest.systemPromptOverride == nil ? "default" : "custom",
            tags: tags,
            actions: actions,
            showsProgress: localState.status == .downloading,
            maxTokensDefault: min(maxTokensFallback, max(manifest.contextLength, 256)),
            maxTokensUpperBound: max(manifest.contextLength, 256)
        )
    }

    // MARK: - Body

    public var body: some View {
        let state = Self.rowState(manifest: manifest, localState: localState)

        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 12) {
                if state.showsChatSliders {
                    chatControls(state: state)
                }

                if let last = localState.lastUsedAt {
                    Text("Last used: \(last, style: .relative)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // Surface a failed download instead of silently swallowing it. The
                // download manager records the reason on `localState.downloadError`
                // (status `.error`), but it was never shown — a failed download
                // looked identical to one that never started. Selectable so the
                // user can copy the reason when reporting a problem.
                if localState.status == .error, let downloadError = localState.downloadError {
                    Label("Download failed: \(downloadError)", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                if state.showsProgress {
                    downloadProgressView()
                } else {
                    actionRow(state: state)
                }
            }
            .padding(.top, 4)
        } label: {
            HStack(spacing: 6) {
                Text(manifest.displayName).bold()
                ForEach(state.tags, id: \.self) { tag in
                    ModelRowTagChip(text: tag)
                }
                Spacer()
                if state.showsProgress {
                    // Collapsed-row feedback: a moving percent (or an indeterminate
                    // spinner before the first byte sample) so an in-flight download
                    // is visible without expanding the row.
                    ProgressView().controlSize(.small)
                    if let progress {
                        Text("\(Int(progress.percent))%")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                } else {
                    Text(String(format: "%.1f GB", manifest.sizeGB))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .onChange(of: progress?.state, initial: true) { _, newState in
            // A finished transfer (success or failure) is reflected in the
            // `UserDefaults`-backed snapshot by the download worker; tell the
            // parent to reload so the row flips to Assign/Delete (or shows the
            // error) instead of spinning forever. `initial: true` covers a
            // transfer that already completed before the row first observed it
            // (only terminal states act; pending/active fall through).
            switch newState {
            case .completed, .failed, .cancelled:
                onDownloadFinished()
            default:
                break
            }
        }
    }

    @ViewBuilder
    private func downloadProgressView() -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let progress {
                ProgressView(value: progress.percent, total: 100)
                HStack {
                    Text("\(Int(progress.percent))%").monospacedDigit()
                    Spacer()
                    Text(Self.progressDetail(progress: progress, sizeGB: manifest.sizeGB))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            } else {
                // Status is `.downloading` but we have no live progress handle
                // (e.g. the screen reappeared mid-transfer): show an
                // indeterminate bar rather than a stale button.
                ProgressView().progressViewStyle(.linear)
                Text("Downloading…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// "1.2 / 5.2 GB" style detail, falling back to the catalog size when the
    /// total byte count is unknown.
    static func progressDetail(progress: ModelDownloadProgress, sizeGB: Double) -> String {
        let gb = 1_073_741_824.0
        let done = Double(progress.transferredBytes) / gb
        let total = progress.totalBytes > 0 ? Double(progress.totalBytes) / gb : sizeGB
        return String(format: "%.1f / %.1f GB", done, total)
    }

    // MARK: - Subviews

    @ViewBuilder
    private func chatControls(state: RowState) -> some View {
        Slider(
            value: Binding(
                get: { manifest.temperatureOverride ?? 0.7 },
                set: { manifest.temperatureOverride = $0 }
            ),
            in: 0...2,
            step: 0.05
        ) {
            Text("Temperature")
        }

        Slider(
            value: Binding(
                get: { Double(manifest.maxTokensOverride ?? state.maxTokensDefault) },
                set: { manifest.maxTokensOverride = Int($0.rounded()) }
            ),
            in: 256...Double(state.maxTokensUpperBound),
            step: 128
        ) {
            Text("Max tokens")
        }

        Slider(
            value: Binding(
                get: { Double(manifest.idleTimeoutSecondsOverride ?? 600) },
                set: { manifest.idleTimeoutSecondsOverride = Int($0) }
            ),
            in: 30...3600,
            step: 30
        ) {
            Text("Idle timeout (s)")
        }

        NavigationLink("System prompt: \(state.systemPromptLabel)") {
            TextEditor(
                text: Binding(
                    get: { manifest.systemPromptOverride ?? "" },
                    set: { manifest.systemPromptOverride = $0.isEmpty ? nil : $0 }
                )
            )
        }
    }

    @ViewBuilder
    private func actionRow(state: RowState) -> some View {
        HStack {
            ForEach(state.actions, id: \.self) { action in
                switch action {
                case .assignChat:
                    Button("Assign as Chat") { onAssignChat() }
                        .foregroundStyle(.secondary)
                case .assignEmbedder:
                    Button("Assign as Embedder") { onAssignEmbedder() }
                        .foregroundStyle(.secondary)
                case .download:
                    Button("Download") { onDownload() }
                        .buttonStyle(.borderedProminent)
                case .reDownload:
                    Button("Re-download") { onReDownload() }
                case .delete:
                    Button("Delete", role: .destructive) { onDelete() }
                }
            }
        }
    }
}

// MARK: - Private chip

/// Small uppercase assignment chip ("CHAT" / "EMBED"). Named to avoid colliding
/// with SwiftUI's `Tag`/`.tag(_:)` family.
private struct ModelRowTagChip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption2.bold())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.tint.opacity(0.15))
            .clipShape(Capsule())
    }
}

#endif
