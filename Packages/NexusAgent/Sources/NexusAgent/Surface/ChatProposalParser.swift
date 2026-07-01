import Foundation
import NexusCore  // JSONValue

private struct ProposalBlock: Decodable {
    struct Mutation: Decodable {
        let tool: String
        let args: [String: JSONValue]
    }

    let rationale: String
    let mutations: [Mutation]
}

public enum ChatProposalParser {
    public struct Result: Sendable, Equatable {
        public let displayText: String
        public let proposal: Proposal?
    }

    /// Only these tools may appear in a proposed mutation (writes; reads are answered, not proposed).
    private static let allowedTools: Set<String> = ["tasks.create", "tasks.update"]

    public static func parse(_ text: String) -> Result {
        guard let range = blockRange(in: text) else {
            return Result(displayText: text, proposal: nil)
        }
        let raw = String(text[range.body])
        let replaced = text.replacingCharacters(in: range.full, with: "")
        let stripped = replaced.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            let data = raw.data(using: .utf8),
            let block = try? JSONDecoder().decode(ProposalBlock.self, from: data)
        else {
            return Result(displayText: stripped, proposal: nil)
        }
        let mutations: [PendingMutation] = block.mutations.compactMap { m in
            guard allowedTools.contains(m.tool) else { return nil }
            return PendingMutation(toolName: m.tool, arguments: .object(m.args))
        }
        guard !mutations.isEmpty else {
            return Result(displayText: stripped, proposal: nil)
        }
        let previews = mutations.map { ProposalPreview(summary: $0.toolName) }
        return Result(
            displayText: stripped,
            proposal: Proposal(rationale: block.rationale, mutations: mutations, previews: previews)
        )
    }

    /// Locates the proposal fence. Prefers the explicit ```nexus-proposal marker;
    /// if absent, falls back to ANY fenced code block whose body decodes to the
    /// proposal shape — the on-device 12B (gemma4) reliably emits the block but
    /// mislabels the fence as ```json, which would otherwise leak the raw JSON
    /// into the chat. The fallback only matches when the body actually parses as a
    /// `ProposalBlock`, so ordinary code blocks the assistant shows are untouched.
    private static func blockRange(
        in text: String
    ) -> (full: Range<String.Index>, body: Range<String.Index>)? {
        if let explicit = explicitBlockRange(in: text) {
            return explicit
        }
        return decodableFenceRange(in: text)
    }

    /// The explicit ```nexus-proposal … ``` fence (stripped even when its JSON is
    /// malformed — an explicit proposal marker should never leak).
    private static func explicitBlockRange(
        in text: String
    ) -> (full: Range<String.Index>, body: Range<String.Index>)? {
        guard let open = text.range(of: "```nexus-proposal") else { return nil }
        let afterOpen = open.upperBound
        guard let close = text.range(of: "```", range: afterOpen..<text.endIndex) else { return nil }
        let bodyStart = text[afterOpen...].firstIndex(where: { !$0.isNewline }) ?? afterOpen
        return (open.lowerBound..<close.upperBound, bodyStart..<close.lowerBound)
    }

    /// Scans every ``` fence and returns the first whose body decodes as a
    /// `ProposalBlock` (mislabeled-fence tolerance, e.g. ```json). Gating on a
    /// successful decode keeps legitimate code blocks in the display.
    private static func decodableFenceRange(
        in text: String
    ) -> (full: Range<String.Index>, body: Range<String.Index>)? {
        var searchStart = text.startIndex
        while let open = text.range(of: "```", range: searchStart..<text.endIndex) {
            guard let close = text.range(of: "```", range: open.upperBound..<text.endIndex) else {
                return nil
            }
            // The opener line may carry a language tag (```json); the body starts
            // after that first newline.
            let bodyStart =
                text[open.upperBound...].firstIndex(where: { $0.isNewline })
                .map { text.index(after: $0) } ?? open.upperBound
            let bodyRange = bodyStart..<close.lowerBound
            if bodyStart <= close.lowerBound, decodesAsProposalBlock(String(text[bodyRange])) {
                return (open.lowerBound..<close.upperBound, bodyRange)
            }
            searchStart = close.upperBound
        }
        return nil
    }

    /// True when `body` parses as the proposal shape (`rationale` + `mutations`).
    private static func decodesAsProposalBlock(_ body: String) -> Bool {
        guard let data = body.data(using: .utf8) else { return false }
        return (try? JSONDecoder().decode(ProposalBlock.self, from: data)) != nil
    }
}
