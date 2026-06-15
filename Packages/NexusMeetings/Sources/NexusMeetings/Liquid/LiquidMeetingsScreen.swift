import NexusCore
import NexusUI
import SwiftData
import SwiftUI

#if os(macOS)

/// Navigation seams the Meetings screen hands taps across module boundaries
/// with. All real destinations: tasks open the app's task detail, notes /
/// projects / people navigate to their existing shell destinations. The app
/// layer (ContentView+LiquidMeetings) supplies the closures.
public struct LiquidMeetingsNavigation {
    public let openTask: (TaskItem) -> Void
    public let openNotes: () -> Void
    public let openProject: (UUID) -> Void
    public let openPeople: () -> Void
    public let openSettings: () -> Void
    /// Cancel the helper's in-flight processing for a meeting. The host app
    /// backs this with the XPC helper control; `nil` (tests/previews, or no
    /// helper available) hides the in-app Cancel affordance entirely.
    public let cancelProcessing: ((UUID) -> Void)?

    public init(
        openTask: @escaping (TaskItem) -> Void,
        openNotes: @escaping () -> Void,
        openProject: @escaping (UUID) -> Void,
        openPeople: @escaping () -> Void,
        openSettings: @escaping () -> Void,
        cancelProcessing: ((UUID) -> Void)? = nil
    ) {
        self.openTask = openTask
        self.openNotes = openNotes
        self.openProject = openProject
        self.openPeople = openPeople
        self.openSettings = openSettings
        self.cancelProcessing = cancelProcessing
    }
}

/// Main-content width below which the Knowledge Column folds into the right
/// inspector. The reference wide layout needs the middle knowledge column to
/// survive the real shell/sidebar/inspector chrome, so the breakpoint leaves a
/// little less dead zone before collapsing.
private let knowledgeColumnBreakpoint: CGFloat = 920
/// Meeting list pane width (spec §Meeting list: 230–250 pt).
private let listPaneWidth: CGFloat = 240
/// Knowledge column width (spec §Layout: 280–300 pt).
private let knowledgeColumnWidth: CGFloat = 288

/// Liquid Meetings / Notes Intelligence main column (Task 10, spec
/// `docs/08_MODULE_MEETINGS_NOTES.md`): meeting list | meeting detail |
/// knowledge column. The matching right inspector
/// (`MeetingActionsInspector`) is mounted separately through the app shell's
/// inspector slot; both read the same shared `LiquidMeetingsModel`.
public struct LiquidMeetingsScreen: View {

    private let model: LiquidMeetingsModel
    private let composition: MeetingsComposition
    @ObservedObject private var router: MeetingNavigationRouter
    private let navigation: LiquidMeetingsNavigation

    public init(
        model: LiquidMeetingsModel,
        composition: MeetingsComposition,
        router: MeetingNavigationRouter,
        navigation: LiquidMeetingsNavigation
    ) {
        self.model = model
        self.composition = composition
        self.router = router
        self.navigation = navigation
    }

    public var body: some View {
        GeometryReader { proxy in
            content
                .onAppear { applyBreakpoint(width: proxy.size.width) }
                .onChange(of: proxy.size.width) { _, width in applyBreakpoint(width: width) }
        }
        .task { reloadSelectingDefault() }
        .task(id: router.selectedMeetingID) { reload() }
        .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { _ in
            reload()
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.meetings.isEmpty, model.searchQuery.trimmingCharacters(in: .whitespaces).isEmpty {
            emptyStore
        } else {
            HStack(alignment: .top, spacing: DS.Space.m) {
                MeetingListPane(
                    model: model,
                    selectedID: router.selectedMeetingID,
                    onSelect: { router.navigate(to: $0) },
                    onSearchChanged: { reload() }
                )
                .frame(width: listPaneWidth)

                detailColumn
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if !model.knowledgeCollapsed, router.selectedMeetingID != nil {
                    KnowledgeColumn(
                        model: model, composition: composition, router: router,
                        navigation: navigation
                    )
                    .frame(width: knowledgeColumnWidth)
                }
            }
            .padding(DS.Space.l)
        }
    }

    @ViewBuilder
    private var detailColumn: some View {
        if model.meeting != nil {
            MeetingDetailPane(model: model, composition: composition)
                // Load-bearing identity pin (same as the SummaryView /
                // TranscriptView pins inside the pane): without it SwiftUI
                // reuses the pane across selection changes and its local
                // @State (`tab`, `summaryExpanded`) leaks between meetings.
                .id(router.selectedMeetingID)
        } else {
            LiquidEmptyState(
                systemImage: "person.wave.2",
                message: "Select a meeting to see its summary, notes and transcript."
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// Calm empty store (spec §Rules: one CTA max). Meetings are recorded
    /// automatically when detection is enabled, so the single CTA points at
    /// the Settings destination where the meetings section lives — there is
    /// no deeper "open settings at section" seam to target.
    private var emptyStore: some View {
        LiquidEmptyState(
            systemImage: "person.wave.2",
            message: "No meetings yet — recording starts automatically once detection is set up."
        ) {
            LiquidPrimaryButton("Open Settings", action: navigation.openSettings)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func applyBreakpoint(width: CGFloat) {
        let collapsed = width < knowledgeColumnBreakpoint
        if model.knowledgeCollapsed != collapsed {
            model.knowledgeCollapsed = collapsed
        }
    }

    private func reload() {
        model.reload(composition: composition, selectedID: router.selectedMeetingID)
    }

    /// First load: when nothing is selected yet, select the newest meeting so
    /// the detail + inspector columns show real content immediately (spec
    /// §Meeting list shows an active meeting by default).
    private func reloadSelectingDefault() {
        reload()
        if router.selectedMeetingID == nil, let first = model.meetings.first {
            // No manual reload here: writing the selection re-fires the
            // `.task(id: router.selectedMeetingID)` handler, which performs
            // the single deferred reload for the new selection.
            router.selectedMeetingID = first.id
        }
    }
}
#endif
