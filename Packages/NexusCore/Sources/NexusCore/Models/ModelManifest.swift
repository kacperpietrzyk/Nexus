import Foundation
import SwiftData

/// Catalog record for one downloadable MLX model.
///
/// CloudKit-mirrored (NexusSchemaV7). Per Phase 1a learning:
/// - No `@Attribute(.unique)` — that attribute is CloudKit-incompatible.
/// - Every non-optional stored property carries an inline default so CloudKit
///   can hydrate rows that predate a new column (the same convention used by
///   `TaskItem`, `Link`, `Project`, etc. in NexusCore).
/// - Uniqueness of `id` is enforced in `ModelCatalog.bootstrap` via a
///   `Set<String>` membership check (Task 4), not at the storage layer.
///
/// Per-device mutable state (download status, localFolderPath, downloadedAt,
/// lastUsedAt, assignedAsChat, assignedAsEmbedder) lives in UserDefaults via
/// `ModelManifestLocalState` (Task 5) — it is NOT stored here.
@Model
public final class ModelManifest {
    // MARK: - Catalog identity

    /// Stable catalog slug used as the primary key in application logic.
    /// Derived from the HF repo path (e.g. "qwen3.5-9b-instruct-4bit"), NOT a
    /// UUID like sibling models — a deterministic slug survives catalog reseeds
    /// and stays identical across devices so CloudKit-synced user-preference
    /// overrides keep pointing at the same model after a re-bootstrap.
    public var id: String = ""

    /// Hugging Face repo path. Example: "mlx-community/Qwen3.5-9B-Instruct-4bit"
    public var hfPath: String = ""

    /// Model family for grouping in the UI. Example: "qwen3.5"
    public var family: String = ""

    /// Human-readable label shown in Settings and the Agent panel.
    public var displayName: String = ""

    // MARK: - Hardware requirements

    /// Approximate disk footprint after download, in gigabytes.
    public var sizeGB: Double = 0.0

    /// Minimum RAM (GB) for comfortable inference without thrashing.
    public var recommendedRAMGB: Int = 0

    /// Maximum token context window supported by this model checkpoint.
    public var contextLength: Int = 0

    // MARK: - Capability flags

    /// Whether the model checkpoint supports structured tool-call output.
    public var supportsTools: Bool = false

    /// Whether the model checkpoint accepts image inputs.
    public var supportsVision: Bool = false

    /// BCP-47 locale codes the model handles well. Example: ["en", "pl"]
    public var supportedLocales: [String] = []

    /// Intended role: "chat" or "embedder".
    public var purpose: String = "chat"

    // MARK: - User-preference overrides (CloudKit-synced)

    /// Override sampling temperature. nil = use platform / catalog default.
    public var temperatureOverride: Double?

    /// Override max tokens per response. nil = use platform / catalog default.
    public var maxTokensOverride: Int?

    /// Override idle-timeout before the runtime unloads the model (seconds).
    /// nil = use platform / catalog default.
    public var idleTimeoutSecondsOverride: Int?

    /// Override system prompt injected at the beginning of every conversation.
    /// nil = use the built-in prompt for this model's purpose.
    public var systemPromptOverride: String?

    // MARK: - Init

    public init(
        id: String,
        hfPath: String,
        family: String,
        displayName: String,
        sizeGB: Double,
        recommendedRAMGB: Int,
        contextLength: Int,
        supportsTools: Bool,
        supportsVision: Bool,
        supportedLocales: [String],
        purpose: String,
        temperatureOverride: Double? = nil,
        maxTokensOverride: Int? = nil,
        idleTimeoutSecondsOverride: Int? = nil,
        systemPromptOverride: String? = nil
    ) {
        self.id = id
        self.hfPath = hfPath
        self.family = family
        self.displayName = displayName
        self.sizeGB = sizeGB
        self.recommendedRAMGB = recommendedRAMGB
        self.contextLength = contextLength
        self.supportsTools = supportsTools
        self.supportsVision = supportsVision
        self.supportedLocales = supportedLocales
        self.purpose = purpose
        self.temperatureOverride = temperatureOverride
        self.maxTokensOverride = maxTokensOverride
        self.idleTimeoutSecondsOverride = idleTimeoutSecondsOverride
        self.systemPromptOverride = systemPromptOverride
    }
}
