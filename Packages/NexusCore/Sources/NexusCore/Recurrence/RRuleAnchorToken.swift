import Foundation

/// String-level helpers for the non-standard `ANCHOR=` RRULE extension token
/// (T1 completion-based recurrence). They operate on the raw
/// `TaskItem.recurrenceRule` text without re-serializing the rest of the rule,
/// so a hand-typed custom RRULE keeps its exact token order and casing.
public enum RRuleAnchorToken {
    /// The serialized completion-anchor token.
    public static let completion = "ANCHOR=COMPLETION"

    /// True when `ruleText` carries `ANCHOR=COMPLETION` (case-insensitive).
    public static func isCompletionAnchored(_ ruleText: String) -> Bool {
        tokens(of: ruleText).contains { $0.key == "ANCHOR" && $0.value == "COMPLETION" }
    }

    /// `ruleText` with any `ANCHOR=` token removed; other tokens untouched.
    public static func strippingAnchor(_ ruleText: String) -> String {
        ruleText
            .split(separator: ";")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.uppercased().hasPrefix("ANCHOR=") }
            .joined(separator: ";")
    }

    /// Returns `ruleText` rewritten to carry (or drop) the completion anchor.
    /// An empty `ruleText` stays empty — there is no rule to anchor.
    public static func applying(completionAnchor: Bool, to ruleText: String) -> String {
        let base = strippingAnchor(ruleText)
        guard completionAnchor, !base.isEmpty else { return base }
        return base + ";" + completion
    }

    private static func tokens(of ruleText: String) -> [(key: String, value: String)] {
        ruleText.split(separator: ";").compactMap { pair in
            let parts = pair.split(separator: "=", maxSplits: 1).map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            }
            guard parts.count == 2 else { return nil }
            return (parts[0], parts[1])
        }
    }
}
