import SwiftUI

#if !os(watchOS)

import NexusAI

/// Welcome-flow screen that shows the auto-detected on-device model recommendation
/// and lets the user confirm, override, or skip MLX setup.
public struct DownloadModelStep: View {
    @Bindable var state: WelcomeFlowState
    let tier: DeviceTier
    let catalog: ModelCatalog.CatalogDoc
    let onContinue: () -> Void

    public init(
        state: WelcomeFlowState,
        tier: DeviceTier,
        catalog: ModelCatalog.CatalogDoc,
        onContinue: @escaping () -> Void = {}
    ) {
        self.state = state
        self.tier = tier
        self.catalog = catalog
        self.onContinue = onContinue
    }

    /// Test-convenience init — loads the bundled DefaultCatalog.json automatically.
    init(state: WelcomeFlowState, tier: DeviceTier) throws {
        self.state = state
        self.tier = tier
        self.catalog = try ModelCatalog.loadDefault()
        self.onContinue = {}
    }

    // MARK: - Download planning

    /// One model the welcome flow should fetch, resolved against the catalog.
    public struct DownloadRequest: Equatable, Sendable {
        public let manifestID: String
        public let hfPath: String
        public let totalBytes: Int64
        /// `"chat"` or `"embedder"` — mirrors `ModelManifest.purpose`. Threaded
        /// into `ModelDownloadManager.startDownload` so a completed download
        /// can auto-assign itself as the active model for its purpose when
        /// none is assigned yet (Task 27b).
        public let purpose: String
    }

    /// Pure decision: which `(manifestID, hfPath, totalBytes)` the welcome flow
    /// should download given the user's selection and the catalog. Returns `[]`
    /// when the user skipped MLX. Chat is ordered before the embedder so the
    /// chat download is kicked off first; the transfers themselves then proceed
    /// concurrently via the download manager (`startDownload` returns
    /// immediately). Selections that don't resolve to a catalog entry are
    /// silently dropped.
    public static func downloadPlan(
        state: WelcomeFlowState,
        catalog: ModelCatalog.CatalogDoc
    ) -> [DownloadRequest] {
        guard !state.skipMLX else { return [] }

        func request(
            for id: String?, in entries: [ModelCatalog.Entry], purpose: String
        ) -> DownloadRequest? {
            guard let id, let entry = entries.first(where: { $0.id == id }) else { return nil }
            return DownloadRequest(
                manifestID: entry.id,
                hfPath: entry.hfPath,
                totalBytes: Int64(entry.sizeGB * 1_073_741_824),
                purpose: purpose
            )
        }

        let chat = request(for: state.selectedChatModelID, in: catalog.chat, purpose: "chat")
        let embedder = request(
            for: state.selectedEmbedderID, in: catalog.embedders, purpose: "embedder")

        var plan: [DownloadRequest] = []
        if let chat { plan.append(chat) }
        if let embedder { plan.append(embedder) }
        return plan
    }

    // MARK: - Tested contract

    public func applyDefaultRecommendation() {
        state.selectedChatModelID = tier.recommendedChat
        state.selectedEmbedderID = tier.recommendedEmbedder
        state.skipMLX = false
        state.persist()
    }

    public func applySkipPath() {
        state.selectedChatModelID = nil
        state.selectedEmbedderID = nil
        state.skipMLX = true
        state.persist()
    }

    // MARK: - Body

    public var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                Spacer(minLength: 24)

                // §3 achromatic — DownloadModelStep is §3-audit-only: MLX-specific, no oracle counterpart;
                // structure/typography are NOT rebuilt to any oracle screen — only accent burn applies here.
                // Hero icon (cpu.fill): screen-identity glyph → Text.secondary (§2 map, salience by 56pt size).
                // Recommended badge (checkmark.circle.fill in `recommendedSection(label:entry:)`):
                //   §3 Categorical/confirmation → ink-ladder; matches oracle FlowsPreview checkmark at
                //   LabPalette.read + MP-4.1 slice-2 "ok → Text.secondary".
                // Selection indicators — skip-row (`state.skipMLX`) in `manualOverrideSection` and the
                //   `ModelRadioRow` (`isSelected`) glyph: achromatic state already carried by shape swap
                //   (fill vs strokeBorder); accent emphasis is redundant → same Text.secondary step as the
                //   recommended badge (uniform treatment across model-list rows).
                Image(systemName: "cpu.fill")
                    .font(.system(size: 56, weight: .light))
                    .foregroundStyle(NexusColor.Text.secondary)
                    .accessibilityHidden(true)

                VStack(spacing: 10) {
                    Text("On-device AI models")
                        .font(NexusType.h1)
                        .foregroundStyle(NexusColor.Text.primary)
                        .multilineTextAlignment(.center)

                    Text(
                        "Nexus can use local MLX models for intelligent summarization"
                            + " and semantic search without sending data to the cloud."
                    )
                    .font(NexusType.body)
                    .foregroundStyle(NexusColor.Text.tertiary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 440)
                }

                deviceMemoryLabel

                VStack(spacing: 0) {
                    recommendedChatRow
                    recommendedEmbedderRow
                }
                .background(NexusColor.Background.panel)
                .clipShape(RoundedRectangle(cornerRadius: NexusRadius.r4, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: NexusRadius.r4, style: .continuous)
                        .strokeBorder(NexusColor.Line.regular, lineWidth: 1)
                )
                .frame(maxWidth: 440)

                manualOverrideSection

                actionRow

                Spacer(minLength: 8)
            }
            .padding(.horizontal, 32)
        }
        .accessibilityLabel("AI model setup")
    }

    // MARK: - Subviews

    @ViewBuilder
    private var deviceMemoryLabel: some View {
        let ramGB = Int(ProcessInfo.processInfo.physicalMemory / 1_073_741_824)
        Text("Device memory: \(ramGB) GB RAM")
            .font(NexusType.meta)
            .foregroundStyle(NexusColor.Text.muted)
    }

    @ViewBuilder
    private var recommendedChatRow: some View {
        if let chatID = tier.recommendedChat, let chatEntry = catalog.chat.first(where: { $0.id == chatID }) {
            recommendedSection(label: "Chat", entry: chatEntry)
        }
    }

    @ViewBuilder
    private var recommendedEmbedderRow: some View {
        if let embedderID = tier.recommendedEmbedder {
            if let embedderEntry = catalog.embedders.first(where: { $0.id == embedderID }) {
                Divider()
                    .background(NexusColor.Line.hairline)
                recommendedSection(label: "Embedder", entry: embedderEntry)
            }
        }
    }

    private func recommendedSection(label: String, entry: ModelCatalog.Entry) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(label.uppercased())
                    .font(NexusType.eyebrow)
                    .foregroundStyle(NexusColor.Text.muted)
                Text(entry.displayName)
                    .font(NexusType.bodySmall)
                    .foregroundStyle(NexusColor.Text.primary)
                Text(String(format: "%.1f GB · %d K context", entry.sizeGB, entry.contextLength / 1000))
                    .font(NexusType.caption)
                    .foregroundStyle(NexusColor.Text.tertiary)
            }
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(NexusColor.Text.secondary)
                .accessibilityLabel("\(label) recommended")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var manualOverrideSection: some View {
        DisclosureGroup {
            VStack(spacing: 2) {
                ForEach(catalog.chat, id: \.id) { entry in
                    ModelRadioRow(
                        entry: entry,
                        isSelected: state.selectedChatModelID == entry.id && !state.skipMLX,
                        action: {
                            state.selectedChatModelID = entry.id
                            state.selectedEmbedderID = tier.recommendedEmbedder
                            state.skipMLX = false
                            state.persist()
                        }
                    )
                }

                Divider()
                    .padding(.vertical, 4)
                    .background(NexusColor.Line.hairline)

                // Skip row
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Skip — cloud only / Apple Intelligence")
                            .font(NexusType.bodySmall)
                            .foregroundStyle(NexusColor.Text.secondary)
                    }
                    Spacer()
                    if state.skipMLX {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(NexusColor.Text.secondary)
                    } else {
                        Circle()
                            .strokeBorder(NexusColor.Line.regular, lineWidth: 1.5)
                            .frame(width: 18, height: 18)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    applySkipPath()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
        } label: {
            Text("Choose manually")
                .font(NexusType.meta)
                .foregroundStyle(NexusColor.Text.tertiary)
        }
        .frame(maxWidth: 440)
    }

    @ViewBuilder
    private var actionRow: some View {
        VStack(spacing: 12) {
            if tier.recommendedChat != nil {
                NexusButton(
                    variant: .primary,
                    size: .lg,
                    action: {
                        applyDefaultRecommendation(); onContinue()
                    },
                    label: { Text("Install recommended").frame(maxWidth: .infinity) }
                )
                .frame(maxWidth: 320)

                NexusButton(
                    variant: .outline,
                    size: .sm,
                    action: {
                        applySkipPath(); onContinue()
                    },
                    label: { Text("Skip for now") }
                )
            } else {
                NexusButton(
                    variant: .primary,
                    size: .lg,
                    action: {
                        applySkipPath(); onContinue()
                    },
                    label: { Text("Continue").frame(maxWidth: .infinity) }
                )
                .frame(maxWidth: 320)
            }
        }
    }
}

// MARK: - Private helper

private struct ModelRadioRow: View {
    let entry: ModelCatalog.Entry
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.displayName)
                    .font(NexusType.bodySmall)
                    .foregroundStyle(NexusColor.Text.primary)
                Text(String(format: "%.1f GB · min. %d GB RAM", entry.sizeGB, entry.recommendedRAMGB))
                    .font(NexusType.caption)
                    .foregroundStyle(NexusColor.Text.tertiary)
            }
            Spacer()
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(NexusColor.Text.secondary)
                    .accessibilityLabel("Selected")
            } else {
                Circle()
                    .strokeBorder(NexusColor.Line.regular, lineWidth: 1.5)
                    .frame(width: 18, height: 18)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .accessibilityLabel(entry.displayName)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

#endif
