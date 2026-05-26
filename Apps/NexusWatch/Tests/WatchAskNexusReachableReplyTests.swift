import Testing

@testable import NexusWatch

@Suite("Watch Ask Nexus reachable reply")
struct WatchAskNexusReachableReplyTests {
    @Test("OK reply prefers text")
    func okReplyPrefersText() throws {
        let reply = try WatchAskNexusReachableReply(payload: [
            "status": "ok",
            "message": "fallback",
            "text": "actual reply",
        ])

        #expect(try reply.displayText() == "actual reply")
    }

    @Test("Error reply throws bridge failure")
    func errorReplyThrows() throws {
        let reply = try WatchAskNexusReachableReply(payload: [
            "status": "error",
            "message": "provider failed",
        ])

        #expect(throws: WatchPhoneBridgeError.sendFailed("provider failed")) {
            _ = try reply.displayText()
        }
    }

    @Test("Missing status is invalid")
    func missingStatusThrows() {
        #expect(throws: WatchPhoneBridgeError.sendFailed("iPhone returned an invalid Ask Nexus reply.")) {
            _ = try WatchAskNexusReachableReply(payload: [:])
        }
    }
}
