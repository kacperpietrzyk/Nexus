import Foundation

/// Extracts the first balanced top-level JSON object substring from prose.
/// Handles two common LM output shapes: free-form prose containing a JSON
/// blob ("Sure, here is the parse: { ... }") and fenced markdown code blocks
/// (```json\n{...}\n```). Brace counting is string-aware so braces inside
/// JSON string literals do not unbalance the match.
internal enum JSONExtractor {
    static func firstObject(in raw: String) -> Data? {
        let scalars = Array(raw)
        guard let openIndex = scalars.firstIndex(of: "{") else { return nil }

        var depth = 0
        var insideString = false
        var escaped = false
        var current = openIndex

        while current < scalars.count {
            let ch = scalars[current]

            if escaped {
                escaped = false
                current += 1
                continue
            }
            if insideString {
                if ch == "\\" {
                    escaped = true
                } else if ch == "\"" {
                    insideString = false
                }
                current += 1
                continue
            }

            switch ch {
            case "\"":
                insideString = true
            case "{":
                depth += 1
            case "}":
                depth -= 1
                if depth == 0 {
                    let substring = String(scalars[openIndex...current])
                    return substring.data(using: .utf8)
                }
            default:
                break
            }
            current += 1
        }
        return nil
    }
}
