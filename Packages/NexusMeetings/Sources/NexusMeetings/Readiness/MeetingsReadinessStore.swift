import Foundation
import NexusCore

public protocol MeetingsReadinessReading: Sendable {
    func read() -> MeetingsReadinessSnapshot?
}

public protocol MeetingsReadinessWriting: Sendable {
    func write(_ snapshot: MeetingsReadinessSnapshot)
}

public final class UserDefaultsMeetingsReadinessStore: MeetingsReadinessReading, MeetingsReadinessWriting, @unchecked Sendable {
    public static let shared = UserDefaultsMeetingsReadinessStore()

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .nexusGroup) {
        self.defaults = defaults
    }

    public func read() -> MeetingsReadinessSnapshot? {
        guard let data = defaults.data(forKey: MeetingsSettingsKeys.readinessSnapshot) else {
            return nil
        }
        return try? JSONDecoder().decode(MeetingsReadinessSnapshot.self, from: data)
    }

    public func write(_ snapshot: MeetingsReadinessSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: MeetingsSettingsKeys.readinessSnapshot)
    }
}
