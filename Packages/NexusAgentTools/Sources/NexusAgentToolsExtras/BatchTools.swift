import Foundation
import NexusAgentTools
import NexusCore

/// `batch.begin` — opens a "quiet mode" window so a series of writes does not
/// brown out the app.
///
/// The app re-runs its store-change refresh fan-out (activity-feed unread
/// re-projection, navigation entity-command rebuild, and — when the Today tab is
/// open — the on-device LLM Daily-Brief regeneration) on every save. A sustained
/// MCP write burst therefore amplifies into one refresh per write. Bracketing the
/// burst with `batch.begin` … `batch.end` suspends that refresh and coalesces it
/// into a single reload when the batch ends.
///
/// Safe by construction: the suspend self-expires after a bounded timeout, so a
/// crash or a dropped `batch.end` mid-series can never leave refresh suspended
/// forever. `batch.end` is idempotent. See `RefreshSuspensionCoordinator`.
public struct BatchBeginTool: AgentTool {
    public let name = "batch.begin"
    public let description = """
        Open a quiet-mode batch before a series of writes. While a batch is open the \
        app suspends its store-change refresh (activity feed, navigation index, and \
        the on-device Daily Brief), coalescing them into a single refresh on \
        batch.end — preventing the app from browning out under sustained writes. \
        Always pair with batch.end. The suspend auto-expires after a bounded \
        timeout, so a missed batch.end is self-healing. Ref-counted: nested begins \
        require an equal number of ends.
        """
    public let inputSchema: JSONSchema = .object(properties: [:], required: [])

    public init() {}

    @MainActor
    public func call(args: JSONValue, context: AgentContext) async throws -> JSONValue {
        RefreshSuspensionCoordinator.shared.begin()
        return .object(["ok": .bool(true), "suspended": .bool(true)])
    }
}

/// `batch.end` — closes a quiet-mode window and triggers a single coalesced
/// refresh. Idempotent: an `end` with no matching `begin` is a safe no-op.
public struct BatchEndTool: AgentTool {
    public let name = "batch.end"
    public let description = """
        Close a quiet-mode batch opened with batch.begin and trigger a single \
        coalesced refresh of the app. Idempotent and safe to call even if no batch \
        is open (no-op). Ref-counted: only the end that closes the last open batch \
        resumes refresh.
        """
    public let inputSchema: JSONSchema = .object(properties: [:], required: [])

    public init() {}

    @MainActor
    public func call(args: JSONValue, context: AgentContext) async throws -> JSONValue {
        let resumed = RefreshSuspensionCoordinator.shared.end()
        return .object([
            "ok": .bool(true),
            "resumed": .bool(resumed),
            "suspended": .bool(RefreshSuspensionCoordinator.shared.isSuspended),
        ])
    }
}
