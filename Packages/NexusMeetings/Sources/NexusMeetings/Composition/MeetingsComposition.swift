import Foundation
import InboxShell
import NexusAI
import NexusAgentTools
import NexusCore
import SwiftData

@MainActor
public final class MeetingsComposition {
    public static let extraModels: [any PersistentModel.Type] = [Meeting.self]
    public static let localOnlyExtraModels: [any PersistentModel.Type] = [MeetingAudioStorage.self]

    public let meetingRepository: MeetingRepository
    public let audioStorageRepository: MeetingAudioStorageRepository
    public let inboxSource: MeetingActionItemsInboxSource
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
        peopleLinker = Self.makePeopleLinker(context: context, calendarProvider: calendarProvider)
        self.taskRepository =
            taskRepository
            ?? TaskItemRepository(
                context: context,
                scheduler: RRuleScheduler(),
                now: Date.init
            )
        linkRepository = LinkRepository(context: context)
        inboxSource = MeetingActionItemsInboxSource(
            meetingRepository: meetingRepository,
            taskRepository: self.taskRepository,
            linkRepository: linkRepository
        )

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
                sourceID: MeetingActionItemsInboxSource.identifier,
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

    public func agentTools() -> [any AgentTool] {
        MeetingsAgentTools.tools(
            meetingRepository: meetingRepository,
            taskRepository: self.taskRepository,
            linkRepository: linkRepository
        )
    }

    public func registerInboxSource(in registry: InboxSourceRegistry = .shared) {
        let source = inboxSource
        Task {
            await registry.register(source)
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
