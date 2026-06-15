import Foundation

/// Wire DTO for `stats.productivity`: the (echoed, normalized) ISO8601 range plus
/// the count of tasks completed within it. CodingKeys are snake_case to match the
/// tool contract.
public struct ProductivityDTO: Codable, Sendable, Equatable {
    public let from: String
    public let to: String
    public let completedCount: Int

    public init(from: String, to: String, completedCount: Int) {
        self.from = from
        self.to = to
        self.completedCount = completedCount
    }

    private enum CodingKeys: String, CodingKey {
        case from
        case to
        case completedCount = "completed_count"
    }
}
