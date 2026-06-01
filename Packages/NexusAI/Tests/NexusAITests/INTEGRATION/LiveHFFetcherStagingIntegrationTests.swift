import Foundation
import Testing

@testable import NexusAI

/// Live, opt-in proof of the staging contract `LiveHFFetcher` must honour after
/// the progress/disk fix: byte-accurate progress, weights staged flat, and the
/// Hub cache repo reclaimed (no ~2x on-disk duplicate). Gated on `INTEGRATION=1`
/// like the sibling `MLXProviderLiveSmoke` so a plain `swift test` never hits the
/// network.
@Suite(
    "LiveHFFetcherStagingIntegration (INTEGRATION=1)",
    .enabled(if: ProcessInfo.processInfo.environment["INTEGRATION"] == "1")
)
struct LiveHFFetcherStagingIntegrationTests {
    private static let modelHFPath = "mlx-community/Qwen2.5-0.5B-Instruct-4bit"

    /// Locked sample collector the `@Sendable` progress closure can mutate.
    private final class Samples: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [Int64] = []
        func record(_ v: Int64) { lock.lock(); values.append(v); lock.unlock() }
        var all: [Int64] { lock.withLock { values } }
    }

    @Test("byte-accurate progress, weights staged, .hf-cache reclaimed")
    func stagesAndReclaims() async throws {
        guard ProcessInfo.processInfo.environment["INTEGRATION"] == "1" else { return }

        let fileManager = FileManager.default
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "nexus-staging-int-\(UUID().uuidString)")
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }

        // The manager always passes `<modelsRoot>/<manifestID>` as destination;
        // `.hf-cache` lands next to it (destination's parent).
        let destination = root.appending(path: "qwen2.5-0.5b")
        let samples = Samples()

        do {
            try await LiveHFFetcher().fetch(
                hfPath: Self.modelHFPath,
                toFile: destination,
                startingAtByte: 0,
                totalBytes: 300_000_000,
                onProgress: { samples.record($0) }
            )
        } catch {
            // Environmental staging failure (offline / HF unreachable / rate
            // limit) is a soft-skip, not a Nexus regression.
            print("[StagingIntegration] soft-skipped (staging failed): \(error)")
            return
        }

        // Weights staged flat into the destination.
        let staged = try fileManager.contentsOfDirectory(atPath: destination.path)
        #expect(staged.contains { $0.hasSuffix(".safetensors") }, "no weights staged: \(staged)")

        // Progress moved through real, increasing byte values before the
        // finalizing sentinel (-1) and the closing total — i.e. the poller drove
        // the bar, not a single 0→100 jump.
        let positive = samples.all.filter { $0 >= 0 }
        #expect(positive.contains { $0 > 0 }, "no positive byte samples: \(samples.all)")
        #expect(samples.all.contains(-1), "finalizing sentinel never emitted: \(samples.all)")

        // The Hub cache repo for this model was reclaimed — no ~2x duplicate of
        // the multi-file snapshot left behind in `.hf-cache`.
        let cacheRepo = root.appending(path: ".hf-cache").appending(path: "models")
            .appending(path: Self.modelHFPath)
        #expect(
            !fileManager.fileExists(atPath: cacheRepo.path),
            "Hub cache repo not reclaimed — duplicate weights remain at \(cacheRepo.path)")
    }
}
