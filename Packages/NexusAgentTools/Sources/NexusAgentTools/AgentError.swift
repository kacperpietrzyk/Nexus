import Foundation

/// Typed errors emitted by tools, mapped to JSON-RPC error codes per spec §7.7.
public enum AgentError: Error, Sendable, Equatable {
    case appNotRunning
    case mcpDisabled
    case notFound(String)
    case validation(String)
    case conflict(String)
    case internalError(String)

    public static let errorDomain = "com.kacperpietrzyk.nexus.agent"

    public var jsonRPCCode: Int {
        switch self {
        case .appNotRunning: return -32001
        case .mcpDisabled: return -32002
        case .notFound: return -32003
        case .validation: return -32004
        case .conflict: return -32005
        case .internalError: return -32099
        }
    }

    public var name: String {
        switch self {
        case .appNotRunning: return "app_not_running"
        case .mcpDisabled: return "mcp_disabled"
        case .notFound: return "not_found"
        case .validation: return "validation"
        case .conflict: return "conflict"
        case .internalError: return "internal"
        }
    }

    public var message: String {
        switch self {
        case .appNotRunning: return "Nexus.app is not running. Open it to enable MCP access."
        case .mcpDisabled: return "MCP server is disabled in Settings."
        case .notFound(let m), .validation(let m), .conflict(let m), .internalError(let m): return m
        }
    }

    public var asNSError: NSError {
        NSError(
            domain: Self.errorDomain,
            code: jsonRPCCode,
            userInfo: [
                NSLocalizedDescriptionKey: message,
                "agent.error.name": name,
            ]
        )
    }

    public static func from(_ nsError: NSError) -> AgentError {
        guard nsError.domain == Self.errorDomain else {
            return .internalError(nsError.localizedDescription)
        }

        switch nsError.code {
        case -32001: return .appNotRunning
        case -32002: return .mcpDisabled
        case -32003: return .notFound(nsError.localizedDescription)
        case -32004: return .validation(nsError.localizedDescription)
        case -32005: return .conflict(nsError.localizedDescription)
        default: return .internalError(nsError.localizedDescription)
        }
    }
}
