import Foundation
import NexusUI

public struct VacationModeGate: @unchecked Sendable {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func shouldFire(scheduleID _: UUID) -> Bool {
        let agentEnabled =
            defaults.object(forKey: NexusPreferences.Keys.agentEnabled) as? Bool
            ?? true
        return agentEnabled && !defaults.bool(forKey: NexusPreferences.Keys.agentVacationMode)
    }
}
