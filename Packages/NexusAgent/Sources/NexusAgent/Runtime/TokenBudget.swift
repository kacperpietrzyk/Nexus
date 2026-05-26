import Foundation

public enum TokenBudget {
    /// Rough token estimate for routing decisions.
    public static func estimate(_ text: String) -> Int {
        guard !text.isEmpty else { return 0 }

        let scalars = text.unicodeScalars
        let nonASCII = scalars.filter { !$0.isASCII }.count
        let usesDenseEncoding = Double(nonASCII) / Double(scalars.count) > 0.2
        let charsPerToken = usesDenseEncoding ? 3.0 : 4.0

        return max(1, Int(ceil(Double(text.count) / charsPerToken)))
    }
}
