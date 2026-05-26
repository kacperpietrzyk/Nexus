import Combine
import NexusCore
import NexusSync
import SwiftData
import SwiftUI
import UserNotifications
import WatchKit
import WidgetKit

@main
struct NexusWatchApp: App {
    private let container: ModelContainer
    /// Strong ref — UNUserNotificationCenter does NOT retain its delegate.
    private let actionHandler: WatchNotificationActionHandler
    private let digestScheduler: WatchOverdueDigestScheduler
    private let guardObj: WatchNotificationGuard

    @State private var didSaveObserver: AnyCancellable?
    @State private var snapshotObserver: AnyCancellable?
    @Environment(\.scenePhase) private var scenePhase

    init() {
        UserDefaultsQuietHoursStore.migrateFromStandardIfNeeded()
        do {
            self.container = try NexusModelContainer.make(
                groupContainerIdentifier: "group.com.kacperpietrzyk.Nexus"
            )
        } catch {
            fatalError("Failed to install NexusModelContainer on Watch: \(error)")
        }
        guard let store = WatchNotificationSnapshotStore() else {
            fatalError("App Group container missing — check NexusWatch.entitlements")
        }
        let delivery = SystemNotificationCenter()
        let watchScheduler = WatchNotificationScheduler(delivery: delivery)
        let quietStore = UserDefaultsQuietHoursStore()
        self.actionHandler = WatchNotificationActionHandler(
            context: container.mainContext,
            bridge: WatchPhoneBridge.shared,
            scheduler: watchScheduler,
            quietHoursStore: quietStore,
            now: { Date() }
        )
        self.digestScheduler = WatchOverdueDigestScheduler(
            context: container.mainContext,
            delivery: delivery,
            presenceProbe: WatchPhoneBridge.shared
        )
        self.guardObj = WatchNotificationGuard(
            snapshotStore: store,
            scheduler: watchScheduler,
            probe: WatchPhoneBridge.shared,
            quietHoursStore: quietStore
        )
        UNUserNotificationCenter.current().delegate = actionHandler
    }

    var body: some Scene {
        WindowGroup {
            WatchRootView(actionHandler: actionHandler)
                .task {
                    await NotificationCategories.registerWatchAll(on: SystemNotificationCenter())
                    _ = try? await UNUserNotificationCenter.current()
                        .requestAuthorization(options: [.alert, .sound, .badge])
                    await digestScheduler.refreshAndSchedule()
                    await guardObj.evaluate()
                    guardObj.startTimer()

                    if didSaveObserver == nil {
                        didSaveObserver = NotificationCenter.default
                            .publisher(for: ModelContext.didSave)
                            .sink { _ in WidgetCenter.shared.reloadAllTimelines() }
                    }

                    if snapshotObserver == nil {
                        snapshotObserver = NotificationCenter.default
                            .publisher(for: .watchNotifSnapshotUpdated)
                            .sink { _ in
                                _Concurrency.Task { @MainActor in
                                    await guardObj.evaluate()
                                    await digestScheduler.refreshAndSchedule()
                                }
                            }
                    }
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        _Concurrency.Task { @MainActor in
                            await guardObj.evaluate()
                            await digestScheduler.refreshAndSchedule()
                        }
                    }
                }
        }
        .modelContainer(container)

        WKNotificationScene(
            controller: WatchNotificationController.self,
            category: NotificationCategory.taskReminder.rawValue
        )
    }
}
