// Packages/InboxShell/Sources/InboxShell/Feed/FeedRegistry.swift
import CoreData
import Foundation
import SwiftData

public actor FeedRegistry {
    public static let shared = FeedRegistry()

    /// State for one feed key, supplied by the host (reads `FeedItemStateRepository`).
    public struct State: Sendable {
        public var seenAt: Date?
        public var dismissedAt: Date?
        public var snoozedUntil: Date?
        public init(seenAt: Date?, dismissedAt: Date?, snoozedUntil: Date?) {
            self.seenAt = seenAt
            self.dismissedAt = dismissedAt
            self.snoozedUntil = snoozedUntil
        }
    }

    private var projectors: [FeedProjector] = []
    private var stateProvider: (@Sendable () async -> [String: State])?
    private var cached: [FeedItem]?
    private nonisolated(unsafe) var storeObservers: [NSObjectProtocol] = []
    private var didStartObserving = false

    public init() {}

    deinit { for o in storeObservers { NotificationCenter.default.removeObserver(o) } }

    public func register(_ projector: FeedProjector) {
        projectors.append(projector)
        cached = nil
    }

    public func setStateProvider(_ provider: @escaping @Sendable () async -> [String: State]) {
        stateProvider = provider
        cached = nil
    }

    public func invalidate() { cached = nil }

    private func startObservingIfNeeded() {
        guard !didStartObserving else { return }
        didStartObserving = true
        let names: [Notification.Name] = [ModelContext.didSave, .NSPersistentStoreRemoteChange]
        storeObservers = names.map { name in
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: nil) { [weak self] _ in
                guard let self else { return }
                Task { await self.invalidate() }
            }
        }
    }

    /// Projected + state-joined + visible items, newest `createdAt` first.
    public func items(now: Date) async throws -> [FeedItem] {
        startObservingIfNeeded()
        let states = await stateProvider?() ?? [:]
        var merged: [FeedItem] = []
        for projector in projectors {
            for var item in try await projector.project() {
                if let s = states[item.key] {
                    item.seenAt = s.seenAt
                    item.dismissedAt = s.dismissedAt
                    item.snoozedUntil = s.snoozedUntil
                }
                if item.isVisible(now: now) { merged.append(item) }
            }
        }
        return merged.sorted { lhs, rhs in
            if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
            return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }
    }

    /// Unread = visible, unseen, non-bridge.
    public func unreadCount(now: Date) async throws -> Int {
        try await items(now: now).filter { $0.stream != .bridge && $0.isUnread(now: now) }.count
    }
}
