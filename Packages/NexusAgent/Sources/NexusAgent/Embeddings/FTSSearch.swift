import Foundation

public protocol FTSSearch: Sendable {
    func search(query: String, limit: Int) async throws -> [UUID]
}

public struct NoopFTSSearch: FTSSearch {
    public init() {}

    public func search(query: String, limit: Int) async throws -> [UUID] {
        []
    }
}
