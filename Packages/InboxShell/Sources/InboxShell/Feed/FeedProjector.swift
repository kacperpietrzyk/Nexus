// Packages/InboxShell/Sources/InboxShell/Feed/FeedProjector.swift
import Foundation

/// A source of feed rows for one stream. Returns items WITHOUT state joined —
/// `FeedRegistry` joins `FeedItemState` by `key`. Sendable so it can be held by
/// the `FeedRegistry` actor; conformers do their data access on `@MainActor`.
public protocol FeedProjector: Sendable {
    var stream: FeedStream { get }
    func project() async throws -> [FeedItem]
}
