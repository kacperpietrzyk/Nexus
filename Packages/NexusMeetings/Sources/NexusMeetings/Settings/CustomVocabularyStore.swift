import Foundation
import NexusCore

/// A single custom-vocabulary entry: a spoken term WhisperKit/Parakeet tends to
/// mis-transcribe, plus the canonical replacement the user wants in the final
/// transcript (e.g. `term: "threat forge"` -> `replacement: "ThreatForge"`).
///
/// `term` biases transcription (fed to WhisperKit as a prompt) and is also the
/// left-hand side of the deterministic post-merge replacement pass; `replacement`
/// is the canonical spelling substituted in.
public struct CustomVocabularyEntry: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public let term: String
    public let replacement: String

    public init(id: UUID = UUID(), term: String, replacement: String) {
        self.id = id
        self.term = term
        self.replacement = replacement
    }

    /// Whether this entry contributes anything once trimmed. An entry with an
    /// empty term can neither bias transcription nor drive a replacement.
    var isUsable: Bool {
        term.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }
}

public protocol CustomVocabularyStoring: Sendable {
    func load() -> [CustomVocabularyEntry]
    func save(_ entries: [CustomVocabularyEntry])
}

/// UserDefaults-backed store for the custom vocabulary list, following the
/// `MeetingsSettingsStores` pattern (no schema churn — settings, not synced
/// model). Backed by the shared app-group defaults so the helper process (which
/// runs the transcription pipeline) and the app UI editor see the same list.
public final class UserDefaultsCustomVocabularyStore: CustomVocabularyStoring, @unchecked Sendable {
    public static let shared = UserDefaultsCustomVocabularyStore()

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .nexusGroup) {
        self.defaults = defaults
    }

    public func load() -> [CustomVocabularyEntry] {
        guard
            let data = defaults.data(forKey: MeetingsSettingsKeys.customVocabulary),
            let entries = try? JSONDecoder().decode([CustomVocabularyEntry].self, from: data)
        else {
            return []
        }
        return entries
    }

    public func save(_ entries: [CustomVocabularyEntry]) {
        guard let data = try? JSONEncoder().encode(entries) else {
            return
        }
        defaults.set(data, forKey: MeetingsSettingsKeys.customVocabulary)
    }
}
