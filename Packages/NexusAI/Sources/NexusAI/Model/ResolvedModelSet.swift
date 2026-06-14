import Foundation

/// The single per-platform model set resolved from the catalog + device tier.
/// Plain value — never persisted, no schema change.
public struct ResolvedModelSet: Sendable, Equatable {
    public let chatManifestID: String
    public let chatHFPath: String
    public let chatContextLength: Int
    public let chatSizeGB: Double
    public let embedderManifestID: String
    public let embedderHFPath: String
    public let embedderSizeGB: Double

    public init(
        chatManifestID: String,
        chatHFPath: String,
        chatContextLength: Int,
        chatSizeGB: Double,
        embedderManifestID: String,
        embedderHFPath: String,
        embedderSizeGB: Double
    ) {
        self.chatManifestID = chatManifestID
        self.chatHFPath = chatHFPath
        self.chatContextLength = chatContextLength
        self.chatSizeGB = chatSizeGB
        self.embedderManifestID = embedderManifestID
        self.embedderHFPath = embedderHFPath
        self.embedderSizeGB = embedderSizeGB
    }
}
