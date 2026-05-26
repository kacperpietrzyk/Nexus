import Foundation
import Testing

@testable import NexusAI

@Test func macStudioRecommendsQwen27B() {
    let tier = TierDetector.recommend(platform: .macOS, physicalMemoryGB: 64, availableStorageGB: 200)
    #expect(tier.recommendedChat == "qwen3.5-27b-instruct-4bit")
    #expect(tier.recommendedEmbedder == "multilingual-e5-large")
}
@Test func macMidTierRecommendsQwen9B() {
    let tier = TierDetector.recommend(platform: .macOS, physicalMemoryGB: 36, availableStorageGB: 50)
    #expect(tier.recommendedChat == "qwen3.5-9b-instruct-4bit")
}
@Test func macLowRAMRecommendsQwen4B() {
    let tier = TierDetector.recommend(platform: .macOS, physicalMemoryGB: 16, availableStorageGB: 20)
    #expect(tier.recommendedChat == "qwen3.5-4b-instruct-4bit")
}
@Test func lowStorageFallsBackToAppleFM() {
    let tier = TierDetector.recommend(platform: .macOS, physicalMemoryGB: 64, availableStorageGB: 4)
    #expect(tier.recommendedChat == nil)
    #expect(tier.recommendedEmbedder == "multilingual-e5-large")  // 1.1 GB fits
}
@Test func iPhoneProRecommendsGemma4() {
    let tier = TierDetector.recommend(platform: .iOS, physicalMemoryGB: 8, availableStorageGB: 12)
    #expect(tier.recommendedChat == "gemma-4-e4b-it-4bit")
}
@Test func iPadProM4RecommendsQwen4B() {
    let tier = TierDetector.recommend(platform: .iOS, physicalMemoryGB: 16, availableStorageGB: 30)
    #expect(tier.recommendedChat == "qwen3.5-4b-instruct-4bit")
}
@Test func watchOSGetsNoMLX() {
    let tier = TierDetector.recommend(platform: .watchOS, physicalMemoryGB: 4, availableStorageGB: 8)
    #expect(tier.recommendedChat == nil)
    #expect(tier.recommendedEmbedder == nil)
}
