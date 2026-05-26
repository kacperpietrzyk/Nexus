import Foundation
import NexusCore
import SwiftData
import os.log

/// Production `QuotaTracker` backed by SwiftData. Aggregates `QuotaLog` rows
/// matching `(providerRaw, day == startOfDay(now))` for daily usage; inserts
/// fresh rows on `recordUsage`.
///
/// `actor` shape serializes concurrent inserts/fetches against the shared
/// `ModelContainer` — without it, parallel `recordUsage` calls from the AIRouter
/// would race when each creates a context and saves simultaneously. Each call
/// uses a short-lived `ModelContext` (per Apple's SwiftData guidance) rather
/// than holding one for the actor's lifetime.
///
/// Local providers are unlimited by default; later phases can promote limits to
/// user-tunable Settings if needed.
public actor PersistentQuotaTracker: QuotaTracker {

    private let container: ModelContainer
    private let clock: any PersistentQuotaTrackerClock
    private let limits: [ProviderID: Int]
    private let logger = Logger(subsystem: "com.kacperpietrzyk.Nexus", category: "ai.quota")

    public init(
        modelContainer: ModelContainer,
        clock: any PersistentQuotaTrackerClock = SystemPersistentQuotaTrackerClock(),
        limits: [ProviderID: Int] = PersistentQuotaTracker.defaultLimits
    ) {
        self.container = modelContainer
        self.clock = clock
        self.limits = limits
    }

    /// Local providers absent → unlimited.
    public static let defaultLimits: [ProviderID: Int] = [:]

    public func usage(for provider: ProviderID) async -> QuotaUsage {
        let dayKey = startOfDay(clock.current())
        let providerRaw = provider.rawValue

        let predicate = #Predicate<QuotaLog> { log in
            log.providerRaw == providerRaw && log.day == dayKey
        }
        let descriptor = FetchDescriptor<QuotaLog>(predicate: predicate)

        let context = ModelContext(container)
        let logs = (try? context.fetch(descriptor)) ?? []
        let used = logs.reduce(0) { $0 + $1.totalTokens }

        return QuotaUsage(
            dailyTokensUsed: used,
            dailyTokenLimit: limits[provider]
        )
    }

    public func recordUsage(provider: ProviderID, tokens: Int) async {
        guard tokens > 0 else { return }
        let context = ModelContext(container)
        // NOTE: QuotaTracker protocol takes a single Int; we collapse it into promptTokens.
        // Phase 1b can split the protocol to (prompt, completion) when AIResponse exposes both —
        // for 1a, totalTokens-based aggregation is what we need.
        let log = QuotaLog(
            id: UUID(),
            providerRaw: provider.rawValue,
            day: startOfDay(clock.current()),
            promptTokens: tokens,
            completionTokens: 0
        )
        context.insert(log)
        do {
            try context.save()
        } catch {
            logger.error(
                "PersistentQuotaTracker: failed to save QuotaLog: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    private func startOfDay(_ date: Date) -> Date {
        Calendar.current.startOfDay(for: date)
    }
}
