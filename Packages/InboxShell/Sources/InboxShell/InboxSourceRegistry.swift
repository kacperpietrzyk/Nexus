import Foundation

public enum InboxSourceRegistryError: Error, Equatable {
    case missingSource(String)
}

public actor InboxSourceRegistry {
    public static let shared = InboxSourceRegistry()

    private var sources: [String: any InboxSource] = [:]

    public init() {}

    public func register(_ source: any InboxSource) {
        sources[source.id] = source
    }

    public func unregister(id: String) {
        sources[id] = nil
    }

    public func sourceIDs() -> [String] {
        sources.keys.sorted()
    }

    public func allItems() async throws -> [InboxItem] {
        var result: [InboxItem] = []
        for source in sources.values {
            result.append(contentsOf: try await source.items())
        }
        return result.sorted { lhs, rhs in
            if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
            return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }
    }

    public func archive(_ item: InboxItem) async throws {
        guard let source = sources[item.sourceID] else {
            throw InboxSourceRegistryError.missingSource(item.sourceID)
        }
        try await source.archive(item)
    }

    public func snooze(_ item: InboxItem, until date: Date) async throws {
        guard let source = sources[item.sourceID] else {
            throw InboxSourceRegistryError.missingSource(item.sourceID)
        }
        try await source.snooze(item, until: date)
    }
}
