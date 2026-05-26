import Foundation
import NexusCore
import Observation

#if canImport(EventKit) && !os(watchOS)
import EventKit
#endif

@MainActor
@Observable
public final class CalendarPermissionState {
    public private(set) var status: CalendarAuthorizationStatus

    private let provider: any CalendarEventProviding
    @ObservationIgnored
    nonisolated(unsafe) private var changeObserverToken: NSObjectProtocol?

    public convenience init() {
        self.init(provider: CalendarPermissionState.defaultProvider())
    }

    public init(provider: any CalendarEventProviding) {
        self.provider = provider
        self.status = provider.authorizationStatus()
        startObservingExternalChanges()
    }

    public func refresh() {
        status = provider.authorizationStatus()
    }

    public func requestAccess() async {
        do {
            status = try await provider.requestAccess()
        } catch {
            status = .denied
        }
    }

    private func startObservingExternalChanges() {
        #if canImport(EventKit) && !os(watchOS)
        // EKEventStore broadcasts on any database change AND on authorization changes (e.g. user
        // toggling access in System Settings while the app is foregrounded). Hop back to the main
        // actor to mutate `status`.
        changeObserverToken = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refresh()
            }
        }
        #endif
    }

    deinit {
        #if canImport(EventKit) && !os(watchOS)
        if let token = changeObserverToken {
            NotificationCenter.default.removeObserver(token)
        }
        #endif
    }

    private static func defaultProvider() -> any CalendarEventProviding {
        #if canImport(EventKit) && !os(watchOS)
        EventKitCalendarProvider.shared
        #else
        MockCalendarEventProvider(status: .denied)
        #endif
    }
}
