import Foundation

#if os(macOS)
public final class MeetingsHelperXPCClient: @unchecked Sendable {
    public static let machServiceName = "group.com.kacperpietrzyk.Nexus.meetings-helper"

    private let lock = NSLock()
    private var connection: NSXPCConnection?

    public init() {}

    public func connect() -> any MeetingsHelperXPCProtocol {
        lock.lock()
        defer { lock.unlock() }

        if connection == nil {
            connection = makeConnection()
        }

        guard let connection else {
            preconditionFailure("Meetings helper XPC connection was not created")
        }

        let proxy = connection.remoteObjectProxyWithErrorHandler { error in
            print("Meetings helper XPC error: \(error.localizedDescription)")
        }
        guard let helper = proxy as? any MeetingsHelperXPCProtocol else {
            preconditionFailure("Meetings helper XPC proxy does not conform to protocol")
        }
        return helper
    }

    public func disconnect() {
        lock.lock()
        let oldConnection = connection
        connection = nil
        lock.unlock()

        oldConnection?.invalidate()
    }

    private func makeConnection() -> NSXPCConnection {
        let connection = NSXPCConnection(machServiceName: Self.machServiceName, options: [])
        connection.remoteObjectInterface = NSXPCInterface(with: MeetingsHelperXPCProtocol.self)
        connection.invalidationHandler = { [weak self] in
            self?.clearConnection(connection)
        }
        connection.interruptionHandler = { [weak self] in
            self?.clearConnection(connection)
        }
        connection.resume()
        return connection
    }

    private func clearConnection(_ connection: NSXPCConnection) {
        lock.lock()
        if self.connection === connection {
            self.connection = nil
        }
        lock.unlock()
    }
}
#endif
