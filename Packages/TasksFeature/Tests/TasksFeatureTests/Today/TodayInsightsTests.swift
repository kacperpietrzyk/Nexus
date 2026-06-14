import Foundation
import NexusAgent
import NexusCore
import Testing

@testable import TasksFeature

@Suite("TodayDashboard proactive insight card mapping")
@MainActor
struct TodayInsightsTests {

    // MARK: - Title mapping

    @Test("overload kind maps to schedule title")
    func overloadKindTitle() {
        #expect(TodayDashboard.insightTitle(for: "overload") == "Schedule looks overloaded")
    }

    @Test("day_plan kind maps to focus order title")
    func dayPlanKindTitle() {
        #expect(TodayDashboard.insightTitle(for: "day_plan") == "Suggested focus order")
    }

    @Test("meeting_decompose kind maps to follow-up title")
    func meetingDecomposeKindTitle() {
        #expect(
            TodayDashboard.insightTitle(for: "meeting_decompose") == "Meeting needs follow-up tasks"
        )
    }

    @Test("unknown kind falls back to generic title")
    func unknownKindFallsBackToGeneric() {
        #expect(TodayDashboard.insightTitle(for: "future_insight_type") == "Insight")
    }

    // MARK: - Advisory card (mutations: [])

    @Test("advisory card maps rationale and previews")
    func advisoryCardMapsRationaleAndPreviews() {
        let store = PendingInsightStore()
        let proposal = Proposal(
            rationale: "You have a busy Friday.",
            mutations: [],
            previews: [ProposalPreview(summary: "3 tasks at risk")]
        )
        store.add(kind: "overload", dedupeKey: "k1", proposal: proposal)
        let entry = store.pending[0]

        let model = TodayDashboard.insightCardModel(
            entry: entry,
            pending: store,
            coordinator: nil,
            cooldown: nil
        )

        #expect(model.title == "Schedule looks overloaded")
        #expect(model.rationale == "You have a busy Friday.")
        #expect(model.previews == ["3 tasks at risk"])
    }

    // MARK: - Dismiss resolves entry + records cooldown

    @Test("dismiss resolves entry and records cooldown key")
    func dismissResolvesEntryAndRecordsCooldown() {
        let store = PendingInsightStore()
        let proposal = Proposal(rationale: "Test", mutations: [], previews: [])
        store.add(kind: "overload", dedupeKey: "cool-key", proposal: proposal)
        let entry = store.pending[0]

        var recorded: String?
        let cooldown = InsightCooldownStore(
            defaults: UserDefaults(suiteName: "nexus.test.insights.\(UUID())")!,
            now: { Date() }
        )

        let model = TodayDashboard.insightCardModel(
            entry: entry,
            pending: store,
            coordinator: nil,
            cooldown: cooldown
        )

        model.reject()

        #expect(store.pending.isEmpty, "entry should be resolved after dismiss")
        // Verify cooldown was recorded by confirming shouldFire returns false
        // (cooldown was just set, so it should not fire again for 1 s).
        #expect(
            cooldown.shouldFire(key: "cool-key", cooldown: 1) == false,
            "cooldown should be recorded after dismiss"
        )
    }

    // MARK: - Advisory accept also dismisses

    @Test("advisory accept calls same dismiss logic (no mutations)")
    func advisoryAcceptDismisses() async {
        let store = PendingInsightStore()
        let proposal = Proposal(rationale: "Advisory", mutations: [], previews: [])
        store.add(kind: "day_plan", dedupeKey: "dp-key", proposal: proposal)
        let entry = store.pending[0]

        let cooldown = InsightCooldownStore(
            defaults: UserDefaults(suiteName: "nexus.test.insights.\(UUID())")!,
            now: { Date() }
        )

        let model = TodayDashboard.insightCardModel(
            entry: entry,
            pending: store,
            coordinator: nil,
            cooldown: cooldown
        )

        await model.accept()

        #expect(store.pending.isEmpty, "advisory accept should resolve entry")
        #expect(
            cooldown.shouldFire(key: "dp-key", cooldown: 1) == false,
            "advisory accept should record cooldown"
        )
    }

    // MARK: - Multiple entries: only first shown, count badge correct

    @Test("pending count reflects all entries; first entry is the visible one")
    func pendingCountAndFirstEntry() {
        let store = PendingInsightStore()
        store.add(
            kind: "overload",
            dedupeKey: "k1",
            proposal: Proposal(rationale: "A", mutations: [], previews: [])
        )
        store.add(
            kind: "day_plan",
            dedupeKey: "k2",
            proposal: Proposal(rationale: "B", mutations: [], previews: [])
        )
        store.add(
            kind: "meeting_decompose",
            dedupeKey: "k3",
            proposal: Proposal(rationale: "C", mutations: [], previews: [])
        )

        #expect(store.count == 3)
        #expect(store.pending.first?.kind == "overload")
    }
}
