import Foundation

/// Length-prefixed framing for the agent socket: 4-byte big-endian unsigned
/// length, then that many UTF-8 JSON bytes.
public enum AgentFrameCodec {
    public static func frame(_ payload: Data) -> Data {
        var length = UInt32(payload.count).bigEndian
        var out = Data(bytes: &length, count: 4)
        out.append(payload)
        return out
    }

    /// Removes and returns one complete frame's payload from the front of `buffer`,
    /// or nil if a full frame is not yet present. Throws on a corrupt length.
    public static func takeFrame(from buffer: inout Data) throws -> Data? {
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

public struct AgentSocketRequest: Codable, Sendable {
    public enum Operation: String, Codable, Sendable { case ping, manifest, dispatch }
    public let op: Operation
    public let name: String?
    public let argsJSON: Data?

    public init(op: Operation, name: String? = nil, argsJSON: Data? = nil) {
        self.op = op
        self.name = name
        self.argsJSON = argsJSON
    }
}

public struct AgentSocketResponse: Codable, Sendable {
    public struct ErrorBox: Codable, Sendable {
        public let code: Int
        public let message: String
        public init(code: Int, message: String) { self.code = code; self.message = message }
    }
    public let enabled: Bool?
    public let version: String?
    public let payload: Data?
    public let error: ErrorBox?

    public init(enabled: Bool? = nil, version: String? = nil, payload: Data? = nil, error: ErrorBox? = nil) {
        self.enabled = enabled
        self.version = version
        self.payload = payload
        self.error = error
    }
}
