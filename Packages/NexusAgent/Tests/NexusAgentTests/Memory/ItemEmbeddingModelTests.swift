import Foundation
import Testing

@testable import NexusAgent

@Test func embeddingDefaults() {
    let id = UUID()
    let vector = Data(count: 512 * MemoryLayout<Float>.size)
    let before = Date()
    let emb = ItemEmbedding(
        itemID: id,
        kind: "task",
        vector: vector,
        textHash: "abc"
    )
    let after = Date()
    #expect(emb.itemID == id)
    #expect(emb.id == id)
    #expect(emb.vectorDimension == 512)
    #expect(emb.language == "multilingual")
    #expect(emb.updatedAt >= before)
    #expect(emb.updatedAt <= after)
}
