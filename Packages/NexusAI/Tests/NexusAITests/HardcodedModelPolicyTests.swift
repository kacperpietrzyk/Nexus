import Foundation
import Testing

@testable import NexusAI

@Suite struct HardcodedModelPolicyTests {
    private func catalog() throws -> ModelCatalog.CatalogDoc { try ModelCatalog.loadDefault() }

    @Test func resolvesChatAndEmbedderFromTierAndCatalog() throws {
        let cat = try catalog()
        let tier = DeviceTier(recommendedChat: cat.chat.first!.id, recommendedEmbedder: ModelCatalog.defaultEmbedderID)
        let policy = DefaultHardcodedModelPolicy(catalog: cat, tier: tier)
        let set = policy.resolve()
        #expect(set.chatHFPath == cat.chat.first!.hfPath)
        #expect(set.embedderHFPath == cat.embedders.first { $0.id == ModelCatalog.defaultEmbedderID }!.hfPath)
        #expect(set.chatContextLength == cat.chat.first!.contextLength)
        #expect(set.chatManifestID == cat.chat.first!.id)
    }
}
