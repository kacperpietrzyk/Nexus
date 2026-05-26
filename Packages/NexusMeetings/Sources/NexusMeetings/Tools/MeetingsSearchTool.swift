import Foundation
import NexusAgentTools
import NexusCore

public struct MeetingsSearchTool: AgentTool {
    public let name = "meetings.search"
    public let description = "Searches meeting titles, transcripts, and summaries."
    public let inputSchema: JSONSchema = .object(
        properties: [
            "query": .string(description: "Non-empty search query."),
            "limit": .integer(minimum: 1, maximum: 50, description: "Maximum hits to return. Defaults to 10."),
        ],
        required: ["query"]
    )

    private let contextRef: ModelContextRef

    @MainActor
    public init(repository: MeetingRepository) {
        self.contextRef = ModelContextRef(repository.context)
    }

    @MainActor
    public func call(args: JSONValue, context _: AgentContext) async throws -> JSONValue {
        let query = try MeetingsToolArguments.requiredString(args["query"], field: "query")
        let limit = try MeetingsToolArguments.boundedInt(args["limit"], field: "limit", default: 10, range: 1...50)
        let meetings = try MeetingRepository(context: contextRef.context)
            .search(query: query, limit: limit)
            .map { SearchHit(meetingID: $0.id.uuidString, title: $0.title, snippet: snippet(for: $0, query: query)) }
        return try MeetingsToolJSON.encode(["hits": Array(meetings)])
    }

    private func snippet(for meeting: Meeting, query: String) -> String {
        let haystack =
            [meeting.summaryText, meeting.transcriptText, meeting.title]
            .first { Self.matchRange(in: $0, query: query) != nil } ?? meeting.searchableText
        guard haystack.count > 220 else { return haystack }
        guard let range = Self.matchRange(in: haystack, query: query) else {
            return String(haystack.prefix(220))
        }
        let lower = haystack.index(range.lowerBound, offsetBy: -80, limitedBy: haystack.startIndex) ?? haystack.startIndex
        let upper = haystack.index(range.upperBound, offsetBy: 140, limitedBy: haystack.endIndex) ?? haystack.endIndex
        return String(haystack[lower..<upper])
    }

    private static func matchRange(in text: String, query: String) -> Range<String.Index>? {
        text.range(of: query, options: [.caseInsensitive, .diacriticInsensitive])
    }

    private struct SearchHit: Codable, Equatable {
        let meetingID: String
        let title: String
        let snippet: String
    }
}
