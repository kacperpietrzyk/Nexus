import Foundation

/// Mirror of NexusAgentXPCProtocol. The sidecar cannot import NexusMac code.
@objc protocol NexusAgentXPCProtocolMirror {
    func ping(reply: @escaping @Sendable (Bool, String) -> Void)
    func getToolManifest(reply: @escaping @Sendable (Data?, NSError?) -> Void)
    func dispatchTool(name: String, argsJSON: Data, reply: @escaping @Sendable (Data?, NSError?) -> Void)
}

actor XPCClient {
    private var connection: NSXPCConnection?
    private var isConnected = false

    func connect() async throws {
        if isConnected { return }

        let connection = NSXPCConnection(machServiceName: machServiceName(), options: [])
        connection.remoteObjectInterface = NSXPCInterface(with: NexusAgentXPCProtocolMirror.self)
        connection.invalidationHandler = { [weak self] in
            Task { await self?.markDisconnected() }
        }
        connection.interruptionHandler = { [weak self] in
            Task { await self?.markDisconnected() }
        }
        connection.resume()
        self.connection = connection

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            guard
                let proxy = connection.remoteObjectProxyWithErrorHandler({ _ in
                    continuation.resume(throwing: SidecarErrors.appNotRunning)
                }) as? NexusAgentXPCProtocolMirror
            else {
                continuation.resume(throwing: SidecarErrors.appNotRunning)
                return
            }
            proxy.ping { ok, _ in
                if ok {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: SidecarErrors.mcpDisabled)
                }
            }
        }
        isConnected = true
    }

    func getToolManifest() async throws -> Data {
        try await connect()
        return try await withCheckedThrowingContinuation { continuation in
            guard
                let proxy = makeProxy(errorHandler: { _ in
                    continuation.resume(throwing: SidecarErrors.appNotRunning)
                })
            else {
                continuation.resume(throwing: SidecarErrors.appNotRunning)
                return
            }
            proxy.getToolManifest { data, error in
                if let error {
                    continuation.resume(throwing: SidecarErrors.from(nsError: error))
                } else if let data {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(throwing: MCPError(code: -32_099, message: "empty manifest"))
                }
            }
        }
    }

    func dispatchTool(name: String, argsJSON: Data) async throws -> Data {
        try await connect()
        return try await withCheckedThrowingContinuation { continuation in
            guard
                let proxy = makeProxy(errorHandler: { _ in
                    continuation.resume(throwing: SidecarErrors.appNotRunning)
                })
            else {
                continuation.resume(throwing: SidecarErrors.appNotRunning)
                return
            }
            proxy.dispatchTool(name: name, argsJSON: argsJSON) { data, error in
                if let error {
                    continuation.resume(throwing: SidecarErrors.from(nsError: error))
                } else if let data {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(throwing: MCPError(code: -32_099, message: "empty result"))
                }
            }
        }
    }

    private func makeProxy(errorHandler: @escaping (Error) -> Void) -> NexusAgentXPCProtocolMirror? {
        guard let connection else { return nil }
        return connection.remoteObjectProxyWithErrorHandler(errorHandler) as? NexusAgentXPCProtocolMirror
    }

    private func markDisconnected() {
        isConnected = false
        connection?.invalidate()
        connection = nil
    }
}
