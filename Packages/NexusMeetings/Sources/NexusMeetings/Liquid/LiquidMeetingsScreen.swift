import NexusCore
import NexusUI
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
    /// Published to the shell whenever the selected meeting changes: the
    /// selected id + title, or `(nil, nil)` at the list root. The shell maps
    /// this to the toolbar breadcrumb crumb. The crumb is DERIVED from
    /// selection here (inside the screen, the only place the router is
    /// observed) — the shell can't see `selectedMeetingID` (env-injected, not
    /// observed), hence this callback seam.
    public let onDetailChange: (UUID?, String?) -> Void

    public init(
        openTask: @escaping (TaskItem) -> Void,
        openNotes: @escaping () -> Void,
        openProject: @escaping (UUID) -> Void,
        openPeople: @escaping () -> Void,
        openSettings: @escaping () -> Void,
        cancelProcessing: ((UUID) -> Void)? = nil,
        onDetailChange: @escaping (UUID?, String?) -> Void = { _, _ in }
    ) {
        self.openTask = openTask
        self.openNotes = openNotes
        self.openProject = openProject
        self.openPeople = openPeople
        self.openSettings = openSettings
        self.cancelProcessing = cancelProcessing
        self.onDetailChange = onDetailChange
    }
}

/// Meeting list pane width (spec §Meeting list: 230–250 pt).
private let listPaneWidth: CGFloat = 240

/// Liquid Meetings / Notes Intelligence main column (Task 10, spec
/// `docs/08_MODULE_MEETINGS_NOTES.md`): meeting list | meeting detail.
/// The matching right inspector (`MeetingActionsInspector`) is mounted
/// separately through the app shell's inspector slot; both read the same
/// shared `LiquidMeetingsModel`. Knowledge sections (linked items, related
/// notes, backlinks) now live exclusively in the inspector.
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
        content
            .task { reloadSelectingDefault() }
            .task(id: router.selectedMeetingID) { reload() }
            // Publish the leaf breadcrumb to the shell whenever the selection
            // changes. DERIVED from `router.selectedMeetingID` (this is the one
            // place the router is `@ObservedObject`); the title comes from the
            // already-loaded `model.meetings`. If the title isn't loaded yet at
            // `initial` (e.g. a deep-link before the list loads), a follow-up
            // reload re-fires this onChange with the resolved title.
            .onChange(of: router.selectedMeetingID, initial: true) { _, id in
                navigation.onDetailChange(
                    id, id.flatMap { mid in model.meetings.first { $0.id == mid }?.title })
            }
            // Coalesce local saves AND cross-process / CloudKit imports into one
            // debounced reload. The MeetingsHelper records into a SEPARATE persistent
            // container, so its writes never post this process's
            // `ModelContext.didSave`; the only cross-process signal is the store-level
            // `NSPersistentStoreRemoteChange` (also how CloudKit imports arrive) —
            // `reloadOnStoreChange` observes both and hops to the main actor before
            // calling `action`, so the Cancel card / processing state refreshes
            // instead of going stale, without a reload storm during bulk writes.
            .reloadOnStoreChange { reload() }
    }

    @ViewBuilder
    private var content: some View {
        if model.meetings.isEmpty, model.searchQuery.trimmingCharacters(in: .whitespaces).isEmpty {
            emptyStore
        } else {
            HStack(alignment: .top, spacing: DS.Space.m) {
                MeetingListPane(
                    model: model,
                    composition: composition,
                    selectedID: router.selectedMeetingID,
                    onSelect: { router.navigate(to: $0) },
                    onSearchChanged: { reload() },
                    onTogglePin: { model.togglePin($0, composition: composition) },
                    onCopySummary: { meeting in
                        let body = model.summaryMarkdownBody(for: meeting)
                        let markdown = MarkdownExport.entity(
                            title: meeting.title,
                            body: body,
                            metadata: [LiquidMeetingsFormat.fullDate.string(from: meeting.startedAt)]
                        )
                        PasteboardCopy.string(markdown)
                    },
                    onRerunSummary: { meeting in
                        guard !meeting.transcriptText.isEmpty else { return }
                        // Re-run summary through the pipeline's summary+actions stages.
                        // `processSummaryAndActions` needs an audio folder — the pipeline
                        // uses the folder for screen-OCR context only; an empty temp dir
                        // is sufficient when no new OCR file is present.
                        Task {
                            let tempFolder = FileManager.default.temporaryDirectory
                                .appendingPathComponent("rerun-\(meeting.id.uuidString)", isDirectory: true)
                            try? FileManager.default.createDirectory(at: tempFolder, withIntermediateDirectories: true)
                            try? await composition.pipeline.processSummaryAndActions(
                                meeting: meeting, audioFolder: tempFolder)
                        }
                    },
                    onDelete: { meeting in
                        model.deleteMeeting(meeting, composition: composition)
                        if router.selectedMeetingID == meeting.id {
                            router.selectedMeetingID = model.meetings.first { $0.id != meeting.id }?.id
                        }
                        reload()
                    }
                )
                .frame(width: listPaneWidth)

                detailColumn
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
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
