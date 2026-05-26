import Foundation

/// Pure-function TF-IDF scorer used by `SearchIndex`.
///
/// score(q, d) = Σ_{t ∈ q ∩ d} tf(t, d) × idf(t)
///   tf(t, d)  = raw count of token `t` in document `d`
///   idf(t)    = log((N + 1) / (df(t) + 1)) + 1   (smoothed; +1 prevents div-by-zero
///                                                  on terms that appear in every doc)
///   N         = total document count
///   df(t)     = number of documents containing `t`
///
/// Phase 0d uses raw TF for simplicity. BM25 (with k1, b length-norm parameters) lands when
/// real text-bearing modules ship and the corpus average length stabilizes.
public enum Scorer {
    public static func score(
        queryTokens: [String],
        documentTermFrequencies: [String: Int],
        documentFrequencies: [String: Int],
        totalDocuments: Int
    ) -> Double {
        guard !queryTokens.isEmpty else { return 0.0 }
        var total = 0.0
        let n = Double(totalDocuments)
        for token in queryTokens {
            guard let tf = documentTermFrequencies[token], tf > 0 else { continue }
            let df = Double(documentFrequencies[token] ?? 0)
            let idf = log((n + 1.0) / (df + 1.0)) + 1.0
            total += Double(tf) * idf
        }
        return total
    }
}
