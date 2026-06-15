import NexusAgent
import NexusUI
import SwiftUI

// MARK: - Environment keys for proactive-insight stores

private struct PendingInsightStoreKey: EnvironmentKey {
    static let defaultValue: PendingInsightStore? = nil
}

private struct InsightProposalCoordinatorKey: EnvironmentKey {
    static let defaultValue: ProposalCoordinator? = nil
}

private struct InsightCooldownStoreKey: EnvironmentKey {
    static let defaultValue: InsightCooldownStore? = nil
}

extension EnvironmentValues {
    /// Pending proactive insights. Nil when the host has not wired the insight
    /// coordinator (e.g. previews, standalone Today, test beds).
    public var pendingInsightStore: PendingInsightStore? {
        get { self[PendingInsightStoreKey.self] }
        set { self[PendingInsightStoreKey.self] = newValue }
    }

    /// Coordinator that applies proposal mutations. Nil default keeps
    /// existing callers compile-clean.
    public var insightProposalCoordinator: ProposalCoordinator? {
        get { self[InsightProposalCoordinatorKey.self] }
        set { self[InsightProposalCoordinatorKey.self] = newValue }
    }

    /// Cooldown store used to record dismiss times. Nil default keeps
    /// existing callers compile-clean.
    public var insightCooldownStore: InsightCooldownStore? {
        get { self[InsightCooldownStoreKey.self] }
        set { self[InsightCooldownStoreKey.self] = newValue }
    }
}

// MARK: - Pure mapper

extension TodayDashboard {
    /// Maps a `PendingInsightStore.Entry` to `ProposalConfirmCardModel`.
    ///
    /// Advisory entries (`mutations.isEmpty`) wire `onAccept` to the same
    /// dismiss+cooldown closure as `onReject` — the apply button has no side
    /// effects but still dismisses cleanly.
    ///
    /// Actionable entries call `ProposalCoordinator.accept` on apply.
    ///
    /// Extracted as a static so the test target can drive it without SwiftUI.
    @MainActor
    static func insightCardModel(
        entry: PendingInsightStore.Entry,
        pending: PendingInsightStore,
        coordinator: ProposalCoordinator?,
        cooldown: InsightCooldownStore?
    ) -> ProposalConfirmCardModel {
        let title = Self.insightTitle(for: entry.kind)
        let previews = entry.proposal.previews.map { $0.summary }

        let dismiss: @MainActor () -> Void = {
            pending.resolve(id: entry.id)
            cooldown?.record(key: entry.dedupeKey)
        }

        let isActionable = !entry.proposal.mutations.isEmpty

        let accept: @MainActor () async -> Void
        if isActionable, let coordinator {
            let proposal = entry.proposal
            accept = {
                _ = try? await coordinator.accept(proposal, threadID: nil)
                pending.resolve(id: entry.id)
            }
        } else {
            // Advisory: apply = dismiss (no mutations to run).
            accept = { dismiss() }
        }

        return ProposalConfirmCardModel(
            title: title,
            rationale: entry.proposal.rationale,
            previews: previews,
            onAccept: accept,
            onReject: dismiss
        )
    }

    /// Human-readable card title derived from insight kind.
    static func insightTitle(for kind: String) -> String {
        switch kind {
        case "overload":
            return "Schedule looks overloaded"
        case "day_plan":
            return "Suggested focus order"
        case "meeting_decompose":
            return "Meeting needs follow-up tasks"
        default:
            return "Insight"
        }
    }
}

// MARK: - Insight banner (TodayDashboard extension)

extension TodayDashboard {
    /// Renders the top pending insight as a ProposalConfirmCard-style banner,
    /// matching the `deadlineRiskBanner()` chrome.
    @ViewBuilder
    func insightBanner() -> some View {
        if let store = pendingInsightStore, let entry = store.pending.first {
            let model = TodayDashboard.insightCardModel(
                entry: entry,
                pending: store,
                coordinator: insightProposalCoordinator,
                cooldown: insightCooldownStore
            )
            InsightBannerRow(model: model, extraCount: max(0, store.count - 1))
                .id(entry.id)
        }
    }
}

// MARK: - InsightBannerRow (private view)

/// Banner row that mirrors `deadlineRiskBanner()` chrome but drives from
/// `ProposalConfirmCardModel` so it's fully testable without SwiftUI rendering.
///
/// Internal (not `private`) so the shared `LiquidTodayScreen` can render the
/// same banner — both Today surfaces drive it from the identical
/// `TodayDashboard.insightCardModel(...)` mapper.
struct InsightBannerRow: View {
    @State var model: ProposalConfirmCardModel
    let extraCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "sparkles")
                    .foregroundStyle(NexusColor.Text.secondary)
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(model.title)
                            .font(NexusType.bodySmall.weight(.semibold))
                            .foregroundStyle(NexusColor.Text.primary)
                        if extraCount > 0 {
                            NexusBadge("+\(extraCount) more", tone: .muted)
                        }
                        Spacer(minLength: 0)
                    }

                    if !model.rationale.isEmpty {
                        Text(model.rationale)
                            .font(NexusType.caption)
                            .foregroundStyle(NexusColor.Text.tertiary)
                            .multilineTextAlignment(.leading)
                            .lineLimit(3)
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                NexusColor.Background.raised,
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(NexusColor.Line.hairline, lineWidth: 1)
            }

            HStack(spacing: 8) {
                Button("Dismiss") { model.reject() }
                    .buttonStyle(.plain)
                    .font(NexusType.caption)
                    .foregroundStyle(NexusColor.Text.secondary)

                Button(model.isApplying ? "Applying…" : "Apply") {
                    Task { await model.accept() }
                }
                .buttonStyle(.plain)
                .font(NexusType.caption.weight(.semibold))
                .foregroundStyle(NexusColor.Text.primary)
                .disabled(model.isApplying)
            }
            .padding(.top, 6)
            .padding(.leading, 12)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(model.title). \(model.rationale)")
    }
}
