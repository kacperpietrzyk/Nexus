import Foundation
import Testing

@testable import NexusMCPSidecar

@Suite("ToolLoadRetry policy")
struct ToolLoadRetryTests {
    /// A deterministic injectable clock + sleep so tests never wait real time.
    private final class FakeClock: @unchecked Sendable {
        private(set) var seconds: Double = 0
        func now() -> Double { seconds }
        func sleep(_ duration: Double) async throws { seconds += duration }
    }

    @Test("returns the first non-empty result and stops retrying")
    func stopsOnFirstNonEmpty() async throws {
        let clock = FakeClock()
        var calls = 0

        let result = try await ToolLoadRetry.run(
            budget: 10,
            now: clock.now,
            sleep: clock.sleep
        ) { () async throws -> [Int] in
            calls += 1
            return [1, 2, 3]
        }

        #expect(result == [1, 2, 3])
        #expect(calls == 1)
    }

    @Test("retries past empty results until a non-empty result appears")
    func retriesPastEmpty() async throws {
        let clock = FakeClock()
        var calls = 0

        let result = try await ToolLoadRetry.run(
            budget: 10,
            now: clock.now,
            sleep: clock.sleep
        ) { () async throws -> [Int] in
            calls += 1
            return calls < 3 ? [] : [42]
        }

        #expect(result == [42])
        #expect(calls == 3)
    }

    @Test("retries past thrown errors until a non-empty result appears")
    func retriesPastErrors() async throws {
        let clock = FakeClock()
        var calls = 0

        let result = try await ToolLoadRetry.run(
            budget: 10,
            now: clock.now,
            sleep: clock.sleep
        ) { () async throws -> [Int] in
            calls += 1
            if calls < 2 { throw SidecarErrors.appNotRunning }
            return [7]
        }

        #expect(result == [7])
        #expect(calls == 2)
    }

    @Test("throws the last error on persistent failure — never returns empty")
    func throwsOnPersistentFailure() async throws {
        let clock = FakeClock()
        var calls = 0

        await #expect(throws: MCPError.self) {
            try await ToolLoadRetry.run(
                budget: 3,
                now: clock.now,
                sleep: clock.sleep
            ) { () async throws -> [Int] in
                calls += 1
                throw SidecarErrors.appNotRunning
            }
        }

        // It actually retried more than once within the budget.
        #expect(calls > 1)
    }

    @Test("throws emptyManifest when every attempt only ever returned empty")
    func throwsEmptyManifestOnAllEmpty() async throws {
        let clock = FakeClock()

        await #expect(throws: MCPError.self) {
            try await ToolLoadRetry.run(
                budget: 3,
                now: clock.now,
                sleep: clock.sleep
            ) { () async throws -> [Int] in
                []
            }
        }
    }

    @Test("respects the total time budget instead of retrying forever")
    func respectsBudget() async throws {
        let clock = FakeClock()
        var calls = 0

        try? await ToolLoadRetry.run(
            budget: 3,
            initialDelay: 0.25,
            maxDelay: 1.0,
            now: clock.now,
            sleep: clock.sleep
        ) { () async throws -> [Int] in
            calls += 1
            return []
        }

        // Backoff 0.25,0.5,1,1 => stops once elapsed+nextDelay >= 3s.
        #expect(clock.seconds <= 3)
        #expect(calls >= 2)
    }
}
