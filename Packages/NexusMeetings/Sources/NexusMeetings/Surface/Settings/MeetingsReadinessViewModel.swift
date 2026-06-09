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

    public func refresh() {
        sections = mapper.sections(from: reader.read(), now: now())
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
