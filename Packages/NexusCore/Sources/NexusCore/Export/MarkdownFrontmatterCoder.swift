import Foundation

public indirect enum FrontmatterValue: Equatable, Sendable {
    case string(String)
    case date(Date)
    case list([FrontmatterValue])
    case dict([(String, FrontmatterValue)])
    case none

    public static func == (lhs: FrontmatterValue, rhs: FrontmatterValue) -> Bool {
        switch (lhs, rhs) {
        case (.string(let a), .string(let b)): return a == b
        case (.date(let a), .date(let b)): return a == b
        case (.list(let a), .list(let b)): return a == b
        case (.dict(let a), .dict(let b)):
            guard a.count == b.count else { return false }
            for (lhsPair, rhsPair) in zip(a, b) {
                if lhsPair.0 != rhsPair.0 || lhsPair.1 != rhsPair.1 { return false }
            }
            return true
        case (.none, .none): return true
        default: return false
        }
    }
}

public enum MarkdownFrontmatterError: Error, Equatable {
    case missingOpeningDelimiter
    case missingClosingDelimiter
    case malformedKeyValue(line: String)
}

public struct ParsedFrontmatter: Sendable {
    public let fields: [(String, FrontmatterValue)]
    public let body: String
}

/// Minimal deterministic YAML-subset codec used by `MarkdownExporter`.
/// Supports: string scalars (quoted if they contain `:` or start with whitespace), ISO8601 dates,
/// `null`, flat lists `[]`, lists-of-dicts (one nesting level — enough for `links:`).
/// Rejects: nested lists-of-lists, anchors, multiline scalars, comments, flow style.
/// Determinism guarantees:
/// 1. Fields are emitted in caller-supplied order — no map iteration.
/// 2. Dict keys inside list items are emitted in caller-supplied order.
/// 3. ISO8601 always uses `.withInternetDateTime` (UTC, no fractional seconds).
public enum MarkdownFrontmatterCoder {
    nonisolated(unsafe) public static let dateFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    public static func encode(fields: [(String, FrontmatterValue)]) -> String {
        var out = "---\n"
        for (key, value) in fields {
            out += encodeTopLevel(key: key, value: value)
        }
        out += "---\n"
        return out
    }

    private static func encodeTopLevel(key: String, value: FrontmatterValue) -> String {
        switch value {
        case .string(let s):
            return "\(key): \(encodeScalarString(s))\n"
        case .date(let d):
            return "\(key): \(dateFormatter.string(from: d))\n"
        case .none:
            return "\(key): null\n"
        case .list(let items):
            if items.isEmpty {
                return "\(key): []\n"
            }
            var s = "\(key):\n"
            for item in items {
                s += encodeListItem(item)
            }
            return s
        case .dict(let pairs):
            var s = "\(key):\n"
            for (k, v) in pairs {
                s +=
                    "  "
                    + encodeTopLevel(key: k, value: v).replacingOccurrences(of: "\n", with: "\n  ")
                    .trimmingCharacters(in: .whitespaces) + "\n"
            }
            return s
        }
    }

    private static func encodeListItem(_ value: FrontmatterValue) -> String {
        switch value {
        case .dict(let pairs):
            var s = ""
            for (i, pair) in pairs.enumerated() {
                let prefix = (i == 0) ? "  - " : "    "
                s += "\(prefix)\(pair.0): \(inlineValue(pair.1))\n"
            }
            return s
        default:
            return "  - \(inlineValue(value))\n"
        }
    }

    private static func inlineValue(_ value: FrontmatterValue) -> String {
        switch value {
        case .string(let s): return encodeScalarString(s)
        case .date(let d): return dateFormatter.string(from: d)
        case .none: return "null"
        case .list, .dict: return "<unsupported nested>"
        }
    }

    private static func encodeScalarString(_ s: String) -> String {
        // Quote if string contains characters that confuse YAML or starts with whitespace / is empty.
        let needsQuotes =
            s.isEmpty
            || s.contains(":")
            || s.contains("#")
            || s.contains("\"")
            || s.contains("\n")
            || s.contains(" ")
            || s.first?.isWhitespace == true
            || s.last?.isWhitespace == true
        guard needsQuotes else { return s }
        let escaped = s.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
        return "\"\(escaped)\""
    }

    public static func decode(_ source: String) throws -> ParsedFrontmatter {
        let lines = source.components(separatedBy: "\n")
        guard let first = lines.first, first == "---" else {
            throw MarkdownFrontmatterError.missingOpeningDelimiter
        }
        // Pre-scan: ensure a closing delimiter exists before we try to parse key/value lines,
        // otherwise body lines without `:` would trip `.malformedKeyValue` first.
        guard lines.dropFirst().contains("---") else {
            throw MarkdownFrontmatterError.missingClosingDelimiter
        }
        var fields: [(String, FrontmatterValue)] = []
        var i = 1
        var foundClose = false
        while i < lines.count {
            let line = lines[i]
            if line == "---" {
                foundClose = true
                i += 1
                break
            }
            let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
                .map(String.init)
            guard parts.count == 2 else {
                throw MarkdownFrontmatterError.malformedKeyValue(line: line)
            }
            let key = parts[0].trimmingCharacters(in: .whitespaces)
            let raw = parts[1].trimmingCharacters(in: .whitespaces)
            let value: FrontmatterValue
            if raw.isEmpty {
                let parsed = try decodeBlockValue(lines: lines, startIndex: i + 1)
                value = parsed.value
                i = parsed.nextIndex
                fields.append((key, value))
                continue
            } else if let d = dateFormatter.date(from: raw) {
                value = .date(d)
            } else {
                value = decodeInlineValue(raw)
            }
            fields.append((key, value))
            i += 1
        }
        guard foundClose else { throw MarkdownFrontmatterError.missingClosingDelimiter }

        // Body: skip a single blank separator line if present.
        if i < lines.count, lines[i].isEmpty { i += 1 }
        let body = lines[i...].joined(separator: "\n")
        let trimmedBody = body.hasSuffix("\n") ? String(body.dropLast()) : body
        return ParsedFrontmatter(fields: fields, body: trimmedBody)
    }

    private static func decodeInlineValue(_ raw: String) -> FrontmatterValue {
        if raw == "null" {
            return .none
        }
        if raw == "[]" {
            return .list([])
        }
        if raw.hasPrefix("\""), raw.hasSuffix("\""), raw.count >= 2 {
            let inner = String(raw.dropFirst().dropLast())
                .replacingOccurrences(of: "\\\"", with: "\"")
                .replacingOccurrences(of: "\\n", with: "\n")
                .replacingOccurrences(of: "\\\\", with: "\\")
            return .string(inner)
        }
        if let d = dateFormatter.date(from: raw) {
            return .date(d)
        }
        return .string(raw)
    }

    private static func decodeBlockValue(
        lines: [String],
        startIndex: Int
    ) throws -> (value: FrontmatterValue, nextIndex: Int) {
        var i = startIndex
        var items: [FrontmatterValue] = []
        while i < lines.count {
            let line = lines[i]
            if line == "---" || line.isEmpty || line.hasPrefix("  ") == false {
                break
            }
            guard line.hasPrefix("  - ") else {
                throw MarkdownFrontmatterError.malformedKeyValue(line: line)
            }

            let itemText = String(line.dropFirst(4)).trimmingCharacters(in: .whitespaces)
            if let firstPair = decodeDictPair(itemText) {
                var pairs = [firstPair]
                i += 1
                while i < lines.count, lines[i].hasPrefix("    ") {
                    let childText = String(lines[i].dropFirst(4)).trimmingCharacters(in: .whitespaces)
                    guard let pair = decodeDictPair(childText) else {
                        throw MarkdownFrontmatterError.malformedKeyValue(line: lines[i])
                    }
                    pairs.append(pair)
                    i += 1
                }
                items.append(.dict(pairs))
            } else {
                items.append(decodeInlineValue(itemText))
                i += 1
            }
        }
        return (.list(items), i)
    }

    private static func decodeDictPair(_ text: String) -> (String, FrontmatterValue)? {
        let parts = text.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            .map(String.init)
        guard parts.count == 2 else { return nil }
        let key = parts[0].trimmingCharacters(in: .whitespaces)
        let raw = parts[1].trimmingCharacters(in: .whitespaces)
        return (key, decodeInlineValue(raw))
    }
}
