import Foundation
import MLXLMCommon
import Tokenizers

/// A `MLXLMCommon.TokenizerLoader` backed by swift-transformers' `AutoTokenizer`.
///
/// mlx-swift-lm 3.31.3 ships no concrete `TokenizerLoader` in the products we link
/// (the README's `TokenizersLoader` / `#huggingFaceTokenizerLoader()` do not exist at
/// this pin), so the caller must implement the protocol. swift-transformers'
/// `Tokenizer` protocol is a near-superset of `MLXLMCommon.Tokenizer`, so the bridge
/// below is thin forwarding.
struct SwiftTransformersTokenizerLoader: MLXLMCommon.TokenizerLoader, Sendable {
    func load(from directory: URL) async throws -> any MLXLMCommon.Tokenizer {
        let inner = try await Tokenizers.AutoTokenizer.from(modelFolder: directory)
        return SwiftTransformersTokenizerAdapter(inner: inner)
    }
}

/// Adapts a swift-transformers `Tokenizers.Tokenizer` to the `MLXLMCommon.Tokenizer`
/// protocol surface.
///
/// Both protocols inherit `Sendable`, so this struct is `Sendable` without any
/// `@unchecked` escape hatch. Most methods forward 1:1; the only divergence is the
/// argument label on `decode` (`tokenIds:` vs `tokens:`).
///
/// Breadcrumb: `eosTokenId`/`bosTokenId`/`unknownTokenId` are `MLXLMCommon.Tokenizer`
/// *extension* methods, not protocol requirements, so they resolve through the default
/// `eosToken` + `convertTokenToId` path here rather than swift-transformers' native
/// id computation. If a generation never terminates, suspect that indirection first.
struct SwiftTransformersTokenizerAdapter: MLXLMCommon.Tokenizer, Sendable {
    let inner: any Tokenizers.Tokenizer

    func encode(text: String, addSpecialTokens: Bool) -> [Int] {
        inner.encode(text: text, addSpecialTokens: addSpecialTokens)
    }

    func decode(tokenIds: [Int], skipSpecialTokens: Bool) -> String {
        inner.decode(tokens: tokenIds, skipSpecialTokens: skipSpecialTokens)
    }

    func convertTokenToId(_ token: String) -> Int? {
        inner.convertTokenToId(token)
    }

    func convertIdToToken(_ id: Int) -> String? {
        inner.convertIdToToken(id)
    }

    var bosToken: String? { inner.bosToken }

    var eosToken: String? { inner.eosToken }

    var unknownToken: String? { inner.unknownToken }

    func applyChatTemplate(
        messages: [[String: any Sendable]],
        tools: [[String: any Sendable]]?,
        additionalContext: [String: any Sendable]?
    ) throws -> [Int] {
        try inner.applyChatTemplate(
            messages: messages,
            tools: tools,
            additionalContext: additionalContext
        )
    }
}
