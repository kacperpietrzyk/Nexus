import Foundation
import Testing

@testable import NexusCore

@Test func scorer_zeroQueryTokens_returnsZero() {
    let s = Scorer.score(
        queryTokens: [],
        documentTermFrequencies: ["foo": 2],
        documentFrequencies: ["foo": 1],
        totalDocuments: 1
    )
    #expect(s == 0.0)
}

@Test func scorer_termNotInDocument_contributesZero() {
    let s = Scorer.score(
        queryTokens: ["bar"],
        documentTermFrequencies: ["foo": 5],
        documentFrequencies: ["foo": 1, "bar": 1],
        totalDocuments: 1
    )
    #expect(s == 0.0)
}

@Test func scorer_higherTermFrequency_yieldsHigherScore() {
    let common = Scorer.score(
        queryTokens: ["foo"],
        documentTermFrequencies: ["foo": 1],
        documentFrequencies: ["foo": 1],
        totalDocuments: 10
    )
    let frequent = Scorer.score(
        queryTokens: ["foo"],
        documentTermFrequencies: ["foo": 5],
        documentFrequencies: ["foo": 1],
        totalDocuments: 10
    )
    #expect(frequent > common)
}

@Test func scorer_rareTerms_outweighFrequentTerms() {
    let rare = Scorer.score(
        queryTokens: ["rare"],
        documentTermFrequencies: ["rare": 1],
        documentFrequencies: ["rare": 1, "common": 90],
        totalDocuments: 100
    )
    let common = Scorer.score(
        queryTokens: ["common"],
        documentTermFrequencies: ["common": 1],
        documentFrequencies: ["rare": 1, "common": 90],
        totalDocuments: 100
    )
    #expect(rare > common)
}

@Test func scorer_multipleQueryTokens_sumContributions() {
    let single = Scorer.score(
        queryTokens: ["foo"],
        documentTermFrequencies: ["foo": 1, "bar": 1],
        documentFrequencies: ["foo": 1, "bar": 1],
        totalDocuments: 5
    )
    let both = Scorer.score(
        queryTokens: ["foo", "bar"],
        documentTermFrequencies: ["foo": 1, "bar": 1],
        documentFrequencies: ["foo": 1, "bar": 1],
        totalDocuments: 5
    )
    #expect(both > single)
}
