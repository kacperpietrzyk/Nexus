import Foundation
import NexusCore

/// Pure, view-independent editing ops over a note's ordered `[NoteProperty]` bag
/// (Tranche 2 Plan E, spec §4.4). Keys are unique CASE-SENSITIVELY within a note
/// — these helpers enforce it at the edit seam (the repository de-duplicates
/// defensively as the backstop). Kept here (not in the view/model) so the rules
/// are unit-testable without SwiftData, mirroring `NoteListGrouping`.
public enum NotePropertyEditing {
    /// UI-facing classification of `NotePropertyValue` for the type menu.
    public enum PropertyType: String, CaseIterable, Sendable {
        case text
        case number
        case boolean
        case date
        case list

        public var label: String {
            switch self {
            case .text: return "Text"
            case .number: return "Number"
            case .boolean: return "Yes/No"
            case .date: return "Date"
            case .list: return "List"
            }
        }

        public init(of value: NotePropertyValue) {
            switch value {
            case .string: self = .text
            case .number: self = .number
            case .bool: self = .boolean
            case .date: self = .date
            case .list: self = .list
            }
        }
    }

    /// Trimmed key; properties never carry surrounding whitespace.
    public static func normalizedKey(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Append a new key with an empty `.string` value. nil when the key is blank
    /// or already present (case-sensitive).
    public static func add(key raw: String, to properties: [NoteProperty]) -> [NoteProperty]? {
        let key = normalizedKey(raw)
        guard !key.isEmpty, !properties.contains(where: { $0.key == key }) else { return nil }
        return properties + [NoteProperty(key: key, value: .string(""))]
    }

    /// Rename a key in place (position + value preserved). nil when the source is
    /// missing, the target is blank, or the target collides with ANOTHER key.
    public static func rename(
        key: String,
        to newRaw: String,
        in properties: [NoteProperty]
    ) -> [NoteProperty]? {
        let newKey = normalizedKey(newRaw)
        guard !newKey.isEmpty,
            let index = properties.firstIndex(where: { $0.key == key }),
            !properties.contains(where: { $0.key == newKey && $0.key != key })
        else { return nil }
        var result = properties
        result[index] = NoteProperty(key: newKey, value: result[index].value)
        return result
    }

    /// Replace a key's value in place. nil when the key is missing.
    public static func setValue(
        _ value: NotePropertyValue,
        forKey key: String,
        in properties: [NoteProperty]
    ) -> [NoteProperty]? {
        guard let index = properties.firstIndex(where: { $0.key == key }) else { return nil }
        var result = properties
        result[index] = NoteProperty(key: key, value: value)
        return result
    }

    public static func remove(key: String, from properties: [NoteProperty]) -> [NoteProperty] {
        properties.filter { $0.key != key }
    }

    // MARK: - Type conversion (the editor's type menu)

    nonisolated(unsafe) private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    /// Best-effort conversion between property types. `now` anchors the fallback
    /// for unparseable date text (injected for determinism in tests).
    public static func convert(
        _ value: NotePropertyValue,
        to type: PropertyType,
        now: Date = Date.now
    ) -> NotePropertyValue {
        guard PropertyType(of: value) != type else { return value }
        let text = displayText(of: value)
        switch type {
        case .text: return .string(text)
        case .number: return .number(Double(text) ?? 0)
        case .boolean: return .bool(text.lowercased() == "true")
        case .date: return .date(isoFormatter.date(from: text) ?? now)
        case .list: return .list(listItems(from: text))
        }
    }

    /// Single-line rendering of a value (text-field seeds, conversions).
    public static func displayText(of value: NotePropertyValue) -> String {
        switch value {
        case .string(let text): return text
        case .number(let number): return numberText(number)
        case .bool(let flag): return flag ? "true" : "false"
        case .date(let date): return isoFormatter.string(from: date)
        case .list(let items): return items.joined(separator: ", ")
        }
    }

    /// Integral doubles collapse ("2", not "2.0") — matches the exporter.
    public static func numberText(_ value: Double) -> String {
        if let integer = Int(exactly: value) { return String(integer) }
        return String(value)
    }

    /// Comma-separated text → trimmed, non-empty list items.
    public static func listItems(from raw: String) -> [String] {
        raw.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
