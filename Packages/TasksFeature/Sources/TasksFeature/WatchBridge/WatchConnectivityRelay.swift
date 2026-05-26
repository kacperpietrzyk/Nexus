#if os(iOS)
import Foundation
import NexusCore
import OSLog
import WatchConnectivity

private struct WatchReplyHandler: @unchecked Sendable {
    let reply: ([String: Any]) -> Void

    func send(status: String, message: String? = nil, text: String? = nil) {
        var payload: [String: Any] = ["status": status]
        if let message {
            payload["message"] = message
        }
        if let text {
            payload["text"] = text
        }
        reply(payload)
    }
}

/// WCSessionDelegate adapter for Watch payloads. It marshals inbound messages
/// to `WatchPayloadHandler` and pings the Watch complications after changes.
@MainActor
public final class WatchConnectivityRelay: NSObject {
    private let handler: WatchPayloadHandler
    private let session: WCSession?

    public init(handler: WatchPayloadHandler) {
        self.handler = handler
        if WCSession.isSupported() {
            self.session = WCSession.default
        } else {
            self.session = nil
        }
        super.init()
    }

    public func activate() {
        session?.delegate = self
        session?.activate()
    }
}

extension WatchConnectivityRelay: WCSessionDelegate {
    nonisolated public func session(
        _: WCSession,
        activationDidCompleteWith _: WCSessionActivationState,
        error: Error?
    ) {
        if let error {
            Logger(subsystem: "com.kacperpietrzyk.Nexus", category: "WatchRelay")
                .error("WCSession activation failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    nonisolated public func sessionDidBecomeInactive(_: WCSession) {}

    nonisolated public func sessionDidDeactivate(_: WCSession) {
        WCSession.default.activate()
    }

    nonisolated public func session(
        _: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        let stringPayload = message.compactMapValues { $0 as? String }
        let reply = WatchReplyHandler(reply: replyHandler)
        _Concurrency.Task { @MainActor [weak self] in
            guard let self else {
                reply.send(status: "error", message: "Watch relay is no longer available.")
                return
            }
            await self.process(payload: stringPayload, reply: reply)
        }
    }

    nonisolated public func session(_: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        let stringPayload = userInfo.compactMapValues { $0 as? String }
        _Concurrency.Task { @MainActor [weak self] in
            await self?.process(payload: stringPayload, reply: nil)
        }
    }

    private func process(payload: [String: String], reply: WatchReplyHandler?) async {
        let outcome = await handler.handle(payload: payload)
        switch outcome {
        case .inserted, .updated:
            session?.transferUserInfo([
                WatchPayload.typeKey: WatchPayload.reloadComplicationsType
            ])
            reply?.send(status: "ok")
        case .replied(let text):
            reply?.send(status: "ok", message: text, text: text)
        case .ignored:
            reply?.send(status: "ignored")
        case .failed(let message):
            reply?.send(status: "error", message: message)
        }
    }
}
#endif
