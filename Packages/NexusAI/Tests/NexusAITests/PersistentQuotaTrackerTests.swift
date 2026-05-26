import Foundation
import NexusCore
import NexusSync
import SwiftData
import Testing

@testable import NexusAI

@Suite("PersistentQuotaTracker")
struct PersistentQuotaTrackerTests {

    private func freshTracker(
        now: Date = Date(timeIntervalSince1970: 1_777_887_600)
    ) async throws -> (PersistentQuotaTracker, ModelContainer) {
        let container = try NexusModelContainer.makeInMemory()
        let clock = FixedClock(now: now)
        let tracker = PersistentQuotaTracker(
            modelContainer: container,
            clock: clock,
            limits: [.whisperKit: 100_000]
        )
        return (tracker, container)
    }

    @Test("usage on fresh tracker returns zero")
    func zeroUsage() async throws {
        let (tracker, _) = try await freshTracker()
        let usage = await tracker.usage(for: .whisperKit)
        #expect(usage.dailyTokensUsed == 0)
        #expect(usage.dailyTokenLimit == 100_000)
    }

    @Test("recordUsage inserts QuotaLog and accumulates")
    func recordUsage() async throws {
        let (tracker, container) = try await freshTracker()
        await tracker.recordUsage(provider: .whisperKit, tokens: 1_000)
        await tracker.recordUsage(provider: .whisperKit, tokens: 500)

        // Fetch via a fresh ModelContext to ensure save() actually committed.
        let context = ModelContext(container)
        let logs = try context.fetch(FetchDescriptor<QuotaLog>())
        #expect(logs.count == 2)

        let usage = await tracker.usage(for: .whisperKit)
        #expect(usage.dailyTokensUsed == 1_500)
    }

    @Test("usage from different provider is isolated")
    func providerIsolation() async throws {
        let (tracker, _) = try await freshTracker()
        await tracker.recordUsage(provider: .whisperKit, tokens: 1_000)
        let apple = await tracker.usage(for: .appleIntelligence)
        #expect(apple.dailyTokensUsed == 0)
    }

    @Test("shared container: yesterday rows excluded by day filter")
    func sharedContainerDayBoundary() async throws {
        let yesterday = Date(timeIntervalSince1970: 1_777_887_600 - 86_400)
        let today = Date(timeIntervalSince1970: 1_777_887_600)
        let container = try NexusModelContainer.makeInMemory()

        let trackerY = PersistentQuotaTracker(
            modelContainer: container,
            clock: FixedClock(now: yesterday),
            limits: [.whisperKit: 100_000]
        )
        await trackerY.recordUsage(provider: .whisperKit, tokens: 7_777)

        let trackerT = PersistentQuotaTracker(
            modelContainer: container,
            clock: FixedClock(now: today),
            limits: [.whisperKit: 100_000]
        )
        let usage = await trackerT.usage(for: .whisperKit)
        #expect(
            usage.dailyTokensUsed == 0,
            "Yesterday's QuotaLog must not contribute to today's bucket")
    }

    @Test("on-device provider has nil dailyTokenLimit")
    func onDeviceUnlimited() async throws {
        let (tracker, _) = try await freshTracker()
        let usage = await tracker.usage(for: .appleIntelligence)
        #expect(usage.dailyTokenLimit == nil)
    }

    @Test("recordUsage with zero tokens is no-op")
    func zeroRecordIsNoop() async throws {
        let (tracker, container) = try await freshTracker()
        await tracker.recordUsage(provider: .whisperKit, tokens: 0)
        let context = ModelContext(container)
        let logs = try context.fetch(FetchDescriptor<QuotaLog>())
        #expect(logs.isEmpty)
    }
}

// Test clock — local to this test target.
private struct FixedClock: PersistentQuotaTrackerClock {
    let now: Date
    func current() -> Date { now }
}
