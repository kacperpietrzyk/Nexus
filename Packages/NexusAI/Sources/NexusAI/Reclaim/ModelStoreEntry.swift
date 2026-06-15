import Foundation

/// One model directory found on disk during a reconciler scan.
public struct ModelStoreEntry: Sendable, Equatable {
    public enum Kind: Sendable, Equatable { case chat, embedder, transcription, unknown }
    public enum Classification: Sendable, Equatable {
        /// Named by the current `ResolvedModelSet` (or current Whisper variant) — keep.
        case canonical
        /// Not canonical and the app never loads from it — reclaim.
        case orphan
        /// A superseded chat model that is still the only working one (new model not
        /// downloaded yet) — protect until the new model lands.
        case staleButActive
        /// A download is in progress for this manifest — never sweep.
        case inFlight
    }

    public let id: String  // manifest id, repo dir name, or Whisper variant
    public let path: URL
    public let sizeBytes: Int64
    public let kind: Kind
    public let classification: Classification

    public init(
        id: String,
        path: URL,
        sizeBytes: Int64,
        kind: Kind,
        classification: Classification
    ) {
        self.id = id
        self.path = path
        self.sizeBytes = sizeBytes
        self.kind = kind
        self.classification = classification
    }
}
