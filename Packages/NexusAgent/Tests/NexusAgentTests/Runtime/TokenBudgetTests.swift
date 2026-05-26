import Testing

@testable import NexusAgent

struct TokenBudgetTests {
    @Test func emptyTextCountsAsZero() {
        #expect(TokenBudget.estimate("") == 0)
    }

    @Test func tokenBudgetCountsEnglish() {
        let count = TokenBudget.estimate("Hello world this is plain English.")

        #expect(count >= 7 && count <= 12)
    }

    @Test func tokenBudgetCountsPolishAsMostlyLatin() {
        let count = TokenBudget.estimate("Zaplanuj jutro z uwzględnieniem priorytetów.")

        #expect(count >= 10 && count <= 18)
    }

    @Test func tokenBudgetUsesDenseEncodingForMostlyNonASCII() {
        #expect(TokenBudget.estimate("ąćęłńóśźż") == 3)
    }

    @Test func nonEmptyShortTextHasMinimumOneToken() {
        #expect(TokenBudget.estimate("a") == 1)
    }

    @Test func tokenBudgetSumsParts() {
        let parts = ["abc", "defghij", "klmnopqrstuv"]
        let direct = parts.map(TokenBudget.estimate).reduce(0, +)
        let joined = TokenBudget.estimate(parts.joined(separator: ""))

        #expect(abs(direct - joined) <= 2)
    }
}
