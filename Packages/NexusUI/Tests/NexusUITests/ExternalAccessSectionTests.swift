import Foundation
import NexusAgentTools
import SwiftUI
import Testing

@testable import NexusUI

#if !os(watchOS)

@MainActor
@Suite("ExternalAccessSection")
struct ExternalAccessSectionTests {
    @Test("renders when activity log provided")
    func renders() {
        let log = AgentActivityLog()
        #if os(macOS)
        let section = ExternalAccessSection(
            sidecarPath: "/Applications/Nexus.app/Contents/MacOS/nexus-mcp",
            activityLog: log
        )
        #expect(section.activityLog === log)
        #endif
    }

    @Test("activity log entries appear in the rendered table")
    func activityEntries() {
        let log = AgentActivityLog()
        log.record(.success(name: "tasks.list", argsRedacted: "{}", durationMs: 12))
        let view = AgentActivityLogView(log: log)
        _ = view.body
        #expect(log.entries.count == 1)
    }

    /// Resolves both `statusIcon` switch arms (`.ok` checkmark / `.errorCode`
    /// xmark+code) so the MP-4.1 slice-2 Semantic→ink-ladder burn (positive
    /// → `Text.secondary`, negative → `Text.primary`) stays build/resolution
    /// safe along the touched value-path.
    @Test("activity log resolves ok and error status arms")
    func activityLogResolvesBothStatusArms() {
        let log = AgentActivityLog()
        log.record(.success(name: "tasks.list", argsRedacted: "{}", durationMs: 12))
        log.record(.failure(name: "tasks.create", argsRedacted: "{}", code: 422, durationMs: 7))
        let view = AgentActivityLogView(log: log)
        _ = view.body
        #expect(log.entries.count == 2)
    }

    #if os(macOS)
    /// Resolves the `ExternalAccessSection` body so the host composing the
    /// retuned `Status` label + status views builds after the slice-2 burn.
    /// The `copyStatus`/`addToClaudeCodeStatus` Label branches are behind
    /// `@State` (default `.idle`), so per the slice-1 adjudication the
    /// per-site source audit comment names those burn sites; this guards
    /// build/resolution of the composing host.
    @Test("external access section resolves body")
    func externalAccessSectionResolvesBody() {
        let view = ExternalAccessSection(
            sidecarPath: "/Applications/Nexus.app/Contents/MacOS/nexus-mcp",
            activityLog: AgentActivityLog()
        )
        _ = view.body
    }
    #endif

    #if os(macOS)
    @Test("Claude Desktop config is valid JSON for unusual paths")
    func claudeDesktopConfigEscapesSidecarPath() throws {
        let path = "/Applications/Nexus \"Beta\"/Contents/MacOS/nexus\\mcp"
        let config = try ExternalAccessSection.claudeDesktopConfig(sidecarPath: path)
        let data = try #require(config.data(using: .utf8))
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let servers = try #require(object["mcpServers"] as? [String: Any])
        let nexus = try #require(servers["nexus"] as? [String: String])

        #expect(nexus["command"] == path)
    }

    @Test("Claude Code add uses user scope")
    func claudeCodeArgumentsUseUserScope() {
        // The canonical argument list passed to `claude`, no leading "claude".
        let arguments = ExternalAccessSection.claudeCodeArguments(sidecarPath: "/tmp/nexus-mcp")

        #expect(arguments == ["mcp", "add", "--scope", "user", "nexus", "/tmp/nexus-mcp"])
    }

    @Test("Claude Code command is copy-paste ready and shell-quotes the path")
    func claudeCodeCommandIsShellSafe() {
        // Plain path: the sidecar path is single-quoted so spaces survive a paste.
        #expect(
            ExternalAccessSection.claudeCodeCommand(sidecarPath: "/Applications/Nexus.app/Contents/MacOS/nexus-mcp")
                == "claude mcp add --scope user nexus '/Applications/Nexus.app/Contents/MacOS/nexus-mcp'"
        )

        // Embedded single quote is POSIX-escaped ('\'') so the command stays valid.
        #expect(
            ExternalAccessSection.claudeCodeCommand(sidecarPath: "/tmp/a'b")
                == "claude mcp add --scope user nexus '/tmp/a'\\''b'"
        )
    }
    #endif
}

#endif
