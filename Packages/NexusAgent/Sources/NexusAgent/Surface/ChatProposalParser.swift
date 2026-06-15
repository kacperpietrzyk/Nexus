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

    /// Finds the ```nexus-proposal … ``` fence.
    /// Returns full range (including fences) and inner body range (trimmed of leading newline).
    private static func blockRange(
        in text: String
    ) -> (full: Range<String.Index>, body: Range<String.Index>)? {
        guard let open = text.range(of: "```nexus-proposal") else { return nil }
        let afterOpen = open.upperBound
        guard let close = text.range(of: "```", range: afterOpen..<text.endIndex) else { return nil }
        let bodyStart = text[afterOpen...].firstIndex(where: { !$0.isNewline }) ?? afterOpen
        return (open.lowerBound..<close.upperBound, bodyStart..<close.lowerBound)
    }
}
