import Foundation
import MCP

/// Bridges MCP stdio to the XPC service hosted by NexusMac.
///
/// Swift MCP SDK 0.12 exposes tool support through `ListTools` and `CallTool`
/// method handlers rather than per-tool registration. The data flow remains
/// manifest-driven: the running app owns tool definitions and execution.
actor MCPServer {
    private let client: XPCClient
    private var server: Server?
    private var cachedTools: [Tool]?

    init(client: XPCClient) {
        self.client = client
    }

    func start() async throws {
        let server = Server(
            name: "nexus",
            version: "0.1.0",
            title: "Nexus",
            capabilities: .init(tools: .init(listChanged: false))
        )

        await server.withMethodHandler(ListTools.self) { [weak self] _ in
            let tools = (try? await self?.loadTools()) ?? []
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

    private func loadTools() async throws -> [Tool] {
        if let cachedTools {
            return cachedTools
        }
        let manifestData = try await client.getToolManifest()
        let manifest = try ToolManifestCache(from: manifestData)
        let tools = try manifest.tools.map(Self.makeTool(from:))
        cachedTools = tools
        return tools
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
