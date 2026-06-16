import Foundation
import Testing

@testable import NexusAI

@Suite struct TierDetectorGemmaTests {
    @Test func iOSRecommendsE4B() {
        let tier = TierDetector.recommend(platform: .iOS, physicalMemoryGB: 8, availableStorageGB: 64)
        #expect(tier.recommendedChat == "gemma-4-e4b")
        #expect(tier.recommendedEmbedder == "multilingual-e5-large")
    }

    @Test func macRecommends26BA4B() {
        let tier = TierDetector.recommend(platform: .macOS, physicalMemoryGB: 32, availableStorageGB: 256)
        #expect(tier.recommendedChat == "gemma-4-26b-a4b")
    }

    @Test func watchGetsNoChat() {
        #expect(TierDetector.recommend(platform: .watchOS, physicalMemoryGB: 2, availableStorageGB: 16).recommendedChat == nil)
    }
}
