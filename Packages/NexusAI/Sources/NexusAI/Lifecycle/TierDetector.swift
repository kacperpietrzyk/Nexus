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
            guard physicalMemoryGB >= 8, availableStorageGB >= 6 else {
                return DeviceTier(
                    recommendedChat: nil,
                    recommendedEmbedder: embedderFits ? e5LargeID : nil)
            }
            if physicalMemoryGB >= 16 {
                return DeviceTier(
                    recommendedChat: storageAllows(modelSizeGB: 3.2, availableGB: availableStorageGB)
                        ? "qwen3.5-4b-4bit" : nil,
                    recommendedEmbedder: embedderFits ? e5LargeID : nil)
            }
            return DeviceTier(
                recommendedChat: storageAllows(modelSizeGB: 3.0, availableGB: availableStorageGB)
                    ? "gemma-4-e4b-it-4bit" : nil,
                recommendedEmbedder: embedderFits ? e5LargeID : nil)

        case .macOS:
            guard physicalMemoryGB >= 16, availableStorageGB >= 8 else {
                return DeviceTier(
                    recommendedChat: nil,
                    recommendedEmbedder: embedderFits ? e5LargeID : nil)
            }
            let fits27b = storageAllows(modelSizeGB: 15.8, availableGB: availableStorageGB)
            if physicalMemoryGB >= 64, fits27b {
                return DeviceTier(
                    recommendedChat: "qwen3.5-27b-4bit",
                    recommendedEmbedder: e5LargeID)
            }
            let fits9b = storageAllows(modelSizeGB: 5.8, availableGB: availableStorageGB)
            if physicalMemoryGB >= 32, fits9b {
                return DeviceTier(
                    recommendedChat: "qwen3.5-9b-4bit",
                    recommendedEmbedder: e5LargeID)
            }
            if storageAllows(modelSizeGB: 3.2, availableGB: availableStorageGB) {
                return DeviceTier(
                    recommendedChat: "qwen3.5-4b-4bit",
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
        let ramGB = Int(ProcessInfo.processInfo.physicalMemory / 1_073_741_824)
        let availableGB = (try? FileManager.default.availableCapacityGBForAppSupport()) ?? 0
        return recommend(platform: platform, physicalMemoryGB: ramGB, availableStorageGB: availableGB)
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
