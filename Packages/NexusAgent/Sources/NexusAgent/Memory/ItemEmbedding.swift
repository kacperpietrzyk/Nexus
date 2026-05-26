import Foundation
import SwiftData

@Model
public final class ItemEmbedding {
    public var itemID: UUID
    public var id: UUID
    public var kind: String
    public var vector: Data
    public var textHash: String
    public var language: String
    public var vectorDimension: Int
    public var updatedAt: Date

    public init(
        itemID: UUID,
        kind: String,
        vector: Data,
        textHash: String,
        language: String = "multilingual",
        vectorDimension: Int = 512,
        updatedAt: Date = .now
    ) {
        self.itemID = itemID
        self.id = itemID
        self.kind = kind
        self.vector = vector
        self.textHash = textHash
        self.language = language
        self.vectorDimension = vectorDimension
        self.updatedAt = updatedAt
    }
}
