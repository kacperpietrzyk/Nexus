import NexusCore
import NexusUI
import SwiftData
import SwiftUI

// MARK: - Embedded-Today status-sectioned main column (MP-2 slice 2)
//
// Rebuilds the Today main column to the accepted Lab organism: a vertical
// stack of status sections — TODAY / AWAITING YOU / LATER — each an
// eyebrow + count header over the shipped MP-2.1 row idiom (`TaskRowView`,
// status glyph + title + meta + Mac hover quick-actions). No greeting hero,
// no linear day-progress, no time-slot schedule (those stay on the
// standalone path). Sectioning is a presentation reorg over the existing
// `TodayQuery` facets — no schema/repo/parser/behaviour change. Achromatic;
// every section consumes frozen MP-1 `Nexus*` primitives only.

extension TodayDashboard {

    /// The embedded (Nexus shell) Today main column. Mounted only when
    /// `chrome == .embedded`; the standalone/iOS-compact paths keep
    /// `todayContent` unchanged.
    var embeddedTodayContent: some View {
        ScrollView {
            // MP-2 slice-5: empty is a real, earned state — not absence.
            // When every loaded bucket is empty AND nothing is pinned AND
            // there is no error to surface, the column shows the Lab
            // `.achievement` "All clear" reward instead of bare/absent
            // section headers (oracle: `TodayHUDPreview.swift` `isEmpty`
            // branch → `LabEmptyState(tone: .achievement, …)`). The error
            // term is part of the predicate deliberately: an inline error
            // row and a celebratory achievement state must never co-render
            // (you do not reward the user while signalling a failure).
            // `embeddedError` is set from two places — the +EmbeddedToday
            // action handlers (✓ / ⏰ repository throws) AND
            // `reloadScheduleData()`'s catch (a data-load failure). In
            // either case `embeddedError != nil` flips
            // `embeddedTodayIsEmpty` false, so the sectioned branch runs
            // and `embeddedErrorRow` shows the failure instead of the
            // achievement — including on a load failure that zeroed the
            // buckets (which would otherwise satisfy the empty-state gate).
            if embeddedTodayIsEmpty {
                embeddedEmptyState
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 460)
                    .padding(.horizontal, 26)
                    .padding(.vertical, 24)
            } else {
                embeddedTodaySectioned
            }
        }
        .scrollContentBackground(.hidden)
        // Mirrors `TaskListView`'s `.cascadeCompletionConfirmation` on its
        // `List`: a `parentHasOpenSubtasks` throw from the row ✓ quick-action
        // raises the same confirm-then-cascade dialog the standalone path uses.
        .cascadeCompletionConfirmation($embeddedCascadePrompt) { prompt in
            embeddedConfirmCascade(prompt)
        }
    }

    /// The empty-state gate: true iff the three already-loaded buckets are
    /// all empty, no task is pinned as the NowCard focus, and there is no
    /// inline error to surface. Pure presentation predicate over state the
    /// column already loaded — no schema/repo/query/behaviour. The
    /// `featuredNowTask` term is derived from the same three buckets so it
    /// is logically redundant with bucket-emptiness, but kept explicit as
    /// defense-in-depth and to mirror the scaffold's literal predicate.
    /// That redundancy holds ONLY under the current "pin selected from the
    /// three loaded buckets" policy: if the deferred NowCard
    /// selection-policy follow-up (see the "KNOWN GATING LIMITATION"
    /// note in `embeddedTodaySectioned`) ever widens
    /// `featuredNowTask`'s source — e.g. adds a dedicated pinned-task query
    /// so an out-of-bucket pinned task can surface — the term stops being
    /// redundant and becomes load-bearing; a future implementer of that
    /// follow-up must NOT delete it. The `embeddedError` term keeps the
    /// achievement reward and an error row mutually exclusive (see the
    /// call-site comment).
    ///
    /// Delegates to the pure static form so the load-failure→error
    /// transition is unit-testable without driving SwiftUI (same
    /// `InspectorVisibility.shouldShowInspector` / `TodayDashboardContentRoute.route`
    /// §12 precedent).
    var embeddedTodayIsEmpty: Bool {
        Self.embeddedTodayIsEmpty(
            todayTasks: embeddedTodayTasks,
            awaiting: embeddedAwaiting,
            laterTasks: embeddedLaterTasks,
            featuredNowTask: featuredNowTask,
            error: embeddedError
        )
    }

    /// Pure static predicate for the embedded-Today empty-state gate.
    /// Returns `true` iff every loaded bucket is empty, no task is pinned
    /// as the NowCard focus, and there is no inline error to surface.
    ///
    /// The `error` term is load-bearing: a data-load failure zeros the
    /// buckets and sets `embeddedError` — without this guard the
    /// zeroed-bucket path would satisfy the gate and falsely show the
    /// "All clear" achievement while simultaneously signalling a failure.
    /// Extracted as a pure `internal static` (not `public` — §5 surface-area
    /// guard) so the production path and the test suite call the same function.
    static func embeddedTodayIsEmpty(
        todayTasks: [TaskItem],
        awaiting: [AwaitingEntry],
        laterTasks: [TaskItem],
        featuredNowTask: TaskItem?,
        error: String?
    ) -> Bool {
        todayTasks.isEmpty
            && awaiting.isEmpty
            && laterTasks.isEmpty
            && featuredNowTask == nil
            && error == nil
    }

    /// The Lab `.achievement` empty state ("All clear"), built from Nexus
    /// tokens only — no `Lab*` import. Mirrors the oracle's
    /// `LabEmptyState(tone: .achievement, …)`
    /// (`LabKit.swift` ≈443–520): a circle-stroked check glyph (34pt
    /// circle, 1.3pt stroke, 12pt-semibold checkmark) over a Geist-SemiBold
    /// 17 title and a Geist-Regular 12.5 subtitle, centered in a 380pt
    /// measure. Achromatic — every tone is a `NexusColor.Text.*` token,
    /// using the same LabPalette→token map slice-4 documented
    /// (`read→Text.secondary`, `faint→Text.muted`, `dim→Text.disabled`).
    ///
    /// Geist-SemiBold 17 / Geist-Regular 12.5 are not `NexusType.Metrics`
    /// sizes (h3 is 18/medium, caption 11/regular), so `Font.custom` with
    /// the process-wide-registered Geist family is used to hit the oracle's
    /// exact type — the same supported mechanism, and the same documented
    /// precedent, as the Canvas sub-tokens in `+EmbeddedTimeline.swift`.
    ///
    /// TELEMETRY PILL OMITTED (explicit, reported to the user): the oracle
    /// composes a `LabBackgroundTelemetry` "N items handled in background today"
    /// pill under the achievement copy. That pill needs a today-scoped
    /// `AgentActivityLog` count which is NOT reachable from this view — it
    /// would require a new query into agent-activity state. That is the
    /// SAME deferred-backend family as the "since you last looked" delta-strip
    /// (persisted last-viewed state): building either is backend-reach the
    /// user must decide (`feedback_no_canvas_emulation_without_backend`).
    /// The pill is therefore intentionally omitted; the achievement copy
    /// alone is the earned-state reward. Tracked follow-up for MP-2.2
    /// pattern-lock / the controller (MP-6.5), bundled with the delta-strip.
    @ViewBuilder
    var embeddedEmptyState: some View {
        VStack(spacing: 0) {
            // Oracle glyph: 34×34 circle stroked at 1.3pt + a 12pt-semibold
            // SF `checkmark`. Achromatic — stroke is `Text.disabled` (Lab
            // `dim`), glyph is `Text.muted` (Lab `faint`).
            ZStack {
                Circle()
                    .stroke(NexusColor.Text.tertiary.opacity(0.75), lineWidth: 1.4)
                    .frame(width: 42, height: 42)
                Image(systemName: "checkmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(NexusColor.Text.secondary)
            }
            .frame(height: 46)
            .padding(.bottom, 20)

            Text("All clear")
                .font(Font.custom("Geist-SemiBold", size: 22))
                .foregroundStyle(NexusColor.Text.primary)
                .multilineTextAlignment(.center)

            Text(
                "Nothing is waiting for you. The agent watches the background — "
                    + "it will reach out when something needs a decision."
            )
            .font(Font.custom("Geist-Regular", size: 13.5))
            .foregroundStyle(NexusColor.Text.tertiary)
            .multilineTextAlignment(.center)
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 8)

            Text("No tasks or blocks today")
                .font(NexusType.meta)
                .foregroundStyle(NexusColor.Text.muted)
                .padding(.top, 16)

            NexusButton(
                variant: .primary,
                size: .md,
                action: { onOpenCapture(.task) },
                label: {
                    HStack(spacing: 7) {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Add your first task")
                    }
                }
            )
            .padding(.top, 16)
        }
        .frame(maxWidth: 420)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .offset(y: 16)
        // Entrance consistency with the rest of the anchor: NowCard and
        // section rows both use `.nexusAppear`; the achievement empty-state
        // otherwise snapped in abruptly. Reduce-Motion-gated internally by
        // the modifier (no call-site gate needed).
        .nexusAppear(0)
    }

    /// The status-sectioned column (the non-empty branch). Unchanged from
    /// slices 2–4 — only lifted out of `embeddedTodayContent` so the
    /// slice-5 empty/non-empty fork stays a single readable `if`.
    @ViewBuilder
    var embeddedTodaySectioned: some View {
        VStack(alignment: .leading, spacing: 26) {
            // MP-2 slice-3: NowCard "TERAZ" — the Today-specific anchor.
            //
            // GATING (binding plan row "NowCard `TERAZ`"): the card
            // surfaces ONLY the existing `TaskItem.pinnedAsFocus` flag
            // (NexusCore TaskItem.swift:41). It is rendered solely when
            // exactly one already-loaded task carries that flag — no new
            // query / predicate / repo method / `TodayQuery` facet, and
            // NO invented selection chain. `featuredNowTask` is a pure
            // filter over the three buckets THIS column already loaded.
            //   • none pinned  → region omitted entirely (no card, no
            //     placeholder) via the `if let` below.
            //   • one pinned   → NowCard for it.
            //   • many pinned  → first in existing bucket order
            //     (TODAY → AWAITING → LATER), deterministic, no new sort.
            //
            // DEFERRED PRODUCT DECISION (explicit follow-up for the
            // user, NOT decided here): the policy for what "TERAZ"
            // should pick when nothing is pinned — and how/where the
            // `pinnedAsFocus` flag itself gets set in the UI — is an
            // explicit deferred follow-up. This slice only renders the
            // existing flag; it does not introduce a fallback chain or
            // a pin affordance.
            //
            // KNOWN GATING LIMITATION (also reported): a task with
            // `pinnedAsFocus == true` that lives OUTSIDE the three
            // already-loaded buckets (e.g. snoozed, done, or otherwise
            // outside TODAY/AWAITING/LATER) will NOT surface here. Adding
            // a dedicated pinned-task query is intentionally NOT done
            // (it would be invented backend); it is a deferred product
            // decision tied to the selection-policy follow-up above.
            if let featuredNowTask {
                embeddedNowCard(featuredNowTask)
            }

            if let embeddedError {
                embeddedErrorRow(embeddedError)
            }

            if !embeddedTodayTasks.isEmpty {
                embeddedSection(eyebrow: "TODAY", count: embeddedTodayTasks.count) {
                    embeddedRows(embeddedTodayTasks)
                }
            }

            if !embeddedAwaiting.isEmpty {
                embeddedSection(eyebrow: "AWAITING YOU", count: embeddedAwaiting.count) {
                    embeddedAwaitingRows(embeddedAwaiting)
                }
            }

            if !embeddedLaterTasks.isEmpty {
                embeddedSection(eyebrow: "LATER", count: embeddedLaterTasks.count) {
                    // LATER is rendered recessed. The recession is a
                    // presentation-only opacity on the ROWS only — the
                    // eyebrow + count stay at full tone so the section
                    // label keeps its legibility (matches the Lab oracle,
                    // which dims rows but not the section header).
                    // `TaskRowView` has no dimmed parameter and its API is
                    // frozen, so the dimming lives on the row container.
                    embeddedRows(embeddedLaterTasks)
                        .opacity(0.65)
                }
            }
        }
        .frame(maxWidth: 620, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 26)
        .padding(.vertical, 24)
    }

    /// ScrollView translation of `TaskListView.errorRow`: same `.caption` +
    /// `NexusColor.Text.primary` ink (achromatic — legibility via contrast,
    /// not hue), but with explicit padding instead of the `List`-only
    /// `listRowInsets`/`listRowBackground`/`listRowSeparator` modifiers, which
    /// no-op outside a `List`.
    @ViewBuilder
    func embeddedErrorRow(_ message: String) -> some View {
        Text(message)
            .font(.caption)
            .foregroundStyle(NexusColor.Text.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
    }

    // MARK: - NowCard "TERAZ" (Today-specific anchor, gated on pinnedAsFocus)

    /// The single task the NowCard features, or `nil` to omit the region.
    ///
    /// Pure first-match filter over the data the embedded column ALREADY
    /// loaded — NOT a new query/predicate/sort. Walk order is the exact
    /// on-screen section order: TODAY (`embeddedTodayTasks`) → AWAITING YOU
    /// (`embeddedAwaiting`, unwrapping `AwaitingEntry.task`) → LATER
    /// (`embeddedLaterTasks`). The first task with `pinnedAsFocus == true`
    /// in that order wins; if none carry the flag the property is `nil`
    /// and the NowCard region is omitted entirely.
    var featuredNowTask: TaskItem? {
        if let pinned = embeddedTodayTasks.first(where: { $0.pinnedAsFocus }) {
            return pinned
        }
        if let pinned = embeddedAwaiting.first(where: { $0.task.pinnedAsFocus }) {
            return pinned.task
        }
        return embeddedLaterTasks.first(where: { $0.pinnedAsFocus })
    }

    /// The NowCard subtitle, or `nil` to omit the subtitle Text entirely.
    ///
    /// Project name ONLY, via the existing `projectName(_:)` lookup.
    /// `TaskItem` has no estimate/duration field, so the Lab oracle's
    /// "~40 min" element has no backing data and is intentionally dropped
    /// (NOT derived from `endAt - startAt`, which would invent an
    /// "estimate" semantic). `nil` when the task has no project, or the
    /// project is archived/deleted and the lookup returns `nil` — the
    /// caller then renders no subtitle Text (never an empty string).
    func embeddedNowSubtitle(_ task: TaskItem) -> String? {
        guard let projectID = task.projectID else { return nil }
        return projectName(projectID)
    }

    /// The `Nexus*`/token equivalent of the Lab `NowCard` oracle
    /// (`TodayHUDPreview.swift` `NowCard`): 9pt ink dot + "NOW" eyebrow
    /// (mono, traced) + title + optional project subtitle + a glass-capsule
    /// "Focus" pill, all on a `.nexusGlass` rounded-18 card with 20pt
    /// padding. Achromatic — every tone is a `NexusColor.Text.*` token; no
    /// hue, no `Lab*` import. The shell already paints the wallpaper in
    /// embedded chrome, so the card layers glass over it (no double-glass).
    @ViewBuilder
    func embeddedNowCard(_ task: TaskItem) -> some View {
        HStack(alignment: .top, spacing: 16) {
            // Oracle: 9×9 LabPalette.ink circle → achromatic primary ink.
            // Purely decorative marker — hidden from VoiceOver (LabKit A2).
            Circle()
                .fill(NexusColor.Text.primary)
                .frame(width: 9, height: 9)
                .padding(.top, 5)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                Text("NOW")
                    .nexusType(.eyebrow)
                    .foregroundStyle(NexusColor.Text.muted)

                // Title from the existing `TaskItem.title` field only.
                Text(task.title)
                    .font(NexusType.h3)
                    .foregroundStyle(NexusColor.Text.primary)
                    .fixedSize(horizontal: false, vertical: true)

                // Subtitle = project name ONLY, via the existing
                // `projectName(_:)` lookup. `TaskItem` has no
                // estimate/duration field, so the oracle's "~40 min"
                // element has no backing data and is intentionally
                // omitted (not fabricated from `endAt - startAt`, which
                // would be an invented "estimate" semantic). If the task
                // has no project (or the project is archived/deleted and
                // the lookup returns nil) the subtitle Text is omitted
                // entirely — never rendered as an empty string.
                if let projectTitle = embeddedNowSubtitle(task) {
                    Text(projectTitle)
                        .font(NexusType.meta)
                        .foregroundStyle(NexusColor.Text.secondary)
                }
            }

            Spacer(minLength: 16)

            // "Focus" — routes to the EXISTING focus-mode entry only.
            embeddedFocusPill(task)
        }
        .padding(20)
        .nexusGlass(.regular, cornerRadius: 18)
        .nexusGlassRim(cornerRadius: 18)
        .nexusAppear(0)
    }

    /// The glass-capsule "Focus" pill. Mirrors the Lab oracle's
    /// inner-pill-over-outer-card layering: a custom HStack clipped to a
    /// `Capsule()` with its own `.nexusGlass` (NOT a `NexusButton` — its
    /// chrome differs from the Lab capsule and structural conformance is
    /// the bar). Tapping calls the EXISTING focus-mode action; no new
    /// behaviour is introduced.
    @ViewBuilder
    func embeddedFocusPill(_ task: TaskItem) -> some View {
        Button {
            embeddedEnterFocus(task)
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "play.fill")
                    .font(.system(size: 9))
                Text("Focus")
                    .font(NexusType.meta)
            }
            .foregroundStyle(NexusColor.Text.primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .nexusGlass(.regular, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    /// Routes to the EXISTING focus-mode entry: the same
    /// `FocusModeState.enter(taskID:)` that the ⌘. "Toggle Focus" menu
    /// command reaches via `NexusMacApp.resolveFocusCandidate` →
    /// `FocusModeState.toggle(pickFrom:)`, and the same state
    /// `ContentView.activeFocusState` observes to swap in `FocusView`.
    /// No new behaviour: if the host app did not inject a
    /// `FocusModeState` (`focusModeState == nil`, the documented default),
    /// this is a no-op exactly as the `FocusModeEnvironment` contract
    /// specifies — the embedded NowCard does not invent a focus action.
    @MainActor
    func embeddedEnterFocus(_ task: TaskItem) {
        focusModeState?.enter(taskID: task.id)
    }

    // MARK: - Section idiom (Lab `LabSection` equivalent, achromatic)

    /// Eyebrow + count header over its rows — the `Nexus*`/token equivalent of
    /// the Lab `LabSection`: `.nexusType(.eyebrow)` (size 10, semibold, traced,
    /// uppercased) + a `NexusCount` in the mono face, 7pt header HStack spacing,
    /// 10pt leading / 6pt bottom header padding, header→rows in one VStack.
    @ViewBuilder
    func embeddedSection<Rows: View>(
        eyebrow: String,
        count: Int,
        @ViewBuilder rows: () -> Rows
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                Text(eyebrow)
                    .nexusType(.eyebrow)
                    // Matches the Lab `LabSection` eyebrow tone (faint ink,
                    // 0x62636D). `NexusColor.Text.muted` is the exact token.
                    .foregroundStyle(NexusColor.Text.muted)
                NexusCount(value: count, font: NexusType.mono, color: NexusColor.Text.disabled)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 6)
            rows()
        }
    }

    /// A plain (non-`List`) column of MP-2.1 rows — matches the Lab oracle's
    /// `VStack`-of-rows. `.swipeActions` would no-op outside `List` anyway; the
    /// macOS embedded completion path is the row's own hover quick-actions
    /// cluster (✓ / ⏰), wired to the real repository below.
    @ViewBuilder
    func embeddedRows(_ tasks: [TaskItem]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(tasks.enumerated()), id: \.element.id) { index, task in
                embeddedRow(task: task, blockedCount: nil)
                    .nexusAppear(index)
            }
        }
    }

    @ViewBuilder
    func embeddedAwaitingRows(_ entries: [AwaitingEntry]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(entries.enumerated()), id: \.element.task.id) { index, entry in
                embeddedRow(task: entry.task, blockedCount: entry.blockedCount)
                    .nexusAppear(index)
            }
        }
    }

    /// The shipped MP-2.1 slice-1 row — `TaskRowView` (status glyph → title →
    /// meta → Mac hover ✓/⏰). Reused as-is (not rebuilt); its quick-action
    /// closures call the same repository idiom `TaskListView` uses.
    @ViewBuilder
    func embeddedRow(task: TaskItem, blockedCount: Int?) -> some View {
        TaskRowView(
            task: task,
            now: .now,
            blockedCount: blockedCount,
            showsDefaultTaskAssistMenu: false,
            onToggleDone: { embeddedToggleDone(task) },
            onSnooze: { embeddedSnoozeOneHour(task) }
        )
        .contentShape(Rectangle())
        .onTapGesture { onOpenTask?(task) }
    }

    // MARK: - Repository actions (mirror `TaskListView`; no new behaviour)

    /// Mirrors `TaskListView.toggleDone` (`TaskListView.swift:312-331`): on a
    /// `parentHasOpenSubtasks` throw for the tapped task, raise the cascade
    /// confirmation prompt; any other error sets the inline error surface.
    /// No silent swallow — the strict-completion throw happens BEFORE save,
    /// so swallowing it left the ✓ doing nothing with zero feedback.
    @MainActor
    func embeddedToggleDone(_ task: TaskItem) {
        guard let taskRepository else { return }
        do {
            if task.status == .done {
                try taskRepository.reopen(task)
            } else {
                try TaskCompletionAction.complete(task, repository: taskRepository)
            }
            embeddedError = nil
        } catch let error as TaskItemRepositoryError {
            if case .parentHasOpenSubtasks(let parentID, let openCount) = error, parentID == task.id {
                embeddedCascadePrompt = CascadeCompletionPrompt(task: task, openCount: openCount)
            } else {
                embeddedError = String(describing: error)
            }
        } catch {
            embeddedError = String(describing: error)
        }
    }

    /// Mirrors `TaskListView.confirmCascade` (`TaskListView.swift:333-342`):
    /// runs the cascade the user just approved; on failure surfaces the error.
    @MainActor
    func embeddedConfirmCascade(_ prompt: CascadeCompletionPrompt) {
        guard let taskRepository else { return }
        do {
            try TaskCompletionAction.cascadeComplete(prompt.task, repository: taskRepository)
            embeddedError = nil
        } catch {
            embeddedError = String(describing: error)
        }
    }

    /// Mirrors `TaskListView.snooze(_:by: .oneHour)` (`TaskListView.swift:367-387`):
    /// a snooze failure sets the inline error surface instead of being
    /// swallowed by a `try?`.
    @MainActor
    func embeddedSnoozeOneHour(_ task: TaskItem) {
        guard let taskRepository else { return }
        let until = Date.now.addingTimeInterval(60 * 60)
        do {
            try taskRepository.snooze(task, until: until)
            embeddedError = nil
        } catch {
            embeddedError = String(describing: error)
        }
    }
}

// MARK: - Section data loader

extension TodayDashboard {

    /// Buckets feeding the embedded-Today status sections, mapped 1:1 onto
    /// pre-existing `TodayQuery` facets — no new query or behaviour:
    ///   TODAY           → `TodayQuery.today` (today's open dated tasks)
    ///   AWAITING YOU    → `TodayQuery.awaiting` (open tasks blocking others)
    ///   LATER           → `TodayQuery.noDate` (open undated tasks, recessed)
    struct EmbeddedTodaySections {
        let today: [TaskItem]
        let awaiting: [AwaitingEntry]
        let later: [TaskItem]
    }

    @MainActor
    static func embeddedTodaySections(
        now: Date,
        modelContext: ModelContext
    ) throws -> EmbeddedTodaySections {
        let query = TodayQuery()
        let linkRepository = LinkRepository(context: modelContext)
        let archivedProjectIDs =
            (try? ProjectRepository(context: modelContext).archivedProjectIDs()) ?? []
        let today = try query.today(now: now, excludingProjectIDs: archivedProjectIDs)
            .apply(in: modelContext)
        let awaiting = try query.awaiting(
            now: now,
            modelContext: modelContext,
            linkRepository: linkRepository
        )
        let later = try query.noDate(excludingProjectIDs: archivedProjectIDs)
            .apply(in: modelContext)
        return EmbeddedTodaySections(today: today, awaiting: awaiting, later: later)
    }
}
