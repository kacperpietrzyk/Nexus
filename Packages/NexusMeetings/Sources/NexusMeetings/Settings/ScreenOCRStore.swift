import Foundation
import NexusCore

/// Opt-in toggle for capturing screen context (shared-window OCR) during a
/// recording (spec §7.2 / I4). Default OFF: `UserDefaults.bool` is `false` for an
/// unset key, so a fresh install never captures the screen until the user
/// explicitly enables it. Backed by the shared app-group defaults so the helper
/// (which records) and the app UI editor agree, mirroring
/// ``UserDefaultsCustomVocabularyStore``.
public protocol ScreenOCRStoring: Sendable {
    func isEnabled() -> Bool
    func save(enabled: Bool)
}

public final class UserDefaultsScreenOCRStore: ScreenOCRStoring, @unchecked Sendable {
    public static let shared = UserDefaultsScreenOCRStore()

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .nexusGroup) {
        self.defaults = defaults
    }

    public func isEnabled() -> Bool {
        defaults.bool(forKey: MeetingsSettingsKeys.screenOCREnabled)
    }

    public func save(enabled: Bool) {
        defaults.set(enabled, forKey: MeetingsSettingsKeys.screenOCREnabled)
    }
}
