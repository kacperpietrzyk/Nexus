import Foundation
import NexusCore
import Observation

#if !os(watchOS)

/// Write-through view state for `GoalsPreferences` (T5). Mirrors the
/// `QuietHoursViewState` pattern (persist on every mutation via `didSet`,
/// no batching); an unset store loads the spec defaults (5/25).
@MainActor
@Observable
public final class GoalsSettingsState {
    private let store: UserDefaultsGoalsPreferencesStore

    public var dailyTarget: Int {
        didSet { persist() }
    }
    public var weeklyTarget: Int {
        didSet { persist() }
    }

    public init(store: UserDefaultsGoalsPreferencesStore = UserDefaultsGoalsPreferencesStore()) {
        self.store = store
        let loaded = store.load()
        self.dailyTarget = loaded.dailyCompletionTarget
        self.weeklyTarget = loaded.weeklyCompletionTarget
    }

    private func persist() {
        store.save(
            GoalsPreferences(
                dailyCompletionTarget: dailyTarget,
                weeklyCompletionTarget: weeklyTarget
            )
        )
    }
}

#endif
