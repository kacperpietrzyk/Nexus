import Foundation
import InboxShell
import NexusAI
import NexusAgentTools
import NexusCore
import NexusSync
import SwiftData

@MainActor
public final class MeetingsComposition {
    public static let extraModels: [any PersistentModel.Type] = [Meeting.self]
    public static let localOnlyExtraModels: [any PersistentModel.Type] = [MeetingAudioStorage.self]

    /// Stable source identifier for meeting-extracted action items. Persisted on
    /// `TaskItem.externalSourceID` for idempotent re-extraction, so the value
    /// must stay byte-identical (`"meetings.action-items"`) — it outlived the
    /// deleted `MeetingActionItemsInboxSource` that originally owned it.
    public static let actionItemSourceID = "meetings.action-items"

    /// V11 -> V12 People backfill (spec §8 / M1): seeds `Person` records and
    /// `.attendee` edges from existing meetings' `participantsJSON`. Wires the
    /// concrete `Meeting` type into the generic, marker-gated backfill in
    /// NexusSync (which can't import `Meeting`). Call ONCE per launch from the
    /// full apps (iOS/Mac) right after `NexusModelContainer.make`, NOT in
    /// extensions. Idempotent and best-effort: a throw leaves the marker unset so
    /// it retries next launch.
    public static func backfillPeopleIfNeeded(container: ModelContainer) throws {
        try NexusModelContainer.backfillPeopleFromMeetingsIfNeeded(
            meetingType: Meeting.self,
            participantsKeyPath: \Meeting.participantsJSON,
            idKeyPath: \Meeting.id,
            container: container
        )
    }

    public let meetingRepository: MeetingRepository
    public let audioStorageRepository: MeetingAudioStorageRepository
    public let recorder: MeetingRecorder
    public let detector: MeetingDetector
    public let pipeline: MeetingProcessingPipeline
    public let pipelineQueue: PipelineQueue

    private let taskRepository: TaskItemRepository
    public let linkRepository: LinkRepository
    private let calendarProvider: any CalendarEventProviding

    public var taskItemRepository: TaskItemRepository { taskRepository }

    /// Wires named speakers to `Person` records (`.attendee` edges), graph-only.
    /// Built here because the People schema rides the base container, so the
    /// `PersonRepository` is always available. Inject into the transcript
    /// labeling surface so a rename surfaces a `Person` (idempotent, never an
    /// assignee — invariant I1). Calendar enrichment reuses the same provider
    /// already wired for detection.
    public let peopleLinker: MeetingPeopleLinker

    /// The shared `PersonRepository` (NexusCore), exposed so the transcript rename
    /// sheet can list existing contacts to assign a speaker to (#3). Graph-only — the
    /// Meetings surface never imports a People UI module.
    public let personRepository: PersonRepository

    public init(
        context: ModelContext,
        router: any MeetingProcessingRouting,
        rootAudioFolder: URL,
        calendarProvider: any CalendarEventProviding,
        dateExtractor: (any DateExtracting)? = nil,
        taskRepository: TaskItemRepository? = nil,
        workspaceProvider: any WindowTitleWorkspaceProviding = EmptyWindowTitleWorkspaceProvider(),
        recorder: MeetingRecorder? = nil,
        appPatternRegistry: AppPatternRegistry = UserDefaultsAppPatternRegistryStore.shared.load(),
        appPatternRegistryProvider: AppPatternRegistryProvider? = nil,
        appCaptureFactory: @escaping (AudioFileWriter) -> any MeetingAppAudioCapturing = {
            AppAudioCapture(writer: $0, tap: NoopAppAudioTap())
        }
    ) throws {
        try FileManager.default.createDirectory(
            at: rootAudioFolder,
            withIntermediateDirectories: true
        )

        self.calendarProvider = calendarProvider
        meetingRepository = MeetingRepository(context: context)
        audioStorageRepository = MeetingAudioStorageRepository(context: context)
        personRepository = PersonRepository(context: context)
        peopleLinker = Self.makePeopleLinker(context: context, calendarProvider: calendarProvider)
        self.taskRepository =
            taskRepository
            ?? TaskItemRepository(
                context: context,
                scheduler: RRuleScheduler(),
                now: Date.init
            )
        linkRepository = LinkRepository(context: context)

        let primaryProvider = ParakeetTDTProvider()
        let fallbackProvider = WhisperKitMeetingProvider()
        let transcriptionStage = TranscriptionStage(
            primary: primaryProvider,
            fallback: fallbackProvider
        )

        pipelineQueue = PipelineQueue()
        pipeline = MeetingProcessingPipeline(
            repo: meetingRepository,
            vad: VADTrimStage(),
            transcription: transcriptionStage,
            diarization: DiarizationStage(),
            merge: MergeStage(),
            summary: SummaryStage(router: router),
            actionItems: ActionItemsStage(
                router: router,
                taskRepository: self.taskRepository,
                meetingRepository: meetingRepository,
                linkRepository: linkRepository,
                sourceID: MeetingsComposition.actionItemSourceID,
                dateExtractor: dateExtractor
            ),
            providerProfile: {
                "\(primaryProvider.identifier)+sortformer"
            }
        )

        self.recorder =
            recorder
            ?? MeetingRecorder(
                appCaptureFactory: appCaptureFactory,
                rootFolder: rootAudioFolder
            )

        detector = Self.makeDetector(
            calendarProvider: calendarProvider,
            workspaceProvider: workspaceProvider,
            appPatternRegistry: appPatternRegistry,
            appPatternRegistryProvider: appPatternRegistryProvider
        )
    }

    /// Calendar-attendee display names for a meeting, used to *seed* the speaker
    /// labeling UI (spec §5 / I3): suggestions only, never auto-assigned. Returns
    /// `[]` when the meeting has no linked calendar event or the lookup fails
    /// (best-effort, like the detection correlator). Matches the event by id over
    /// a padded window since `CalendarEventProviding` has no fetch-by-id.
    public func calendarAttendeeNames(for meeting: Meeting) async -> [String] {
        guard let eventID = meeting.calendarEventID else { return [] }
        let pad: TimeInterval = 15 * 60
        let end = meeting.endedAt ?? meeting.startedAt.addingTimeInterval(TimeInterval(meeting.durationSec))
        let lower = meeting.startedAt.addingTimeInterval(-pad)
        let upper = max(end, meeting.startedAt).addingTimeInterval(pad)
        do {
            let events = try await calendarProvider.eventsBetween(start: lower, end: upper)
            let attendees = events.first { $0.id == eventID }?.attendees ?? []
            var seen = Set<String>()
            var names: [String] = []
            for attendee in attendees {
                guard let name = attendee.name?.trimmingCharacters(in: .whitespacesAndNewlines),
                    name.isEmpty == false,
                    seen.insert(name.lowercased()).inserted
                else { continue }
                names.append(name)
            }
            return names
        } catch {
            return []
        }
    }

    /// Richer calendar-attendee suggestions for the speaker rename sheet (#4b):
    /// name + email + response/role, ranked for usefulness. Like
    /// `calendarAttendeeNames`, best-effort and suggestion-only (I3) — picking one is
    /// the user's manual choice and nothing here writes `participantsJSON`. Returns
    /// `[]` when the meeting has no linked calendar event or the lookup fails.
    public func calendarAttendeeCandidates(for meeting: Meeting) async -> [MeetingAttendeeCandidate] {
        guard let eventID = meeting.calendarEventID else { return [] }
        let pad: TimeInterval = 15 * 60
        let end = meeting.endedAt ?? meeting.startedAt.addingTimeInterval(TimeInterval(meeting.durationSec))
        let lower = meeting.startedAt.addingTimeInterval(-pad)
        let upper = max(end, meeting.startedAt).addingTimeInterval(pad)
        do {
            let events = try await calendarProvider.eventsBetween(start: lower, end: upper)
            let attendees = events.first { $0.id == eventID }?.attendees ?? []
            return Self.rankAttendeeCandidates(attendees)
        } catch {
            return []
        }
    }

    /// Pure ranking used by `calendarAttendeeCandidates` (testable in isolation):
    /// drops the current user ("Me") and unnamed attendees, de-duplicates by email
    /// (else name), then orders accepted/required participants ahead of tentative and
    /// declined ones (a declined invitee is the least likely speaker).
    nonisolated static func rankAttendeeCandidates(
        _ attendees: [CalendarEvent.Attendee]
    ) -> [MeetingAttendeeCandidate] {
        var seen = Set<String>()
        var candidates: [MeetingAttendeeCandidate] = []
        for attendee in attendees {
            guard attendee.isCurrentUser == false else { continue }
            let name = attendee.name?.trimmingCharacters(in: .whitespacesAndNewlines)
            let email = attendee.email?.trimmingCharacters(in: .whitespacesAndNewlines)
            let nonEmptyName = (name?.isEmpty == false) ? name : nil
            let nonEmptyEmail = (email?.isEmpty == false) ? email : nil
            // A candidate must be human-readable: prefer a real name, else fall back to
            // the email so an email-only attendee is still pickable.
            guard let label = nonEmptyName ?? nonEmptyEmail else { continue }
            let dedupeKey = (nonEmptyEmail ?? label).lowercased()
            guard seen.insert(dedupeKey).inserted else { continue }
            candidates.append(
                MeetingAttendeeCandidate(
                    name: label,
                    email: nonEmptyEmail,
                    responseStatus: attendee.responseStatus,
                    role: attendee.role
                )
            )
        }
        // Stable sort: lower rank first; equal-rank attendees keep invite order.
        return candidates.enumerated()
            .sorted { lhs, rhs in
                let lr = Self.rank(lhs.element)
                let rr = Self.rank(rhs.element)
                return lr == rr ? lhs.offset < rhs.offset : lr < rr
            }
            .map(\.element)
    }

    /// Lower is shown first. Declined invitees sink to the bottom (unlikely speakers);
    /// tentative sits just above; everything else (accepted / pending / unknown) leads.
    nonisolated private static func rank(_ candidate: MeetingAttendeeCandidate) -> Int {
        switch candidate.responseStatus {
        case .declined: return 2
        case .tentative: return 1
        case .accepted, .pending, .none: return 0
        }
    }

    public func agentTools() -> [any AgentTool] {
        MeetingsAgentTools.tools(
            meetingRepository: meetingRepository,
            taskRepository: self.taskRepository,
            linkRepository: linkRepository
        )
    }

    /// Registers the meeting activity-feed projector into the shared
    /// `FeedRegistry`. Each meeting that produced a summary and/or extracted
    /// action items becomes one `.meeting`-stream feed row; the snapshot is
    /// built on `@MainActor` by `MeetingFeedSnapshotBuilder` (the queries lifted
    /// from the deleted `MeetingActionItemsInboxSource`).
    public func registerInboxSource(in registry: FeedRegistry = .shared) {
        // Capture the Sendable container (not the non-Sendable repositories) so
        // the `@Sendable` snapshot closure is legal under strict concurrency;
        // rebuild the repositories on the MainActor hop where fetches run.
        let container = meetingRepository.context.container
        Task {
            await registry.register(
                MeetingFeedProjector(snapshotProvider: {
                    try await MainActor.run {
                        try MeetingFeedSnapshotBuilder(context: container.mainContext).snapshots()
                    }
                })
            )
        }
    }

    private static func makePeopleLinker(
        context: ModelContext,
        calendarProvider: any CalendarEventProviding
    ) -> MeetingPeopleLinker {
        MeetingPeopleLinker(
            people: PersonRepository(context: context),
            calendarProvider: calendarProvider
        )
    }

    private static func makeDetector(
        calendarProvider: any CalendarEventProviding,
        workspaceProvider: any WindowTitleWorkspaceProviding,
        appPatternRegistry: AppPatternRegistry,
        appPatternRegistryProvider: AppPatternRegistryProvider?
    ) -> MeetingDetector {
        let poller = WindowTitlePoller(
            registry: appPatternRegistry,
            workspace: workspaceProvider,
            registryProvider: appPatternRegistryProvider
        )
        return MeetingDetector(
            poller: poller,
            debouncer: DetectionDebouncer(),
            correlator: CalendarCorrelator(provider: calendarProvider),
            registry: appPatternRegistry,
            registryProvider: appPatternRegistryProvider
        )
    }
}

public struct EmptyWindowTitleWorkspaceProvider: WindowTitleWorkspaceProviding {
    public init() {}
    public func currentSnapshots(trackedBundleIDs: Set<String>) -> [RunningAppSnapshot] { [] }
}
