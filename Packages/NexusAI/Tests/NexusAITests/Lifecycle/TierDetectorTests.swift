import Foundation
import Testing

@testable import NexusAI

// NOTE: Task 11 (2026-06-14) — all Qwen IDs replaced by Gemma IDs.
// Mac now has a single model (gemma-4.5-12b-1m) for all RAM tiers that meet
// the storage floor; iOS always recommends gemma-4-e4b when hardware qualifies.

@Test func macStudioRecommendsGemma12B() {
    let tier = TierDetector.recommend(platform: .macOS, physicalMemoryGB: 64, availableStorageGB: 200)
    #expect(tier.recommendedChat == "gemma-4.5-12b-1m")
    #expect(tier.recommendedEmbedder == "multilingual-e5-large")
}

@Test func macMidTierRecommendsGemma12B() {
    let tier = TierDetector.recommend(platform: .macOS, physicalMemoryGB: 36, availableStorageGB: 50)
    #expect(tier.recommendedChat == "gemma-4.5-12b-1m")
}

@Test func macLowRAMRecommendsGemma12B() {
    let tier = TierDetector.recommend(platform: .macOS, physicalMemoryGB: 16, availableStorageGB: 20)
    #expect(tier.recommendedChat == "gemma-4.5-12b-1m")
}

@Test func lowStorageFallsBackToAppleFM() {
    let tier = TierDetector.recommend(platform: .macOS, physicalMemoryGB: 64, availableStorageGB: 4)
    #expect(tier.recommendedChat == nil)
    #expect(tier.recommendedEmbedder == "multilingual-e5-large")  // 1.1 GB fits
}

@Test func iPhoneProRecommendsGemma4E4B() {
    let tier = TierDetector.recommend(platform: .iOS, physicalMemoryGB: 8, availableStorageGB: 12)
    #expect(tier.recommendedChat == "gemma-4-e4b")
}

@Test func iPadProM4RecommendsGemma4E4B() {
    let tier = TierDetector.recommend(platform: .iOS, physicalMemoryGB: 16, availableStorageGB: 30)
    #expect(tier.recommendedChat == "gemma-4-e4b")
}

@Test func watchOSGetsNoMLX() {
    let tier = TierDetector.recommend(platform: .watchOS, physicalMemoryGB: 4, availableStorageGB: 8)
    #expect(tier.recommendedChat == nil)
    #expect(tier.recommendedEmbedder == nil)
}

/// Every chat/embedder ID `recommend` can return must resolve against the
/// bundled catalog — guards against the #15-class hallucinated-name bug where
/// the recommended ID (e.g. a stray `-instruct` infix) silently fails the
/// exact-match catalog lookup and drops the chat model from the download plan.
@Test func recommendedIDsAllResolveAgainstCatalog() throws {
    let catalog = try ModelCatalog.loadDefault()
    let knownIDs = Set(catalog.chat.map(\.id)).union(catalog.embedders.map(\.id))

    struct Profile {
        let platform: TierDetectorPlatform
        let ramGB: Int
        let storageGB: Int
    }
    let profiles: [Profile] = [
        Profile(platform: .macOS, ramGB: 64, storageGB: 200),
        Profile(platform: .macOS, ramGB: 36, storageGB: 50),
        Profile(platform: .macOS, ramGB: 16, storageGB: 20),
        Profile(platform: .iOS, ramGB: 16, storageGB: 30),
        Profile(platform: .iOS, ramGB: 8, storageGB: 12),
    ]
    for profile in profiles {
        let tier = TierDetector.recommend(
            platform: profile.platform,
            physicalMemoryGB: profile.ramGB,
            availableStorageGB: profile.storageGB)
        if let chat = tier.recommendedChat {
            #expect(knownIDs.contains(chat), "chat ID \(chat) not in catalog")
        }
        if let embedder = tier.recommendedEmbedder {
            #expect(knownIDs.contains(embedder), "embedder ID \(embedder) not in catalog")
        }
    }
}
