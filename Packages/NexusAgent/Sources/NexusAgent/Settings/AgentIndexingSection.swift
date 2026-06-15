import NexusUI
import SwiftUI

public struct AgentIndexingSection: View {
    public let context: AgentSettingsContext
    @StateObject private var viewModel: AgentIndexingViewModel

    public init(context: AgentSettingsContext) {
        self.context = context
        _viewModel = StateObject(
            wrappedValue: AgentIndexingViewModel(
                context: context.auditContext,
                backfill: context.backfillJob
            )
        )
    }

    public var body: some View {
        LiquidGlassCard("Search index") {
            VStack(alignment: .leading, spacing: DS.Space.l) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Indexed")
                            .font(DS.FontToken.body.weight(.medium))
                            .foregroundStyle(DS.ColorToken.textPrimary)

                        Spacer(minLength: 12)

                        Text("\(viewModel.coverage.indexed) / \(viewModel.coverage.total)")
                            .font(DS.FontToken.metadata)
                            .foregroundStyle(DS.ColorToken.textSecondary)
                    }

                    // §3 activity: Accent.solid → Text.primary. The .tint
                    // modifier is retained (dropping it falls back to system
                    // accent hue, slice-1 NexusMacApp precedent). The oracle
                    // has no coverage-bar vocabulary (it shows "✓ zsync"
                    // text), so this is an oracle-gap primitive resolved to
                    // the achromatic ink ladder (§2 LabPalette.ink).
                    ProgressView(value: viewModel.coverage.ratio)
                        .tint(DS.ColorToken.textPrimary)
                }

                HStack(spacing: 10) {
                    NexusButton(variant: .outline, size: .sm, action: rebuild) {
                        Text("Rebuild full index")
                    }
                    .disabled(viewModel.isRebuilding)

                    if viewModel.isRebuilding {
                        // §3 activity: Accent.solid → Text.primary. .tint
                        // retained (slice-1 NexusMacApp precedent — dropping
                        // it re-introduces the system accent hue); the
                        // spinner conveys "live" by motion, ink only (§2
                        // LabPalette.ink).
                        ProgressView()
                            .controlSize(.small)
                            .tint(DS.ColorToken.textPrimary)
                    }
                }

                if let lastProgress = viewModel.lastProgress {
                    Text(lastRebuildSummary(lastProgress))
                        .font(DS.FontToken.caption)
                        .foregroundStyle(DS.ColorToken.textMuted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear {
            viewModel.refresh()
        }
    }

    private func rebuild() {
        Task {
            await viewModel.rebuild()
        }
    }

    private func lastRebuildSummary(_ progress: BackfillProgress) -> String {
        let suffix = "processed \(progress.processed), skipped \(progress.skipped)."
        guard let lastRebuildAt = viewModel.lastRebuildAt else {
            return "Last rebuild: \(suffix)"
        }
        return "Last rebuild \(lastRebuildAt.formatted(date: .abbreviated, time: .shortened)): \(suffix)"
    }
}
