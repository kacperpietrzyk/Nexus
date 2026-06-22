import Foundation

/// Pure, socket-free retry policy for loading the tool list.
///
/// The headline reliability bug ("connected but zero tools at startup") is a
/// race: at `ListTools` time the app may still be launching, so a single load
/// attempt returns an error or an empty manifest, which then gets cached and
/// never recovered. This unit makes the load decision explicit and testable:
///
/// - Retries `attempt` with bounded backoff until it yields a NON-EMPTY result.
/// - Treats an empty result as "app not ready yet" (the app ships 200+ tools,
///   so empty is never a legitimate steady state) and keeps retrying.
/// - On budget exhaustion THROWS the last error (or `emptyManifest` if every
///   attempt merely returned empty) so the caller never silently caches `[]`.
///
/// The socket dependency is injected as `attempt`, and time is injected as
/// `sleep`, so the policy is fully unit-testable without a live app.
enum ToolLoadRetry {
    /// Thrown when every attempt within the budget returned an empty list
    /// (app reachable but manifest empty / not yet populated).
    static let emptyManifest = MCPError(
        code: -32_003,
        message: "Nexus.app returned no tools yet. It may still be starting up."
    )

    /// Run `attempt` repeatedly until it returns a non-empty array or the total
    /// elapsed budget is exhausted.
    ///
    /// - Parameters:
    ///   - budget: total wall-clock budget in seconds across all attempts.
    ///   - initialDelay: delay before the first retry (seconds).
    ///   - maxDelay: cap on the backoff delay (seconds).
    ///   - now: monotonic clock source (seconds); injectable for tests.
    ///   - sleep: async sleep (seconds); injectable for tests.
    ///   - attempt: the load operation; may throw or return `[]` when not ready.
    /// - Returns: a guaranteed non-empty `[Element]`.
    /// - Throws: the last attempt error, or `emptyManifest` if all attempts were empty.
    static func run<Element>(
        budget: Double,
        initialDelay: Double = 0.25,
        maxDelay: Double = 1.0,
        now: () -> Double = { Date().timeIntervalSinceReferenceDate },
        sleep: (Double) async throws -> Void = { try await Task.sleep(for: .seconds($0)) },
        attempt: sending () async throws -> [Element]
    ) async throws -> [Element] {
        let start = now()
        var delay = initialDelay
        var lastError: Error?

        while true {
            do {
                let result = try await attempt()
                if !result.isEmpty {
                    return result
                }
                // Empty = app not ready; remember nothing-but-empty so we throw
                // a meaningful error if the budget runs out.
                lastError = nil
            } catch {
                lastError = error
            }

            // Out of budget? Stop and surface the failure instead of caching [].
            let elapsed = now() - start
            if elapsed + delay >= budget {
                throw lastError ?? emptyManifest
            }

            try await sleep(delay)
            delay = min(delay * 2, maxDelay)
        }
    }
}
