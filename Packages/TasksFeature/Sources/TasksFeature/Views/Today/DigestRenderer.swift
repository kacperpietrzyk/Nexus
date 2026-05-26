import NexusUI
import SwiftUI

public enum DigestRenderer {
    public static func render(_ raw: String) -> Text {
        Text(attributedString(for: raw))
    }

    public static func attributedString(for raw: String) -> AttributedString {
        var result = AttributedString()
        var index = raw.startIndex

        while index < raw.endIndex {
            guard let marker = nextMarker(in: raw, from: index) else {
                result.append(attributed(raw[index..<raw.endIndex], kind: nil))
                break
            }

            if marker.openRange.lowerBound > index {
                result.append(attributed(raw[index..<marker.openRange.lowerBound], kind: nil))
            }

            result.append(
                attributed(
                    raw[marker.openRange.upperBound..<marker.closeRange.lowerBound],
                    kind: marker.kind
                )
            )
            index = marker.closeRange.upperBound
        }

        return result
    }

    private static func attributed(_ segment: Substring, kind: MarkerKind?) -> AttributedString {
        var attributed = AttributedString(String(segment))
        switch kind {
        case .emphasis:
            attributed.foregroundColor = NexusColor.Text.primary
        case .mono:
            attributed.font = NexusType.mono
            attributed.foregroundColor = NexusColor.Text.primary
        case nil:
            attributed.foregroundColor = NexusColor.Text.secondary
        }
        return attributed
    }

    private static func nextMarker(in raw: String, from index: String.Index) -> MarkerMatch? {
        MarkerKind.allCases
            .compactMap { kind -> MarkerMatch? in
                guard
                    let openRange = raw.range(of: kind.open, range: index..<raw.endIndex),
                    let closeRange = raw.range(of: kind.close, range: openRange.upperBound..<raw.endIndex)
                else { return nil }
                return MarkerMatch(kind: kind, openRange: openRange, closeRange: closeRange)
            }
            .min { lhs, rhs in lhs.openRange.lowerBound < rhs.openRange.lowerBound }
    }
}

private struct MarkerMatch {
    let kind: MarkerKind
    let openRange: Range<String.Index>
    let closeRange: Range<String.Index>
}

private enum MarkerKind: CaseIterable {
    /// Emphasis span — wire marker strings `[[accent]]`/`[[/accent]]` are preserved
    /// byte-for-byte as they are emitted by `HeroBriefService` and `AgentBriefService`.
    case emphasis
    case mono

    var open: String {
        switch self {
        case .emphasis: return "[[accent]]"
        case .mono: return "[[mono]]"
        }
    }

    var close: String {
        switch self {
        case .emphasis: return "[[/accent]]"
        case .mono: return "[[/mono]]"
        }
    }
}
