import Foundation

/// Mirror of `NexusAgentTools.AgentFrameCodec` + socket message types. Length-
/// prefixed framing: 4-byte big-endian unsigned length, then UTF-8 JSON bytes.
enum AgentFrameCodec {
    static func frame(_ payload: Data) -> Data {
        var length = UInt32(payload.count).bigEndian
        var out = Data(bytes: &length, count: 4)
        out.append(payload)
        return out
    }

    static func takeFrame(from buffer: inout Data) throws -> Data? {
        let bytes = Data(buffer)
        guard bytes.count >= 4 else { return nil }
        let length = bytes.prefix(4).withUnsafeBytes { raw in
            UInt32(bigEndian: raw.loadUnaligned(as: UInt32.self))
        }
        let total = 4 + Int(length)
        guard bytes.count >= total else { return nil }
        let payload = bytes.subdata(in: 4..<total)
        buffer = bytes.subdata(in: total..<bytes.count)
        return payload
    }
}

struct AgentSocketRequest: Codable, Sendable {
    enum Operation: String, Codable, Sendable { case ping, manifest, dispatch }
    let op: Operation
    let name: String?
    let argsJSON: Data?

    init(op: Operation, name: String? = nil, argsJSON: Data? = nil) {
        self.op = op
        self.name = name
        self.argsJSON = argsJSON
    }
}

struct AgentSocketResponse: Codable, Sendable {
    struct ErrorBox: Codable, Sendable {
        let code: Int
        let message: String
    }
    let enabled: Bool?
    let version: String?
    let payload: Data?
    let error: ErrorBox?
}
