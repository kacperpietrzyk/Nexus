import Foundation
import NexusAgentTools
import Testing

struct AgentFrameCodecTests {
    @Test
    func encodeThenDecodeRoundTrips() throws {
        let payload = Data("hello frame".utf8)
        let framed = AgentFrameCodec.frame(payload)
        #expect(framed.count == 4 + payload.count)

        var buffer = framed
        let decoded = try AgentFrameCodec.takeFrame(from: &buffer)
        #expect(decoded == payload)
        #expect(buffer.isEmpty)
    }

    @Test
    func takeFrameReturnsNilWhenIncomplete() throws {
        let payload = Data("partial".utf8)
        let framed = AgentFrameCodec.frame(payload)
        var buffer = framed.prefix(framed.count - 2)
        #expect(try AgentFrameCodec.takeFrame(from: &buffer) == nil)
    }

    @Test
    func requestAndResponseCodableRoundTrip() throws {
        let req = AgentSocketRequest(op: .dispatch, name: "tasks.get", argsJSON: Data(#"{"task_id":"x"}"#.utf8))
        let data = try JSONEncoder().encode(req)
        let back = try JSONDecoder().decode(AgentSocketRequest.self, from: data)
        #expect(back.op == .dispatch)
        #expect(back.name == "tasks.get")
        #expect(back.argsJSON == req.argsJSON)
    }
}
