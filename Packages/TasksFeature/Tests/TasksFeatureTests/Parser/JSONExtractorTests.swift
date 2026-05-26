import Foundation
import Testing

@testable import TasksFeature

@Suite("JSONExtractor")
struct JSONExtractorTests {
    @Test("extracts plain JSON object")
    func plainObject() {
        let raw = #"{"title":"Buy milk","dueAt":null}"#
        let data = JSONExtractor.firstObject(in: raw)
        #expect(data != nil)
        let parsed = try? JSONSerialization.jsonObject(with: data!) as? [String: Any]
        #expect(parsed?["title"] as? String == "Buy milk")
    }

    @Test("strips prose preamble")
    func stripsPreamble() {
        let raw = #"Sure, here is the parse: {"title":"Buy milk"}"#
        let data = JSONExtractor.firstObject(in: raw)
        let parsed = try? JSONSerialization.jsonObject(with: data!) as? [String: Any]
        #expect(parsed?["title"] as? String == "Buy milk")
    }

    @Test("strips fenced code block")
    func stripsFencedBlock() {
        let raw = """
            ```json
            {"title":"Buy milk"}
            ```
            """
        let data = JSONExtractor.firstObject(in: raw)
        let parsed = try? JSONSerialization.jsonObject(with: data!) as? [String: Any]
        #expect(parsed?["title"] as? String == "Buy milk")
    }

    @Test("respects nested braces")
    func nestedBraces() {
        let raw = #"prefix {"title":"x","extras":{"a":1,"b":2}} suffix"#
        let data = JSONExtractor.firstObject(in: raw)
        let parsed = try? JSONSerialization.jsonObject(with: data!) as? [String: Any]
        #expect(parsed?["title"] as? String == "x")
        let extras = parsed?["extras"] as? [String: Any]
        #expect(extras?["a"] as? Int == 1)
    }

    @Test("respects string-quoted braces")
    func quotedBraces() {
        let raw = #"prefix {"title":"hello { world","x":1} suffix"#
        let data = JSONExtractor.firstObject(in: raw)
        let parsed = try? JSONSerialization.jsonObject(with: data!) as? [String: Any]
        #expect(parsed?["title"] as? String == "hello { world")
    }

    @Test("returns nil when no JSON found")
    func noJSON() {
        #expect(JSONExtractor.firstObject(in: "no json here") == nil)
    }

    @Test("returns nil on unbalanced braces")
    func unbalanced() {
        #expect(JSONExtractor.firstObject(in: #"{"a":1"#) == nil)
    }
}
