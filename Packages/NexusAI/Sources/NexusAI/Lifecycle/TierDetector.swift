import Foundation

/// The platform family to consider when computing a device tier.
public enum TierDetectorPlatform: Sendable {
    case macOS, iOS, watchOS
}

/// The recommended model IDs for a device tier.
///
/// `nil` means "no suitable on-device model for this purpose on this hardware";
/// the caller should fall back to Apple Foundation Models or cloud routing.
public struct DeviceTier: Sendable, Equatable {
    public let recommendedChat: String?
    public let recommendedEmbedder: String?

    public init(recommendedChat: String?, recommendedEmbedder: String?) {
        self.recommendedChat = recommendedChat
        self.recommendedEmbedder = recommendedEmbedder
    }
}

/// Pure-deterministic device-tier recommender.
///
/// ``recommend(platform:physicalMemoryGB:availableStorageGB:)`` is a pure
/// function — no side effects, safe to call from any context.
/// ``detectCurrent()`` wires it to `ProcessInfo` and `FileManager` for
/// production use.
public enum TierDetector {

    // MARK: - Public API

    /// Returns the recommended on-device model IDs for the given hardware profile.
    ///
    /// Storage thresholds use a 2× buffer (`modelSizeGB * 2.0`) so the device
    /// can hold both the downloaded archive and the extracted weights without
    /// running out of space.
    public static func recommend(
        platform: TierDetectorPlatform,
        physicalMemoryGB: Int,
        availableStorageGB: Int
    ) -> DeviceTier {
        let e5LargeID = ModelCatalog.defaultEmbedderID
        let embedderFits = availableStorageGB >= 4

        switch platform {
        case .watchOS:
            return DeviceTier(recommendedChat: nil, recommendedEmbedder: nil)

        case .iOS:
            // Chat targets 8 GB-class iPhones (e4b ~4.5 GB). The RAM floor is `>= 7`,
            // not `>= 8`, on purpose: iOS under-reports `physicalMemory` by an amount
            // we cannot measure ahead of time, so an 8 GB device can convert to 7 even
            // after rounding. No iOS device ships with 7 GB, so `>= 7` still cleanly
            // excludes the 6 GB class (which rounds to ≤ 6) while surviving even a heavy
            // ~1.5 GB under-report on an 8 GB device — making the tier independent of the
            // exact reported value rather than betting on a narrow rounding margin.
            guard physicalMemoryGB >= 7, availableStorageGB >= 6 else {
                return DeviceTier(
                    recommendedChat: nil,
                    recommendedEmbedder: embedderFits ? e5LargeID : nil)
            }
            return DeviceTier(
                recommendedChat: storageAllows(modelSizeGB: 4.5, availableGB: availableStorageGB)
                    ? "gemma-4-e4b" : nil,
                recommendedEmbedder: embedderFits ? e5LargeID : nil)

        case .macOS:
            guard physicalMemoryGB >= 16, availableStorageGB >= 8 else {
                return DeviceTier(
                    recommendedChat: nil,
                    recommendedEmbedder: embedderFits ? e5LargeID : nil)
            }
            // Two loadable Gemma-4 tiers. ≥24 GB RAM gets the dense 12B
            // (`model_type: gemma4_unified`, registered in mlx-swift-lm 3.31.4 onto the
            // existing `Gemma4Model`; ~11 GB resident at qat-4bit). It replaced the MoE
            // 26B/A4B, which was removed from the catalog entirely — a dense 12B plausibly
            // beats a 26B MoE with only 4B active at lower RAM, and dropping it sheds a
            // 14.6 GB manual-override option for a lightweight helper that never needed it.
            // (Any already-downloaded 26B is reclaimed by ModelStoreReconciler as a
            // non-canonical orphan, independent of catalog membership.) 16–24 GB gets the
            // elastic E4B (~4.9 GB). The qat-4bit 12B is 11 GB, not the ~7 GB once assumed,
            // so it does NOT fit 16 GB comfortably (~69% of RAM) — hence still a ≥24 GB
            // gate and no single-tier collapse. The assistant is a lightweight in-app
            // helper (recommendations, calendar, task breakdown), not a heavy reasoner —
            // E4B is sufficient on 16 GB.
            if physicalMemoryGB >= 24, storageAllows(modelSizeGB: 11.0, availableGB: availableStorageGB) {
                return DeviceTier(
                    recommendedChat: "gemma-4-12b",
                    recommendedEmbedder: e5LargeID)
            }
            if storageAllows(modelSizeGB: 4.9, availableGB: availableStorageGB) {
                return DeviceTier(
                    recommendedChat: "gemma-4-e4b",
                    recommendedEmbedder: e5LargeID)
            }
            return DeviceTier(
                recommendedChat: nil,
                recommendedEmbedder: embedderFits ? e5LargeID : nil)
        }
    }

    /// Detects the current device's tier using `ProcessInfo` for RAM and
    /// `FileManager` for available storage.
    public static func detectCurrent() -> DeviceTier {
        let platform: TierDetectorPlatform = {
            #if os(watchOS)
            return .watchOS
            #elseif os(iOS)
            return .iOS
            #else
            return .macOS
            #endif
        }()
        let ramGB = gigabytes(fromBytes: ProcessInfo.processInfo.physicalMemory)
        let availableGB = (try? FileManager.default.availableCapacityGBForAppSupport()) ?? 0
        return recommend(platform: platform, physicalMemoryGB: ramGB, availableStorageGB: availableGB)
    }

    /// Converts a raw `physicalMemory` byte count to whole gigabytes by ROUNDING,
    /// not truncating.
    ///
    /// iOS reports `physicalMemory` slightly UNDER the nominal installed RAM (the
    /// kernel reserves a slice), so an 8 GB iPhone returns ~7.98 GiB. The old
    /// `Int(bytes / 1_073_741_824)` floored that to 7, which fell below the (then
    /// `>= 8`) iOS chat tier and silently dropped the assistant model on every 8 GB
    /// iPhone (the embedder, gated at only `>= 4 GB`, still passed — so Settings
    /// showed a "Search model" row but no "Assistant model" row). Rounding gives a
    /// truthful figure for the "Device memory: N GB" label and a sane tiering input.
    ///
    /// Rounding is NOT load-bearing for the chat-tier decision on its own — that
    /// would only hold if the under-report stays under 0.5 GiB, which we cannot
    /// guarantee. The robustness comes from the `>= 7` iOS RAM floor (see the iOS
    /// branch of `recommend`), which tolerates a much larger under-report. Macs
    /// report exact binary RAM, so rounding is a no-op there.
    public static func gigabytes(fromBytes bytes: UInt64) -> Int {
        Int((Double(bytes) / 1_073_741_824).rounded())
    }

    // MARK: - Helpers

    /// Returns `true` when twice the model's on-disk size fits within available
    /// storage (download + extracted weights).
    private static func storageAllows(modelSizeGB: Double, availableGB: Int) -> Bool {
        Double(availableGB) >= modelSizeGB * 2.0
    }
}

// MARK: - FileManager extension

extension FileManager {
    /// Available capacity in whole gigabytes under the Application Support
    /// directory, using the important-usage capacity key so iOS/macOS report
    /// the capacity that would actually be accessible for large downloads.
    ///
    /// `public` so the NexusUI `ManageModelsSection` storage bar can compute
    /// the device's remaining free space without duplicating the
    /// volume-capacity resource-key logic (Task 27).
    public func availableCapacityGBForAppSupport() throws -> Int {
        guard let support = urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        else { return 0 }
        let values = try support.resourceValues(forKeys: [
            .volumeAvailableCapacityForImportantUsageKey
        ])
        guard let bytes = values.volumeAvailableCapacityForImportantUsage else { return 0 }
        return Int(bytes / 1_073_741_824)
    }
}
