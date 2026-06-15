import Foundation

public struct ContextFocus: Sendable, Equatable {
    public let primaryID: UUID?
    public let kind: String?  // ItemKind raw value, e.g. "meeting", "project"
    public let freeText: String?
    public init(primaryID: UUID? = nil, kind: String? = nil, freeText: String? = nil) {
        self.primaryID = primaryID; self.kind = kind; self.freeText = freeText
    }
}

/// Deterministic repo slices the assembler can render. Each maps to an existing repo query.
public enum RepoSlice: Sendable, Equatable {
    case tasksDueWithin(days: Int)
    case overdueTasks
    case projectKeyDates(projectID: UUID)
    case person(id: UUID)
    case recentActivity(itemID: UUID, kind: String, limit: Int)
}

public struct RagQuerySpec: Sendable, Equatable {
    public let query: String
    public let limit: Int
    public init(query: String, limit: Int) { self.query = query; self.limit = limit }
}

public struct ContextRecipe: Sendable, Equatable {
    public let includeEntity: Bool
    public let linkGraphDepth: Int
    public let repoSlices: [RepoSlice]
    public let ragQuery: RagQuerySpec?
    public let tokenBudget: Int
    public init(
        includeEntity: Bool = false, linkGraphDepth: Int = 0,
        repoSlices: [RepoSlice] = [], ragQuery: RagQuerySpec? = nil, tokenBudget: Int = 2_000
    ) {
        self.includeEntity = includeEntity; self.linkGraphDepth = linkGraphDepth
        self.repoSlices = repoSlices; self.ragQuery = ragQuery; self.tokenBudget = tokenBudget
    }
}

/// Ordered, named context sections + budget accounting.
public struct AssembledContext: Sendable, Equatable {
    public struct Section: Sendable, Equatable {
        public let title: String
        public let body: String
        public init(title: String, body: String) { self.title = title; self.body = body }
    }
    public let sections: [Section]
    public let estimatedTokens: Int
    public init(sections: [Section], estimatedTokens: Int) {
        self.sections = sections; self.estimatedTokens = estimatedTokens
    }
    /// Compact rendered block for the prompt `context` array (one string per section).
    public func renderedBlocks() -> [String] {
        sections.map { "## \($0.title)\n\($0.body)" }
    }
}
