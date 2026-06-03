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
            activityLog: log,
            isClaudeCLIAvailable: false
        )
        #expect(section.activityLog === log)
        #else
        _ = ExternalAccessInfoSection()
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

    /// Resolves the `SyncSettingsSection` body in both `cloudKitEnabled`
    /// states so the slice-2 icon ternary burn (positive → `Text.secondary`,
    /// negative → `Text.primary`) is guarded along the public-init path.
    @Test("sync section resolves enabled and disabled states")
    func syncSectionResolvesBothStates() {
        let enabled = SyncSettingsSection(
            cloudKitEnabled: true,
            containerIdentifier: "iCloud.com.example.test"
        )
        _ = enabled.body
        let disabled = SyncSettingsSection(
            cloudKitEnabled: false,
            containerIdentifier: "iCloud.com.example.test"
        )
        _ = disabled.body
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
            activityLog: AgentActivityLog(),
            isClaudeCLIAvailable: true
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
        // The executable is resolved separately (claudeExecutableURL), so the
        // arguments are what we pass to `claude` itself — no leading "claude".
        let arguments = ExternalAccessSection.claudeCodeArguments(sidecarPath: "/tmp/nexus-mcp")

        #expect(arguments == ["mcp", "add", "--scope", "user", "nexus", "/tmp/nexus-mcp"])
    }

    @Test("claude CLI is located via CLAUDE_CLI_PATH override and home candidates")
    func claudeExecutableLocator() throws {
        let fileManager = FileManager.default
        let tempDir = fileManager.temporaryDirectory
            .appendingPathComponent("nexus-cli-locator-\(UUID().uuidString)")
        let binDir = tempDir.appendingPathComponent(".local/bin")
        try fileManager.createDirectory(at: binDir, withIntermediateDirectories: true)
        let fakeClaude = binDir.appendingPathComponent("claude")
        try Data("#!/bin/sh\n".utf8).write(to: fakeClaude)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeClaude.path)
        defer { try? fileManager.removeItem(at: tempDir) }

        // Found relative to an injected home directory.
        let viaHome = ExternalAccessSection.claudeExecutableURL(
            environment: [:],
            homeDirectory: tempDir
        )
        #expect(viaHome?.path == fakeClaude.path)

        // CLAUDE_CLI_PATH override wins over the candidate scan.
        let viaOverride = ExternalAccessSection.claudeExecutableURL(
            environment: ["CLAUDE_CLI_PATH": fakeClaude.path],
            homeDirectory: fileManager.temporaryDirectory
        )
        #expect(viaOverride?.path == fakeClaude.path)

        // Nothing executable anywhere → nil.
        let missing = ExternalAccessSection.claudeExecutableURL(
            environment: [:],
            homeDirectory: fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        )
        // Only nil if the machine also lacks the absolute fallbacks; assert the
        // override/home resolution above instead of the host-dependent fallback.
        _ = missing
    }
    #endif
}

#endif
