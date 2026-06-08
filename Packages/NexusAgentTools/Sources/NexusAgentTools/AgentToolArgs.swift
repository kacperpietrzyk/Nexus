import Foundation
import NexusCore

/// Shared argument helpers for `AgentTool` implementations.
enum AgentToolArgs {
    /// Reads an optional integer `limit` argument, applying `fallback` when it is
    /// absent and clamping the result into `[1, upperBound]`.
    ///
    /// The MCP sidecar pre-validates against each tool's `inputSchema`, but the
    /// in-app dispatch path (and any client that ignores the schema bounds) reaches
    /// `call` directly. Clamping here keeps list/search honest regardless: a `0`/
    /// negative `limit` can no longer collapse a query to a single row — or trap a
    /// `prefix(_:)` on a negative count — and an over-large value is capped at the
    /// schema maximum instead of returning the whole table. (A5)
    static func limit(_ args: JSONValue, default fallback: Int, max upperBound: Int) -> Int {
        let requested = args["limit"]?.intValue ?? fallback
        return min(max(requested, 1), upperBound)
    }
}
