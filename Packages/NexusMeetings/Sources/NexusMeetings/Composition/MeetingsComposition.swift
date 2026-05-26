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

    public var taskItemRepository: TaskItemRepository { taskRepository }

    public init(
        context: ModelContext,
        router: any MeetingProcessingRouting,
        rootAudioFolder: URL,
        calendarProvider: any CalendarEventProviding,
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

        meetingRepository = MeetingRepository(context: context)
        audioStorageRepository = MeetingAudioStorageRepository(context: context)
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
                sourceID: MeetingActionItemsInboxSource.identifier
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
