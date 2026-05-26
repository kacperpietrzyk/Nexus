import Foundation

/// Per-device download and assignment state for a model manifest, keyed by
/// manifest ID. Stored in ``UserDefaults`` (not CloudKit) because each device
/// independently manages which models are downloaded and which are active.
///
/// ``Store`` uses `@unchecked Sendable` rather than an actor because
/// `UserDefaults` is Apple-documented as thread-safe, making actor serialisation
/// redundant. This matches the pattern in ``UserDefaultsConsentStore``.
public struct ModelManifestLocalState: Sendable, Equatable {
    // MARK: - Status

    public enum Status: String, Sendable, Equatable {
        case available, downloading, downloaded, error
    }

    // MARK: - Fields

    public var status: Status
    public var localFolderPath: String?
    public var downloadProgressPercent: Double
    public var downloadError: String?
    public var downloadedAt: Date?
    public var lastUsedAt: Date?
    public var assignedAsChat: Bool
    public var assignedAsEmbedder: Bool

    // MARK: - Init

    public init(
        status: Status = .available,
        localFolderPath: String? = nil,
        downloadProgressPercent: Double = 0,
        downloadError: String? = nil,
        downloadedAt: Date? = nil,
        lastUsedAt: Date? = nil,
        assignedAsChat: Bool = false,
        assignedAsEmbedder: Bool = false
    ) {
        self.status = status
        self.localFolderPath = localFolderPath
        self.downloadProgressPercent = downloadProgressPercent
        self.downloadError = downloadError
        self.downloadedAt = downloadedAt
        self.lastUsedAt = lastUsedAt
        self.assignedAsChat = assignedAsChat
        self.assignedAsEmbedder = assignedAsEmbedder
    }

    // MARK: - Store

    /// Persists ``ModelManifestLocalState`` values under
    /// `nexus.mlx.manifest.<id>.<field>` keys in `UserDefaults`.
    ///
    /// Assignment is mutually exclusive: saving `assignedAsChat = true` for
    /// one manifest automatically clears `assignedAsChat` on all others.
    /// The same rule applies to `assignedAsEmbedder`.
    public struct Store: @unchecked Sendable {
        private let defaults: UserDefaults

        public init(defaults: UserDefaults = .standard) {
            self.defaults = defaults
        }

        // MARK: Key builder

        private func key(_ field: String, _ id: String) -> String {
            "nexus.mlx.manifest.\(id).\(field)"
        }

        // MARK: Load

        public func load(manifestID: String) -> ModelManifestLocalState {
            var state = ModelManifestLocalState()
            let rawStatus = defaults.string(forKey: key("status", manifestID))
            state.status = rawStatus.flatMap(Status.init(rawValue:)) ?? state.status
            state.localFolderPath = defaults.string(forKey: key("localFolderPath", manifestID))
            state.downloadProgressPercent = defaults.double(
                forKey: key("downloadProgressPercent", manifestID))
            state.downloadError = defaults.string(forKey: key("downloadError", manifestID))
            state.downloadedAt = defaults.object(forKey: key("downloadedAt", manifestID)) as? Date
            state.lastUsedAt = defaults.object(forKey: key("lastUsedAt", manifestID)) as? Date
            state.assignedAsChat = defaults.bool(forKey: key("assignedAsChat", manifestID))
            state.assignedAsEmbedder = defaults.bool(forKey: key("assignedAsEmbedder", manifestID))
            return state
        }

        // MARK: Save

        public func save(manifestID: String, state: ModelManifestLocalState) {
            defaults.set(state.status.rawValue, forKey: key("status", manifestID))
            defaults.set(state.localFolderPath, forKey: key("localFolderPath", manifestID))
            defaults.set(
                state.downloadProgressPercent, forKey: key("downloadProgressPercent", manifestID))
            defaults.set(state.downloadError, forKey: key("downloadError", manifestID))
            defaults.set(state.downloadedAt, forKey: key("downloadedAt", manifestID))
            defaults.set(state.lastUsedAt, forKey: key("lastUsedAt", manifestID))
            if state.assignedAsChat {
                clearAllAssignments(field: "assignedAsChat", except: manifestID)
            }
            if state.assignedAsEmbedder {
                clearAllAssignments(field: "assignedAsEmbedder", except: manifestID)
            }
            defaults.set(state.assignedAsChat, forKey: key("assignedAsChat", manifestID))
            defaults.set(state.assignedAsEmbedder, forKey: key("assignedAsEmbedder", manifestID))
        }

        // MARK: Queries

        /// Returns the manifest ID currently assigned as the chat model, if any.
        public func currentChatAssignment() -> String? {
            findAssignment(field: "assignedAsChat")
        }

        /// Returns the manifest ID currently assigned as the embedder model, if any.
        public func currentEmbedderAssignment() -> String? {
            findAssignment(field: "assignedAsEmbedder")
        }

        // MARK: Helpers

        private func findAssignment(field: String) -> String? {
            let dict = defaults.dictionaryRepresentation()
            let prefix = "nexus.mlx.manifest."
            for (rawKey, value) in dict {
                guard rawKey.hasPrefix(prefix), rawKey.hasSuffix(".\(field)") else { continue }
                guard let flag = value as? Bool, flag else { continue }
                let stripped = String(rawKey.dropFirst(prefix.count))
                return String(stripped.dropLast(".\(field)".count))
            }
            return nil
        }

        private func clearAllAssignments(field: String, except keepID: String) {
            let dict = defaults.dictionaryRepresentation()
            let prefix = "nexus.mlx.manifest."
            for rawKey in dict.keys where rawKey.hasPrefix(prefix) && rawKey.hasSuffix(".\(field)") {
                let stripped = String(rawKey.dropFirst(prefix.count))
                let manifestID = String(stripped.dropLast(".\(field)".count))
                if manifestID != keepID {
                    defaults.set(false, forKey: rawKey)
                }
            }
        }
    }
}
