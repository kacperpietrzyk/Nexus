import Foundation
import NexusCore
import OSLog
import WatchConnectivity
import WidgetKit
import os

private let watchBridgeLogger = Logger(
    subsystem: "com.kacperpietrzyk.Nexus",
    category: "WatchBridge"
)

/// Errors surfaced from the Watch side of the bridge so capture can display
/// "phone not reachable" states without crashing.
enum WatchPhoneBridgeError: Error, Equatable {
    case sessionNotSupported
    case sendFailed(String)
}

struct WatchAskNexusReachableReply: Equatable {
    static let queuedMessage = "Sent to Nexus. A reply will arrive shortly."

    let status: String
    let message: String?
    let text: String?

    init(payload: [String: Any]) throws {
        guard let status = payload["status"] as? String else {
            throw WatchPhoneBridgeError.sendFailed("iPhone returned an invalid Ask Nexus reply.")
        }
        self.status = status
        self.message = Self.nonEmpty(payload["message"] as? String)
        self.text = Self.nonEmpty(payload["text"] as? String)
    }

    func displayText() throws -> String {
        switch status {
        case "ok":
            if let text {
                return text
            }
            if let message {
                return message
            }
            throw WatchPhoneBridgeError.sendFailed("iPhone returned an empty Ask Nexus reply.")
        case "error":
            throw WatchPhoneBridgeError.sendFailed(message ?? "Ask Nexus failed on iPhone.")
        case "ignored":
            throw WatchPhoneBridgeError.sendFailed("Ask Nexus is not available on iPhone.")
        default:
            throw WatchPhoneBridgeError.sendFailed("iPhone returned an unknown Ask Nexus status: \(status).")
        }
    }

    private static func nonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmed, !trimmed.isEmpty else { return nil }
        return trimmed
    }
}

enum WatchPhonePayload {
    case askNexus(prompt: String)

    var message: [String: Any] {
        switch self {
        case .askNexus(let prompt):
            return [
                WatchPayload.typeKey: WatchPayload.askNexusType,
                WatchPayload.promptKey: prompt,
                WatchPayload.idKey: UUID().uuidString,
            ]
        }
    }
}

@MainActor
final class WatchPhoneBridge: NSObject {
    static let shared = WatchPhoneBridge()

    private let session: WCSession?
    private let pingLock = OSAllocatedUnfairLock<Date?>(initialState: nil)

    /// Wall-clock stamp of the most recent inbound iPhone signal. Used by
    /// `WatchNotificationGuard` and `WatchOverdueDigestScheduler` to decide
    /// whether the iPhone is the master right now.
    nonisolated var lastIPhonePing: Date? {
        pingLock.withLock { $0 }
    }

    nonisolated func stampPing() {
        pingLock.withLock { $0 = Date() }
    }

    override init() {
        if WCSession.isSupported() {
            self.session = WCSession.default
        } else {
            self.session = nil
        }
        super.init()
        session?.delegate = self
        session?.activate()
    }

    static func sendCaptureToPhone(input: String) async throws {
        try await shared.sendCapture(input: input)
    }

    static func sendMarkDone(taskID: UUID) async throws {
        try await shared.sendAction(type: WatchPayload.markDoneType, taskID: taskID)
    }

    static func sendReopen(taskID: UUID) async throws {
        try await shared.sendAction(type: WatchPayload.reopenType, taskID: taskID)
    }

    static func sendSnoozeAction(taskID: UUID, until: Date) async throws {
        try await shared.sendSnoozeAction(taskID: taskID, until: until)
    }

    /// Relay a proposed-block accept to iPhone (spec §7 / §11). The Watch has no
    /// EventKit, so the iPhone materializes the mirror event.
    static func sendAcceptBlock(blockID: UUID) async throws {
        try await shared.sendAcceptBlock(blockID: blockID)
    }

    func sendAcceptBlock(blockID: UUID) async throws {
        let message: [String: Any] = [
            WatchPayload.typeKey: WatchPayload.acceptBlockType,
            WatchPayload.blockIDKey: blockID.uuidString,
            WatchPayload.idKey: UUID().uuidString,
        ]
        try await sendMessageOrTransferUserInfo(message)
    }

    func sendSnoozeAction(taskID: UUID, until: Date) async throws {
        let message: [String: Any] = [
            WatchPayload.typeKey: WatchPayload.snoozeActionType,
            WatchPayload.taskIDKey: taskID.uuidString,
            WatchPayload.snoozeUntilKey: ISO8601DateFormatter().string(from: until),
            WatchPayload.idKey: UUID().uuidString,
        ]
        try await sendMessageOrTransferUserInfo(message)
    }

    func sendCapture(input: String) async throws {
        let message: [String: Any] = [
            WatchPayload.typeKey: WatchPayload.captureType,
            WatchPayload.inputKey: input,
            WatchPayload.idKey: UUID().uuidString,
        ]
        try await sendMessageOrTransferUserInfo(message)
    }

    func send(_ payload: WatchPhonePayload) async throws {
        try await sendMessageOrTransferUserInfo(payload.message)
    }

    func sendAskNexus(prompt: String) async throws -> String {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw WatchPhoneBridgeError.sendFailed("Question is empty.")
        }

        let message = WatchPhonePayload.askNexus(prompt: trimmed).message
        guard let session else { throw WatchPhoneBridgeError.sessionNotSupported }

        guard session.isReachable else {
            session.transferUserInfo(message)
            return WatchAskNexusReachableReply.queuedMessage
        }

        return try await withCheckedThrowingContinuation { continuation in
            session.sendMessage(
                message,
                replyHandler: { reply in
                    do {
                        let decoded = try WatchAskNexusReachableReply(payload: reply)
                        continuation.resume(returning: try decoded.displayText())
                    } catch {
                        continuation.resume(throwing: error)
                    }
                },
                errorHandler: { _ in
                    session.transferUserInfo(message)
                    continuation.resume(returning: WatchAskNexusReachableReply.queuedMessage)
                })
        }
    }

    func sendAction(type: String, taskID: UUID) async throws {
        let message: [String: Any] = [
            WatchPayload.typeKey: type,
            WatchPayload.taskIDKey: taskID.uuidString,
            WatchPayload.idKey: UUID().uuidString,
        ]
        try await sendMessageOrTransferUserInfo(message)
    }

    private func sendMessageOrTransferUserInfo(_ message: [String: Any]) async throws {
        guard let session else { throw WatchPhoneBridgeError.sessionNotSupported }

        guard session.isReachable else {
            session.transferUserInfo(message)
            return
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            session.sendMessage(
                message,
                replyHandler: { _ in
                    continuation.resume()
                },
                errorHandler: { _ in
                    session.transferUserInfo(message)
                    continuation.resume()
                })
        }
    }
}

extension WatchPhoneBridge: WCSessionDelegate {
    nonisolated func session(
        _: WCSession,
        activationDidCompleteWith _: WCSessionActivationState,
        error _: Error?
    ) {}

    nonisolated func session(_: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        stampPing()
        let type = userInfo[WatchPayload.typeKey] as? String
        if type == WatchPayload.reloadComplicationsType {
            _Concurrency.Task { @MainActor in
                WidgetCenter.shared.reloadAllTimelines()
            }
            return
        }
        guard
            type == WatchPayload.notifSnapshotType,
            let json = userInfo[WatchPayload.snapshotPayloadKey] as? String,
            let data = json.data(using: .utf8),
            let snapshot = try? JSONDecoder().decode(NotificationSnapshot.self, from: data)
        else { return }
        _Concurrency.Task { @MainActor in
            if let store = WatchNotificationSnapshotStore() {
                do {
                    try store.save(snapshot)
                } catch {
                    watchBridgeLogger.error(
                        "Snapshot save failed: \(error.localizedDescription, privacy: .public)"
                    )
                }
            } else {
                watchBridgeLogger.error(
                    "Snapshot store unavailable — App Group entitlement missing?"
                )
            }
            // Guard wake-up — Task 8 will subscribe to this notification.
            NotificationCenter.default.post(
                name: .watchNotifSnapshotUpdated,
                object: nil
            )
        }
    }
}

extension Notification.Name {
    static let watchNotifSnapshotUpdated = Notification.Name("nexus.watch.notif.snapshot.updated")
}

extension WatchPhoneBridge: WatchReachabilityProbing, WatchIPhonePresenceProbing {
    nonisolated var isReachable: Bool {
        WCSession.isSupported() ? WCSession.default.isReachable : false
    }
}

extension WatchPhoneBridgeError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .sessionNotSupported:
            return "Watch Connectivity is not supported on this device."
        case .sendFailed(let message):
            return "Failed to send to iPhone: \(message)"
        }
    }
}
