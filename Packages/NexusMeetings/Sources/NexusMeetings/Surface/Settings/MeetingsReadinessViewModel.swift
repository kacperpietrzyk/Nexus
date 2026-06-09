import Foundation

@MainActor
@Observable
public final class MeetingsReadinessViewModel {
    public private(set) var sections: [ReadinessSection] = []

    private let reader: any MeetingsReadinessReading
    private let mapper: ReadinessRowMapper
    private let now: () -> Date
    private let post: (Notification.Name) -> Void

    public init(
        reader: any MeetingsReadinessReading = UserDefaultsMeetingsReadinessStore.shared,
        mapper: ReadinessRowMapper = ReadinessRowMapper(),
        now: @escaping () -> Date = { Date() },
        post: @escaping (Notification.Name) -> Void = { name in
            DistributedNotificationCenter.default().postNotificationName(
                name, object: nil, userInfo: nil, deliverImmediately: true
            )
        }
    ) {
        self.reader = reader
        self.mapper = mapper
        self.now = now
        self.post = post
    }

    /// Reads the latest snapshot from the shared store and re-renders. Pure
    /// read — does NOT ping the helper (so it is safe to call from the
    /// `readinessDidChange` observer without creating a feedback loop).
    public func refresh() {
        sections = mapper.sections(from: reader.read(), now: now())
    }

    /// Asks the helper to recompute and write a fresh snapshot (e.g. when the
    /// panel appears, in case permissions changed while it was closed).
    public func requestHelperRefresh() {
        post(MeetingsReadinessNotification.refreshReadiness)
    }

    public func perform(_ action: ReadinessRowAction) {
        switch action {
        case .requestMicrophone, .openAccessibilitySettings:
            post(MeetingsReadinessNotification.requestPermissions)
        case .downloadModel, .downloadAllModels:
            post(MeetingsReadinessNotification.downloadModels)
        case .startHelper, .enableAutoRecord:
            post(MeetingsReadinessNotification.refreshReadiness)
        case .info:
            break
        }
    }
}
