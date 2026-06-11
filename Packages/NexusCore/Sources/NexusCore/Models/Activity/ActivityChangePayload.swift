import Foundation

/// Old/new value pair carried in `ActivityEntry.payloadJSON` (spec §2.1: small,
/// human-readable old/new values keyed "old"/"new" — raw enum values, UUID
/// strings, or ISO8601 dates). Always encodes BOTH keys (nil → JSON null) so a
/// consumer can distinguish "cleared" (`"new": null`) from "absent".
public struct ActivityChangePayload: Codable, Equatable, Sendable {
    public var old: String?
    public var new: String?

    public init(old: String?, new: String?) {
        self.old = old
        self.new = new
    }

    private enum CodingKeys: String, CodingKey {
        case old
        case new
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        old = try container.decodeIfPresent(String.self, forKey: .old)
        new = try container.decodeIfPresent(String.self, forKey: .new)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        // `Optional` encodes JSON null for nil — deliberate, see type doc.
        try container.encode(old, forKey: .old)
        try container.encode(new, forKey: .new)
    }

    /// Deterministic JSON (sorted keys) for storage in `payloadJSON`.
    public var encodedJSON: String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Lenient decode — nil/garbage payloads (or future shapes synced from a
    /// newer build) return nil instead of throwing, mirroring the
    /// `workflowState` accessor's forward-compat posture.
    public static func decoded(from json: String?) -> ActivityChangePayload? {
        guard let json else { return nil }
        return try? JSONDecoder().decode(ActivityChangePayload.self, from: Data(json.utf8))
    }

    /// ISO8601 (internet date-time, second precision) for date-valued payloads.
    public static func dateString(_ date: Date?) -> String? {
        guard let date else { return nil }
        return iso8601.string(from: date)
    }

    public static func parseDate(_ text: String?) -> Date? {
        guard let text else { return nil }
        return iso8601.date(from: text)
    }

    // `ISO8601DateFormatter` is documented thread-safe; the
    // `MarkdownFrontmatterCoder.dateFormatter` precedent.
    nonisolated(unsafe) private static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}
