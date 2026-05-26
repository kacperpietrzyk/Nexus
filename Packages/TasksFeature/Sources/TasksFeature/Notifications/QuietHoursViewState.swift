import Foundation
import NexusCore
import Observation

/// Bridges the `(hour, minute)` shape stored in `UserDefaultsQuietHoursStore`
/// to the `Date`-typed bindings consumed by `NexusSettingsView`'s two
/// `DatePicker(displayedComponents: .hourAndMinute)` controls.
///
/// SwiftUI `DatePicker` requires a `Binding<Date>`, but the on-disk format is
/// just a wall-clock window, so we round-trip through dates rooted in today's
/// `startOfDay`. Persistence happens on every mutation via `didSet`, matching
/// the existing `UserDefaultsConsentStore` pattern in NexusAI (write-through,
/// no batching).
@MainActor
@Observable
public final class QuietHoursViewState {
    private let store: UserDefaultsQuietHoursStore
    private let calendar: Calendar

    /// Default fallback when nothing is persisted: 22:00 → 07:00.
    public static let defaultHours = QuietHours(
        startHour: 22, startMinute: 0,
        endHour: 7, endMinute: 0
    )

    public var startTime: Date {
        didSet { persist() }
    }
    public var endTime: Date {
        didSet { persist() }
    }

    public init(
        store: UserDefaultsQuietHoursStore = UserDefaultsQuietHoursStore(),
        calendar: Calendar = .current,
        now: Date = .now
    ) {
        self.store = store
        self.calendar = calendar
        let loaded = store.load() ?? Self.defaultHours
        let day = calendar.startOfDay(for: now)
        self.startTime =
            calendar.date(
                bySettingHour: loaded.startHour,
                minute: loaded.startMinute,
                second: 0,
                of: day
            ) ?? day
        self.endTime =
            calendar.date(
                bySettingHour: loaded.endHour,
                minute: loaded.endMinute,
                second: 0,
                of: day
            ) ?? day
    }

    private func persist() {
        let s = calendar.dateComponents([.hour, .minute], from: startTime)
        let e = calendar.dateComponents([.hour, .minute], from: endTime)
        store.save(
            QuietHours(
                startHour: s.hour ?? Self.defaultHours.startHour,
                startMinute: s.minute ?? Self.defaultHours.startMinute,
                endHour: e.hour ?? Self.defaultHours.endHour,
                endMinute: e.minute ?? Self.defaultHours.endMinute
            )
        )
    }
}
