import Foundation

/// Security boundary for the `attachments.*` path-handoff tools. An MCP caller hands
/// the app a host-filesystem path (or `file://` URL); the app reads the bytes itself.
/// This policy is the gate: it rejects relative paths and any path that escapes the
/// allow-listed ingest root, returning a canonicalized `URL`. Size/MIME are then
/// enforced by `AttachmentImportService` (image-only) — `validateSize` here is a
/// pre-read guard so an oversized file is rejected before the bytes are loaded.
public enum AttachmentIngestPolicy {
    public static let maxBytes = 25 * 1_024 * 1_024

    /// Canonicalize `source` (absolute path or `file://` URL) and assert it lives
    /// inside `allowedRoot`. Throws `AgentError.validation` for anything that is not
    /// an absolute, in-root location.
    public static func resolve(source: String, allowedRoot: URL) throws -> URL {
        let raw: URL
        if source.hasPrefix("file://") {
            guard let url = URL(string: source) else {
                throw AgentError.validation("Invalid file URL: \(source)")
            }
            raw = url
        } else {
            guard source.hasPrefix("/") else {
                throw AgentError.validation("source_path must be an absolute path or file:// URL")
            }
            raw = URL(fileURLWithPath: source)
        }

        let resolved = raw.standardizedFileURL.resolvingSymlinksInPath()
        let root = allowedRoot.standardizedFileURL.resolvingSymlinksInPath()
        guard resolved.path == root.path || resolved.path.hasPrefix(root.path + "/") else {
            throw AgentError.validation("source_path escapes the allowed ingest root")
        }
        return resolved
    }

    /// Pre-read size guard. `AttachmentImportService` re-checks against its own
    /// `maxBytes`, but rejecting here avoids loading an oversized file into memory.
    public static func validateSize(_ bytes: Int) throws {
        guard bytes <= maxBytes else {
            throw AgentError.validation("File exceeds the \(maxBytes)-byte limit")
        }
    }
}
