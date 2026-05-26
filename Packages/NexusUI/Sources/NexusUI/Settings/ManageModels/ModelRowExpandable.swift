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

    @State private var expanded = false

    // Invoked by the parent's assignment affordance (Task 27), not by this row's own controls.
    private let onAssignChat: () -> Void
    private let onAssignEmbedder: () -> Void
    private let onDownload: () -> Void
    private let onDelete: () -> Void
    private let onReDownload: () -> Void

    public init(
        manifest: ModelManifest,
        localState: ModelManifestLocalState,
        onAssignChat: @escaping () -> Void = {},
        onAssignEmbedder: @escaping () -> Void = {},
        onDownload: @escaping () -> Void = {},
        onDelete: @escaping () -> Void = {},
        onReDownload: @escaping () -> Void = {}
    ) {
        self.manifest = manifest
        self.localState = localState
        self.onAssignChat = onAssignChat
        self.onAssignEmbedder = onAssignEmbedder
        self.onDownload = onDownload
        self.onDelete = onDelete
        self.onReDownload = onReDownload
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
        } else {
            actions.append(.download)
        }

        return RowState(
            showsChatSliders: manifest.purpose == "chat",
            systemPromptLabel: manifest.systemPromptOverride == nil ? "default" : "custom",
            tags: tags,
            actions: actions,
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

                actionRow(state: state)
            }
            .padding(.top, 4)
        } label: {
            HStack(spacing: 6) {
                Text(manifest.displayName).bold()
                ForEach(state.tags, id: \.self) { tag in
                    ModelRowTagChip(text: tag)
                }
                Spacer()
                Text(String(format: "%.1f GB", manifest.sizeGB))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
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
