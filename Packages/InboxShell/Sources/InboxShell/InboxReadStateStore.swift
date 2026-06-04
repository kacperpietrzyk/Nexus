import Foundation

/// Durable store for which Inbox items the user has marked read.
///
/// `InboxView` previously held read state in a `@State Set<UUID>`, so switching
/// tabs (which unmounts the view) discarded it and every item reappeared as
/// unread. `InboxItem.id` is stable across reloads — the real sources derive it
/// from the underlying `TaskItem.id` — so persisting the id set survives the
/// remount. UserDefaults-backed (matching `ModelManifestLocalState`); read state
/// is low-stakes local UI bookkeeping, not synced domain data, so it does not
/// warrant a SwiftData/CloudKit schema bump.
public struct InboxReadStateStore: @unchecked Sendable {
    // `@unchecked Sendable`: the only stored state is a `UserDefaults` reference,
    // which Apple documents as thread-safe. Lets the `.shared` static singleton
    // satisfy strict-concurrency checking without an actor hop.
    private let defaults: UserDefaults
    private let key = "nexus.inbox.readItemIDs"

    public static let shared = InboxReadStateStore()

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> Set<UUID> {
        let raw = defaults.array(forKey: key) as? [String] ?? []
        return Set(raw.compactMap(UUID.init(uuidString:)))
    }

    public func save(_ ids: Set<UUID>) {
        defaults.set(ids.map(\.uuidString), forKey: key)
    }
}
