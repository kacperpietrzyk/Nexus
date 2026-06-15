import Foundation
import Testing

@testable import NexusCore

@Suite("ActivityChangePayload")
struct ActivityChangePayloadTests {
    @Test("encodes both keys, nil as JSON null")
    func encodesBothKeysWithNull() throws {
        let json = try #require(ActivityChangePayload(old: "todo", new: nil).encodedJSON)
        let object = try #require(
            try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]
        )
        #expect(object["old"] as? String == "todo")
        #expect(object.keys.contains("new"))
        #expect(object["new"] is NSNull)
    }

    @Test("round-trips through encodedJSON/decoded")
    func roundTrips() {
        let payload = ActivityChangePayload(old: nil, new: "inProgress")
        let decoded = ActivityChangePayload.decoded(from: payload.encodedJSON)
        #expect(decoded == payload)
    }

    @Test("decoded returns nil for nil or garbage input")
    func decodedRejectsGarbage() {
        #expect(ActivityChangePayload.decoded(from: nil) == nil)
        #expect(ActivityChangePayload.decoded(from: "not json") == nil)
    }

    @Test("dateString/parseDate round-trip at second precision")
    func dateRoundTrip() throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let text = try #require(ActivityChangePayload.dateString(date))
        #expect(ActivityChangePayload.parseDate(text) == date)
        #expect(ActivityChangePayload.dateString(nil) == nil)
        #expect(ActivityChangePayload.parseDate("garbage") == nil)
    }
}
