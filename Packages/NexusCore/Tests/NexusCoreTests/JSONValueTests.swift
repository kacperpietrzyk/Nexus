import Foundation
import NexusCore
import Testing

struct JSONValueTests {
    @Test
    func primitiveRoundTrip() throws {
        let values: [JSONValue] = [
            .null,
            .bool(true),
            .int(42),
            .double(3.5),
            .string("nexus"),
            .array([.string("a"), .int(1)]),
            .object(["name": .string("Inbox")]),
        ]

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for value in values {
            let data = try encoder.encode(value)
            let decoded = try decoder.decode(JSONValue.self, from: data)
            #expect(decoded == value)
        }
    }

    @Test
    func decodesFromRawJSON() throws {
        let data = Data(#"{"name":"Plan","count":3,"active":true,"items":[null,2.5]}"#.utf8)
        let value = try JSONDecoder().decode(JSONValue.self, from: data)

        #expect(value["name"] == .string("Plan"))
        #expect(value["count"] == .int(3))
        #expect(value["active"] == .bool(true))
        #expect(value["items"] == .array([.null, .double(2.5)]))
    }

    @Test
    func objectSubscriptReturnsEntryAndNilForMissingKeys() {
        let value = JSONValue.object(["name": .string("Inbox")])

        #expect(value["name"] == .string("Inbox"))
        #expect(value["missing"] == nil)
        #expect(JSONValue.string("not-object")["name"] == nil)
    }

    @Test
    func typedExtractorsReturnMatchingPrimitiveValues() {
        #expect(JSONValue.string("Inbox").stringValue == "Inbox")
        #expect(JSONValue.int(7).intValue == 7)
        #expect(JSONValue.bool(true).boolValue == true)
        #expect(JSONValue.int(2).doubleValue == 2)
        #expect(JSONValue.array([.int(1)]).arrayValue == [.int(1)])
        #expect(JSONValue.object(["done": .bool(false)]).objectValue == ["done": .bool(false)])
    }

    @Test
    func intValueOnlyAcceptsExactlyRepresentableDoubles() {
        #expect(JSONValue.double(1.0).intValue == 1)
        #expect(JSONValue.double(1.5).intValue == nil)
        #expect(JSONValue.double(1e100).intValue == nil)
        #expect(JSONValue.double(.infinity).intValue == nil)
    }
}
