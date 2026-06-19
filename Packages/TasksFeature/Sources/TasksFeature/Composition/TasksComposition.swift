import CommandPaletteShell
import Foundation
import InboxShell
import NexusAI
import NexusCore
import OSLog
import SwiftData

/// Factory for the production `CompositeNLParser` cascade. Apps call this from
/// their composition roots so `NexusMacApp.swift` and `NexusiOSApp.swift` stay
/// symmetrical and independent of the cascade's internal types.
public enum TasksComposition {

    /// Builds the standard cascade: `HandcodedParser` primary, `FoundationModelParser`
    /// augmenting on a low-confidence + no-date + no-recurrence handcoded result.
    /// `connectivity` defaults to `.offlineOnly` because the FM path is meant to
    /// stay on-device through `AppleIntelligenceProvider` in the happy path.
    public static func makeParser(
        router: AIRouter,
        connectivity: ConnectivityPreference = .offlineOnly
    ) -> CompositeNLParser {
        CompositeNLParser(
            handcoded: HandcodedParser(),
            foundationModel: FoundationModelParser(
                router: router,
                connectivity: connectivity
            )
        )
    }

    /// Builds the production `TaskItemRepository` for an app's main `ModelContext`.
    /// Apps call this once from the composition root and inject the resulting
    /// instance into the environment so views share a single repository identity.
    @MainActor
    public static func makeRepository(for context: ModelContext) -> TaskItemRepository {
        TaskItemRepository(
            context: context,
            scheduler: RRuleScheduler(),
            now: { .now },
            activity: ActivityRecorder(context: context)
        )
    }

    /// Overload that wires a `NotificationScheduling` impl into the repository.
    /// Apps use this in production so task mutations dispatch to
    /// `NotificationScheduler` via `NotificationSchedulingAdapter`. Kept as a
    /// distinct overload (rather than a defaulted parameter on the existing
    /// 1-arg form) so existing call sites that don't pass `notifications` stay
    /// unambiguous.
    ///
    /// When `snapshotPusher` is provided, the repository's post-write hook
    /// encodes a fresh `NotificationSnapshot` from `context` via
    /// `NotificationSnapshotEncoder` and forwards it to `pusher.push(_:)`.
    /// When `nil` (the Mac default), the no-op closure is wired so the
    /// repository skips snapshot work entirely.
    @MainActor
    public static func makeRepository(
        for context: ModelContext,
        notifications: any NotificationScheduling,
        snapshotPusher: (any WatchSnapshotPushing)? = nil
    ) -> TaskItemRepository {
        let encoder = NotificationSnapshotEncoder(context: context)
        let closure: WatchSnapshotPusher = {
            guard let snapshotPusher else { return }
            await snapshotPusher.push(encoder.encodeNow())
        }
        return TaskItemRepository(
            context: context,
            scheduler: RRuleScheduler(),
            now: { .now },
            notifications: notifications,
            activity: ActivityRecorder(context: context),
            snapshotPusher: snapshotPusher == nil ? noopWatchSnapshotPusher : closure
        )
    }

    /// Builds a production `NotificationScheduler` wired to
    /// `SystemNotificationCenter` and the `UserDefaults`-backed quiet-hours
    /// store. Apps call this once from their composition root and pass the
    /// result both into the repository (via `NotificationSchedulingAdapter`)
    /// and into the SwiftUI environment via `\.notificationScheduler`.
    @MainActor
    public static func makeNotificationScheduler(
        delivery: any NotificationDelivering = SystemNotificationCenter(),
        quietHoursStore: UserDefaultsQuietHoursStore = UserDefaultsQuietHoursStore(),
        calendar: Calendar = .current
    ) -> NotificationScheduler {
        NotificationScheduler(
            delivery: delivery,
            quietHours: { quietHoursStore.load() },
            calendar: calendar
        )
    }

    /// Builds the production `OverdueDigestScheduler` wired to
    /// `SystemNotificationCenter`. Apps call this once at launch (in the same
    /// permission-gated `.task` as `makeNotificationScheduler`) and call
    /// `registerDailyDigest()` so the daily 9:00 overdue-digest notification
    /// arms. The scheduler is an `actor`, so this factory needs no isolation.
    public static func makeOverdueDigestScheduler(
        delivery: any NotificationDelivering = SystemNotificationCenter()
    ) -> OverdueDigestScheduler {
        OverdueDigestScheduler(delivery: delivery)
    }

    /// Registers the Tasks feed projector and command palette actions into the
    /// shared cross-module registries. Apps call this once from their
    /// composition root so the `InboxShell` activity feed and the
    /// `CommandPaletteShell` UI get populated without any direct cross-module
    /// imports. The `UnscheduledBridgeProjector` emits a single bridge card
    /// linking to the unscheduled-tasks triage view; its count comes from the
    /// cheap `TasksNoDateInboxCount` fetchCount (no materialization).
    @MainActor
    public static func bootstrap(
        repository: TaskItemRepository,
        feedRegistry: FeedRegistry = .shared,
        commandRegistry: CommandRegistry = .shared,
        navigation: TaskCommandNavigation
    ) async {
        // Capture the Sendable `ModelContainer` (not the non-Sendable
        // `ModelContext`) so the `@Sendable` count closure stays legal under
        // Swift 6 strict concurrency, then resolve the main context inside the
        // MainActor hop where SwiftData fetches must run.
        let container = repository.context.container
        await feedRegistry.register(
            UnscheduledBridgeProjector(countProvider: {
                await MainActor.run {
                    (try? TasksNoDateInboxCount(context: container.mainContext).count()) ?? 0
                }
            })
        )

        await commandRegistry.register(AddTaskCommand(openCapture: navigation.openCapture))
        await commandRegistry.register(GoToInboxCommand(action: navigation.goToInbox))
        await commandRegistry.register(GoToTodayCommand(action: navigation.goToToday))
        await commandRegistry.register(
            MarkSelectedDoneCommand(repository: repository, selectedTask: navigation.selectedTask)
        )
        await commandRegistry.register(
            SnoozeSelectedCommand(repository: repository, selectedTask: navigation.selectedTask)
        )
        await commandRegistry.register(
            ToggleFocusCommand(repository: repository, selectedTask: navigation.selectedTask)
        )
    }
}

/// Adapter exposing TasksFeature's `NotificationScheduler` (an `@MainActor`
/// `final class`) as a NexusCore `NotificationScheduling` impl. The protocol
/// is `@MainActor`-annotated, and `NotificationScheduler` already runs on
/// MainActor, so the wrapping is a thin pass-through with OSLog error logging.
@MainActor
public struct NotificationSchedulingAdapter: NotificationScheduling {
    private static let logger = Logger(
        subsystem: "com.kacperpietrzyk.Nexus",
        category: "NotificationSchedulingAdapter"
    )

    private let scheduler: NotificationScheduler

    public init(scheduler: NotificationScheduler) {
        self.scheduler = scheduler
    }

    public func schedule(_ task: TaskItem) async throws {
        do {
            try await scheduler.schedule(task)
        } catch {
            Self.logger.error(
                "schedule failed for taskID \(task.id, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
            throw error
        }
    }

    public func cancel(taskID: UUID) async {
        await scheduler.cancel(taskID: taskID)
    }

    public func reschedule(_ task: TaskItem) async throws {
        do {
            try await scheduler.reschedule(task)
        } catch {
            Self.logger.error(
                "reschedule failed for taskID \(task.id, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
            throw error
        }
    }

    public func scheduleSnooze(_ task: TaskItem, until: Date) async throws {
        do {
            try await scheduler.scheduleSnooze(task, until: until)
        } catch {
            Self.logger.error(
                "scheduleSnooze failed for taskID \(task.id, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
            throw error
        }
    }
}
