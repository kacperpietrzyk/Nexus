import Foundation
import SwiftData

/// Audit record for one lifecycle transition of a downloadable MLX model.
///
/// CloudKit-mirrored (NexusSchemaV7). Per the Phase 1a learning shared with
/// `ModelManifest`, `TaskItem`, `Link`, etc.:
/// - No `@Attribute(.unique)` — CloudKit-incompatible.
/// - Every non-optional stored property carries an inline default so CloudKit
///   can hydrate rows that predate a new column.
///
/// `kind` is a free-form string (one of "started", "completed", "failed",
/// "deleted", "swapped_in", "swapped_out") rather than an enum so the schema
/// stays additive-friendly and CloudKit-safe.
@Model
public final class ModelDownloadEvent {
    /// Catalog slug of the `ModelManifest` this event refers to (its `id`).
    public var modelManifestID: String = ""

    /// Lifecycle transition: "started" | "completed" | "failed" | "deleted"
    /// | "swapped_in" | "swapped_out".
    public var kind: String = ""

    /// When the transition occurred.
    public var occurredAt: Date = Date.now

    /// Bytes transferred during a download, when applicable.
    public var bytesTransferred: Int64?

    /// Wall-clock duration of the operation in seconds, when applicable.
    public var durationSeconds: Double?

    /// Failure detail for "failed" events; nil otherwise.
    public var errorMessage: String?

    public init(
        modelManifestID: String,
        kind: String,
        occurredAt: Date,
        bytesTransferred: Int64? = nil,
        durationSeconds: Double? = nil,
        errorMessage: String? = nil
    ) {
        self.modelManifestID = modelManifestID
        self.kind = kind
        self.occurredAt = occurredAt
        self.bytesTransferred = bytesTransferred
        self.durationSeconds = durationSeconds
        self.errorMessage = errorMessage
    }
}
