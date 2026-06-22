import Foundation

/// Connects to the agent unix-domain socket vended by a running NexusMac.
/// Public surface mirrors the old XPCClient so MCPServer is unchanged:
/// `connect()`, `getToolManifest()`, `dispatchTool(name:argsJSON:)`.
actor AgentSocketClient {
    private var fd: Int32 = -1

    /// Read/write timeout for the MANIFEST request only, so a connected-but-silent
    /// app can't hang `ListTools` forever. Tool DISPATCH is intentionally
    /// unbounded: legitimate tools (semantic search, on-device summarization,
    /// export) can run well past any short timeout. The fd is sticky, so the
    /// timeout is set per request and explicitly cleared for dispatch.
    private let manifestTimeoutSeconds: Int = 5

    func connect() async throws {
        if fd >= 0 { return }
        guard let url = AgentServiceConstants.socketURL() else {
            throw SidecarErrors.appNotRunning
        }
        let path = url.path
        let sock = socket(AF_UNIX, SOCK_STREAM, 0)
        guard sock >= 0 else { throw SidecarErrors.appNotRunning }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        _ = withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            path.withCString { strncpy(UnsafeMutableRawPointer(ptr).assumingMemoryBound(to: CChar.self), $0, 103) }
        }
        let size = socklen_t(MemoryLayout<sockaddr_un>.size)
        let rc = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(sock, $0, size) }
        }
        guard rc == 0 else {
            close(sock)
            throw SidecarErrors.appNotRunning
        }
        fd = sock
    }

    /// Set the socket read/write timeout (`SO_RCVTIMEO` / `SO_SNDTIMEO`).
    /// Zero seconds = blocking / no timeout. A timed-out read returns -1/EAGAIN,
    /// which the request loop maps to a thrown error via its `n <= 0` path. The
    /// fd is sticky across requests, so this is set explicitly per request.
    private func setSocketTimeout(seconds: Int) {
        var tv = timeval(tv_sec: seconds, tv_usec: 0)
        let len = socklen_t(MemoryLayout<timeval>.size)
        _ = setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, len)
        _ = setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, len)
    }

    func getToolManifest() async throws -> Data {
        try await connect()
        // Bound the manifest fetch so a silent app can't hang ListTools forever.
        let response = try request(AgentSocketRequest(op: .manifest), timeoutSeconds: manifestTimeoutSeconds)
        if let error = response.error { throw MCPError(code: error.code, message: error.message) }
        guard let payload = response.payload else { throw MCPError(code: -32_099, message: "empty manifest") }
        return payload
    }

    func dispatchTool(name: String, argsJSON: Data) async throws -> Data {
        try await connect()
        // Tool execution is unbounded: long-running tools must not be cut off.
        let response = try request(AgentSocketRequest(op: .dispatch, name: name, argsJSON: argsJSON), timeoutSeconds: 0)
        if let error = response.error { throw MCPError(code: error.code, message: error.message) }
        guard let payload = response.payload else { throw MCPError(code: -32_099, message: "empty result") }
        return payload
    }

    private func request(_ req: AgentSocketRequest, timeoutSeconds: Int) throws -> AgentSocketResponse {
        // The fd is reused across requests, so set the timeout explicitly each
        // time (manifest bounded; dispatch cleared to blocking).
        setSocketTimeout(seconds: timeoutSeconds)
        let body = try JSONEncoder().encode(req)
        let framed = AgentFrameCodec.frame(body)
        try writeAll(framed)
        var buffer = Data()
        var chunk = [UInt8](repeating: 0, count: 16 * 1024)
        while true {
            if let frame = try AgentFrameCodec.takeFrame(from: &buffer) {
                return try JSONDecoder().decode(AgentSocketResponse.self, from: frame)
            }
            let n = read(fd, &chunk, chunk.count)
            if n <= 0 { markClosed(); throw SidecarErrors.appNotRunning }
            buffer.append(contentsOf: chunk[0..<n])
        }
    }

    private func writeAll(_ data: Data) throws {
        try data.withUnsafeBytes { raw in
            var sent = 0
            guard let base = raw.baseAddress else { return }
            while sent < raw.count {
                let n = write(fd, base + sent, raw.count - sent)
                if n <= 0 { markClosed(); throw SidecarErrors.appNotRunning }
                sent += n
            }
        }
    }

    private func markClosed() {
        if fd >= 0 { close(fd); fd = -1 }
    }
}
