import Foundation
import Testing

@testable import NexusAI

// NOTE: Task 11 (2026-06-14) — all Qwen IDs replaced by Gemma IDs.
// 2026-06-16 — Mac chat corrected from the fabricated `gemma-4.5-12b-1m`
// (HF 401) to a RAM-tiered pair of loadable Gemma-4 models (both `model_type:
// gemma4`): ≥24 GB → `gemma-4-26b-a4b` (MoE, ~14.6 GB resident); 16–24 GB →
// `gemma-4-e4b` (elastic, ~4.9 GB). The dense 12B (`gemma4_unified`) is absent
// from the pinned mlx-swift-lm registry — would download but never load — so it
// is deliberately not used until Swift-runtime support lands.

@Test func macHighRAMRecommends26BA4B() {
    let tier = TierDetector.recommend(platform: .macOS, physicalMemoryGB: 64, availableStorageGB: 200)
    #expect(tier.recommendedChat == "gemma-4-26b-a4b")
    #expect(tier.recommendedEmbedder == "multilingual-e5-large")
}

@Test func mac24GBBoundaryGets26BA4B() {
    let tier = TierDetector.recommend(platform: .macOS, physicalMemoryGB: 24, availableStorageGB: 50)
    #expect(tier.recommendedChat == "gemma-4-26b-a4b")
}

@Test func macLowRAMRecommendsE4B() {
    // 16–24 GB RAM is below the 26B/A4B floor → the elastic E4B that fits.
    let tier = TierDetector.recommend(platform: .macOS, physicalMemoryGB: 16, availableStorageGB: 20)
    #expect(tier.recommendedChat == "gemma-4-e4b")
}

@Test func macHighRAMLowStorageFallsToE4B() {
    // ≥24 GB RAM but not enough disk for the 26B (needs ~29 GB) → E4B, not nil.
    let tier = TierDetector.recommend(platform: .macOS, physicalMemoryGB: 32, availableStorageGB: 15)
    #expect(tier.recommendedChat == "gemma-4-e4b")
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

// MARK: - Byte→GB conversion (the shipped iOS bug)

/// iOS reports `physicalMemory` a little UNDER nominal installed RAM (the kernel
/// reserves a slice), so an 8 GB iPhone returns ~7.98 GiB. `Int(bytes / 1 GiB)`
/// floors that to 7, dropping the device below the `>= 8` chat tier — the exact
/// reason an iPhone 16 Pro showed the embedder ("Search model") but no assistant
/// model. Rounding to nearest GB maps it back to 8. RAM classes are ≥1 GB apart
/// (4/6/8/12/16/24/32), so nearest-GB rounding never misclassifies.
@Test func eightGBDeviceUnderReportRoundsTo8NotFlooredTo7() {
    // iPhone 16 Pro–class reported value: 8 GiB minus a ~17 MiB kernel carve-out.
    let reported: UInt64 = 8_589_934_592 - 18_616_320  // ≈ 7.98 GiB
    #expect(TierDetector.gigabytes(fromBytes: reported) == 8)
}

@Test func sixGBDeviceUnderReportRoundsTo6() {
    let reported: UInt64 = 6_442_450_944 - 16_000_000  // ≈ 5.99 GiB
    #expect(TierDetector.gigabytes(fromBytes: reported) == 6)
}

@Test func exactBinaryGiBValuesAreUnchanged() {
    #expect(TierDetector.gigabytes(fromBytes: 8_589_934_592) == 8)  // Macs report exact
    #expect(TierDetector.gigabytes(fromBytes: 17_179_869_184) == 16)
    #expect(TierDetector.gigabytes(fromBytes: 25_769_803_776) == 24)
}

/// End-to-end: the under-reported 8 GB byte count, once converted, must yield the
/// iOS chat model — proving the floor was what dropped it.
@Test func eightGBUnderReportYieldsChatModel() {
    let gb = TierDetector.gigabytes(fromBytes: 8_589_934_592 - 18_616_320)
    let tier = TierDetector.recommend(platform: .iOS, physicalMemoryGB: gb, availableStorageGB: 20)
    #expect(tier.recommendedChat == "gemma-4-e4b")
}

// The `>= 7` iOS RAM floor (not `>= 8`) is what makes the fix independent of the
// exact under-report magnitude. These two lock that margin from both sides: an
// 8 GB device must keep chat even if it converts as low as 7, and a 6 GB device
// must still be excluded. No iOS device ships with 7 GB, so 7 is a safe divider.
@Test func iOSEightGBConvertingAsLowAs7StillGetsChat() {
    // Worst-case heavy under-report on an 8 GB device → rounds to 7.
    let tier = TierDetector.recommend(platform: .iOS, physicalMemoryGB: 7, availableStorageGB: 20)
    #expect(tier.recommendedChat == "gemma-4-e4b")
}

@Test func iOSSixGBStillExcludedFromChat() {
    // A 6 GB iPhone (rounds to ≤ 6) must NOT be offered the e4b chat model.
    let tier = TierDetector.recommend(platform: .iOS, physicalMemoryGB: 6, availableStorageGB: 20)
    #expect(tier.recommendedChat == nil)
    #expect(tier.recommendedEmbedder == "multilingual-e5-large")  // 1.1 GB embedder still fits
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
