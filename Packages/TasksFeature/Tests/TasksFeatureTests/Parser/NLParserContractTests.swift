import Foundation
import Testing

@testable import TasksFeature

@Suite("NLParser contract")
struct NLParserContractTests {
    @Test("conforming type satisfies protocol")
    func conformance() async {
        let stub = StubNLParser()
        let result = await stub.parse("hello", locale: .init(identifier: "en"), now: Date())
        #expect(result.title == "hello")
    }
}

private struct StubNLParser: NLParser {
    func parse(_ input: String, locale: Locale, now: Date, calendar: Calendar) async -> ParseResult {
        ParseResult.empty(title: input)
    }
}
