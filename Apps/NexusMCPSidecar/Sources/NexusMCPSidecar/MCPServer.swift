import Foundation
import MCP

/// Bridges MCP stdio to the unix-domain socket service hosted by NexusMac.
///
/// Swift MCP SDK 0.12 exposes tool support through `ListTools` and `CallTool`
/// method handlers rather than per-tool registration. The data flow remains
/// manifest-driven: the running app owns tool definitions and execution.
actor MCPServer {
    /// Total wall-clock budget for the synchronous, in-band retry on a single
    /// `ListTools` call. Kept short because it BLOCKS the response the client is
    /// waiting on; the unbounded "app came up later" tail is handled by the
    /// background recovery poll, not by lengthening this.
    static let foregroundLoadBudget: Double = 3.0
    /// Delay between background recovery poll attempts once the app is unreachable.
    static let backgroundPollDelay: Double = 2.0

    private let client: AgentSocketClient
    private var server: Server?
    private var cachedTools: [Tool]?
    private var recoveryTask: Task<Void, Never>?

    init(client: AgentSocketClient) {
        self.client = client
    }

    func start() async throws {
        let server = Server(
            name: "nexus",
            version: "0.1.0",
            title: "Nexus",
            // We declare listChanged because we ACTUALLY emit the notification
            // from the background recovery poll below — not as a bare flag.
            capabilities: .init(tools: .init(listChanged: true))
        )

        await server.withMethodHandler(ListTools.self) { [weak self] _ in
            guard let self else { return ListTools.Result(tools: []) }
            // On failure this THROWS (-> JSON-RPC error to the client) rather
            // than returning an empty list, and kicks off background recovery so
            // tools appear once the app finishes launching, with no restart.
            let tools = try await self.loadTools()
            return ListTools.Result(tools: tools)
        }

        await server.withMethodHandler(CallTool.self) { [weak self, client] parameters in
            do {
                guard let self else {
                    return Self.errorResult(message: "Sidecar server deallocated")
                }
                let tools = try await self.loadTools()
                let knownToolNames = Set(tools.map(\.name))
                guard knownToolNames.contains(parameters.name) else {
                    return Self.errorResult(message: "Unknown tool: \(parameters.name)")
                }
            } catch let error as MCPError {
                return Self.errorResult(message: "\(error.message) (code \(error.code))")
            } catch {
                return Self.errorResult(message: "\(error)")
            }

            let arguments = parameters.arguments ?? [:]
            let argsData = try JSONEncoder().encode(arguments)
            do {
                let resultData = try await client.dispatchTool(name: parameters.name, argsJSON: argsData)
                return try Self.successResult(from: resultData)
            } catch let error as MCPError {
                return Self.errorResult(message: "\(error.message) (code \(error.code))")
            } catch {
                return Self.errorResult(message: "\(error)")
            }
        }

        self.server = server
        let transport = StdioTransport()
        try await server.start(transport: transport)
        await server.waitUntilCompleted()
    }

    /// Load the tool list, recovering from the "app still launching" race.
    ///
    /// A non-empty list is cached. A failed or empty load is NEVER cached: we
    /// retry in-band for a short budget, and on persistent failure we (1) start
    /// a background poll that will populate the cache + emit
    /// `tools/list_changed` once the app comes up, then (2) THROW so the client
    /// sees an error instead of an empty, sticky tool list.
    private func loadTools() async throws -> [Tool] {
        if let cachedTools {
            return cachedTools
        }
        do {
            let tools = try await ToolLoadRetry.run(budget: Self.foregroundLoadBudget) {
                try await self.fetchTools()
            }
            cachedTools = tools
            return tools
        } catch {
            startRecoveryPollIfNeeded()
            throw error
        }
    }

    /// One round-trip to the app: fetch + decode the manifest into `Tool`s.
    /// Returns `[]` when the app is reachable but the manifest is empty (treated
    /// as "not ready yet" by the retry policy, since the app ships 200+ tools).
    private func fetchTools() async throws -> [Tool] {
        let manifestData = try await client.getToolManifest()
        let manifest = try ToolManifestCache(from: manifestData)
        return try manifest.tools.map(Self.makeTool(from:))
    }

    /// Background recovery: poll until the app is reachable and returns tools,
    /// cache them, then emit `notifications/tools/list_changed` so a passive
    /// client (one that already saw the empty/failed load) re-queries — making
    /// tools appear without a session restart or manual `/mcp` reconnect.
    ///
    /// This is what turns the declared `listChanged` capability from a flag into
    /// a real recovery mechanism. Idempotent: at most one poll runs at a time.
    private func startRecoveryPollIfNeeded() {
        guard recoveryTask == nil, cachedTools == nil else { return }
        recoveryTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if await self.attemptBackgroundRecovery() { return }
                try? await Task.sleep(for: .seconds(Self.backgroundPollDelay))
            }
        }
    }

    /// One background recovery attempt. On success caches the tools, emits the
    /// list-changed notification, clears the recovery handle, and returns `true`.
    private func attemptBackgroundRecovery() async -> Bool {
        guard cachedTools == nil else {
            recoveryTask = nil
            return true
        }
        guard let tools = try? await fetchTools(), !tools.isEmpty else {
            return false
        }
        cachedTools = tools
        recoveryTask = nil
        try? await server?.notify(ToolListChangedNotification.message())
        return true
    }

    private static func makeTool(from entry: ToolEntry) throws -> Tool {
        Tool(
            name: entry.name,
            description: entry.description,
            inputSchema: try value(from: entry.inputSchema ?? ["type": "object"])
        )
    }

    private static func successResult(from data: Data) throws -> CallTool.Result {
        let text = String(data: data, encoding: .utf8) ?? ""
        let structured: Value? = try structuredObject(from: data)
        return CallTool.Result(
            content: [.text(text: text, annotations: nil, _meta: nil)],
            structuredContent: structured,
            isError: false
        )
    }

    private static func errorResult(message: String) -> CallTool.Result {
        CallTool.Result(
            content: [.text(text: message, annotations: nil, _meta: nil)],
            isError: true
        )
    }

    private static func value(from json: Any) throws -> Value {
        guard JSONSerialization.isValidJSONObject(json) else {
            return .object([:])
        }
        let data = try JSONSerialization.data(withJSONObject: json)
        return try JSONDecoder().decode(Value.self, from: data)
    }

    static func structuredObject(from data: Data) throws -> Value {
        let value = try JSONDecoder().decode(Value.self, from: data)
        if case .object = value {
            return value
        }
        return .object(["result": value])
    }
}
