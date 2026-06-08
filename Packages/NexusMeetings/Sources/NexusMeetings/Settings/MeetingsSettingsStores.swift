import Foundation
import NexusAI
import NexusCore

public enum MeetingsSettingsKeys {
    public static let appPatternRegistry = "nexus.meetings.patternRegistry.v1"
    public static let helperAutoRecordEnabled = "nexus.meetings.helper.autoRecord.enabled"
    public static let retentionPolicy = "nexus.meetings.retention"
    public static let transcriptionProvider = "nexus.meetings.transcription.provider"
    public static let summaryProvider = "nexus.meetings.summary.provider"
    public static let customVocabulary = "nexus.meetings.customVocabulary.v1"
    public static let screenOCREnabled = "nexus.meetings.screenOCR.enabled"
}

public enum MeetingsTranscriptionProviderPreference: String, CaseIterable, Sendable {
    case parakeetTDTv3 = "parakeet-tdt-v3"
    case whisperKitLarge = "whisperkit-large"
    case ask
}

public enum MeetingsSummaryProviderPreference: String, CaseIterable, Sendable {
    case auto
    case disabled

    public var providerPreference: ProviderPreference? {
        switch self {
        case .auto:
            .auto
        case .disabled:
            nil
        }
    }
}

public protocol AppPatternRegistryStoring: Sendable {
    func load() -> AppPatternRegistry
    func save(_ registry: AppPatternRegistry)
}

public protocol HelperAutoRecordStoring: Sendable {
    func isEnabled() -> Bool
    func save(enabled: Bool)
}

public final class UserDefaultsAppPatternRegistryStore: AppPatternRegistryStoring, @unchecked Sendable {
    public static let shared = UserDefaultsAppPatternRegistryStore()

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .nexusGroup) {
        self.defaults = defaults
    }

    public func load() -> AppPatternRegistry {
        guard
            let data = defaults.data(forKey: MeetingsSettingsKeys.appPatternRegistry),
            let patterns = try? JSONDecoder().decode([AppPattern].self, from: data)
        else {
            return .makeDefault()
        }
        return AppPatternRegistry(patterns: patterns)
    }

    public func save(_ registry: AppPatternRegistry) {
        guard let data = try? JSONEncoder().encode(registry.patterns) else {
            return
        }
        defaults.set(data, forKey: MeetingsSettingsKeys.appPatternRegistry)
    }
}

public final class UserDefaultsMeetingRetentionPolicyStore: @unchecked Sendable {
    public static let shared = UserDefaultsMeetingRetentionPolicyStore()

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .nexusGroup) {
        self.defaults = defaults
    }

    public func load() -> MeetingAudioStorage.RetentionPolicy {
        guard
            let rawPolicy = defaults.string(forKey: MeetingsSettingsKeys.retentionPolicy),
            let policy = MeetingAudioStorage.RetentionPolicy(rawValue: rawPolicy)
        else {
            return .days30
        }
        return policy
    }

    public func save(_ policy: MeetingAudioStorage.RetentionPolicy) {
        defaults.set(policy.rawValue, forKey: MeetingsSettingsKeys.retentionPolicy)
    }
}

public final class UserDefaultsHelperAutoRecordStore: HelperAutoRecordStoring, @unchecked Sendable {
    public static let shared = UserDefaultsHelperAutoRecordStore()

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .nexusGroup) {
        self.defaults = defaults
    }

    public func isEnabled() -> Bool {
        defaults.bool(forKey: MeetingsSettingsKeys.helperAutoRecordEnabled)
    }

    public func save(enabled: Bool) {
        defaults.set(enabled, forKey: MeetingsSettingsKeys.helperAutoRecordEnabled)
    }
}

public final class MeetingsProviderSettingsStore: @unchecked Sendable {
    public static let shared = MeetingsProviderSettingsStore()

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .nexusGroup) {
        self.defaults = defaults
    }

    public func transcriptionProvider() -> MeetingsTranscriptionProviderPreference {
        guard
            let rawValue = defaults.string(forKey: MeetingsSettingsKeys.transcriptionProvider),
            let preference = MeetingsTranscriptionProviderPreference(rawValue: rawValue)
        else {
            return .parakeetTDTv3
        }
        return preference
    }

    public func saveTranscriptionProvider(_ preference: MeetingsTranscriptionProviderPreference) {
        defaults.set(preference.rawValue, forKey: MeetingsSettingsKeys.transcriptionProvider)
    }

    public func summaryProvider() -> MeetingsSummaryProviderPreference {
        guard
            let rawValue = defaults.string(forKey: MeetingsSettingsKeys.summaryProvider),
            let preference = MeetingsSummaryProviderPreference(rawValue: rawValue)
        else {
            return .auto
        }
        return preference
    }

    public func saveSummaryProvider(_ preference: MeetingsSummaryProviderPreference) {
        defaults.set(preference.rawValue, forKey: MeetingsSettingsKeys.summaryProvider)
    }
}

public final class MeetingsPromptStore: @unchecked Sendable {
    public static let shared = MeetingsPromptStore()

    private let applicationSupportURL: URL

    public init(
        applicationSupportURL: URL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
    ) {
        self.applicationSupportURL = applicationSupportURL
    }

    public var promptFileURL: URL {
        applicationSupportURL
            .appendingPathComponent("com.kacperpietrzyk.Nexus", isDirectory: true)
            .appendingPathComponent("meetings_prompt.md")
    }

    public func load() -> String? {
        guard
            let prompt = try? String(contentsOf: promptFileURL, encoding: .utf8),
            prompt.isEmpty == false
        else {
            return nil
        }
        return prompt
    }

    public func save(_ prompt: String) throws {
        try FileManager.default.createDirectory(
            at: promptFileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try prompt.write(to: promptFileURL, atomically: true, encoding: .utf8)
    }

    public func reset() throws {
        guard FileManager.default.fileExists(atPath: promptFileURL.path) else {
            return
        }
        try FileManager.default.removeItem(at: promptFileURL)
    }
}
