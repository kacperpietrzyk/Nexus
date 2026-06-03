import SwiftUI

#if os(macOS)

import AppKit
import NexusAgentTools

public struct ExternalAccessSection: View {
    @AppStorage(NexusPreferences.Keys.mcpEnabled) private var enabled = false
    @State private var copyStatus: CopyStatus = .idle
    @State private var commandCopyStatus: CopyStatus = .idle

    public let sidecarPath: String
    public let activityLog: AgentActivityLog

    public init(
        sidecarPath: String,
        activityLog: AgentActivityLog
    ) {
        self.sidecarPath = sidecarPath
        self.activityLog = activityLog
    }

    public var body: some View {
        Section {
            Text(
                """
                Claude Desktop, Claude Code, and other MCP clients can access tasks through a local Model Context Protocol \
                server. Single-machine, no network exposure.
                """
            )
            .font(.footnote)
            .foregroundStyle(.secondary)

            Toggle("MCP server", isOn: $enabled)

            LabeledContent("Status") {
                // §3 emphasis: Accent.solid → Text.primary; the oracle
                // conveys active state by ink brightness (§2 LabPalette.ink),
                // never hue. Enabled is the salient state → Text.primary;
                // off is settled-low → Text.secondary (§2 LabPalette.read).
                Text(enabled ? "running" : "off")
                    .foregroundStyle(enabled ? NexusColor.Text.primary : NexusColor.Text.secondary)
            }

            LabeledContent("Sidecar") {
                Text(sidecarPath)
                    .font(.system(.caption, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            HStack(spacing: 12) {
                Button("Copy Claude Desktop config") { copyClaudeDesktopConfig() }
                    .buttonStyle(.borderedProminent)

                Button("Copy Claude Code command") { copyClaudeCodeCommand() }
                    .buttonStyle(.bordered)
            }
            .padding(.vertical, 4)

            copyStatusView
            commandCopyStatusView
        } header: {
            nexusSettingsSectionHeader("External Access")
        }

        Section {
            NexusCard(.elev2, padding: 16) {
                AgentActivityLogView(log: activityLog)
            }
        } header: {
            nexusSettingsSectionHeader("Recent activity")
        }
    }

    @ViewBuilder
    private var copyStatusView: some View {
        switch copyStatus {
        case .idle:
            EmptyView()
        case .copied:
            // §3 categorical: Accent.solid → Text.secondary; the
            // `checkmark.circle.fill` glyph shape carries the success
            // semantic (oracle has no hue, §2 LabPalette.read).
            Label(
                "Copied. Paste into ~/Library/Application Support/Claude/claude_desktop_config.json",
                systemImage: "checkmark.circle.fill"
            )
            .foregroundStyle(NexusColor.Text.secondary)
            .font(.caption)
        case .failed(let message):
            // §3 categorical: Semantic.negative → Text.primary; the
            // `exclamationmark.triangle` glyph shape carries the error
            // semantic, ink steps to the most-salient (§2 LabPalette.ink).
            Label(message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(NexusColor.Text.primary)
                .font(.caption)
        }
    }

    @ViewBuilder
    private var commandCopyStatusView: some View {
        switch commandCopyStatus {
        case .idle:
            EmptyView()
        case .copied:
            // §3 categorical: Accent.solid → Text.secondary; the
            // `checkmark.circle.fill` glyph shape carries the success
            // semantic (oracle has no hue, §2 LabPalette.read).
            Label("Copied. Paste into a terminal, then restart Claude Code.", systemImage: "checkmark.circle.fill")
                .foregroundStyle(NexusColor.Text.secondary)
                .font(.caption)
        case .failed(let message):
            // §3 categorical: Semantic.negative → Text.primary; the
            // `exclamationmark.triangle` glyph shape carries the error
            // semantic, ink steps to the most-salient (§2 LabPalette.ink).
            Label(message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(NexusColor.Text.primary)
                .font(.caption)
        }
    }

    private func copyClaudeDesktopConfig() {
        do {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            copyStatus =
                pasteboard.setString(try Self.claudeDesktopConfig(sidecarPath: sidecarPath), forType: .string)
                ? .copied
                : .failed("Could not copy to clipboard")
        } catch {
            copyStatus = .failed("Could not encode Claude Desktop config")
        }
    }

    private func copyClaudeCodeCommand() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        commandCopyStatus =
            pasteboard.setString(Self.claudeCodeCommand(sidecarPath: sidecarPath), forType: .string)
            ? .copied
            : .failed("Could not copy to clipboard")
    }

    nonisolated static func claudeDesktopConfig(sidecarPath: String) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(
            ClaudeDesktopConfig(mcpServers: ["nexus": ClaudeDesktopMCPServer(command: sidecarPath)])
        )
        guard let snippet = String(bytes: data, encoding: .utf8) else {
            throw EncodingError.invalidValue(
                sidecarPath,
                EncodingError.Context(codingPath: [], debugDescription: "Could not encode Claude Desktop config")
            )
        }
        return snippet
    }

    nonisolated static func claudeCodeArguments(sidecarPath: String) -> [String] {
        ["mcp", "add", "--scope", "user", "nexus", sidecarPath]
    }

    /// The full, copy-paste-ready `claude mcp add` command for this sidecar.
    ///
    /// The Mac app is sandboxed, so it can neither locate nor spawn the external
    /// `claude` CLI (`homeDirectoryForCurrentUser` resolves to the container and
    /// `posix_spawn` of an outside binary is denied). Instead of running the CLI
    /// we hand the user a command to paste into a terminal. The sidecar path is
    /// POSIX single-quoted so spaces and quotes survive the paste.
    nonisolated static func claudeCodeCommand(sidecarPath: String) -> String {
        let quoted = "'" + sidecarPath.replacingOccurrences(of: "'", with: "'\\''") + "'"
        return (["claude"] + claudeCodeArguments(sidecarPath: sidecarPath).dropLast() + [quoted])
            .joined(separator: " ")
    }

    private enum CopyStatus: Equatable {
        case idle
        case copied
        case failed(String)
    }

}

private struct ClaudeDesktopConfig: Encodable {
    let mcpServers: [String: ClaudeDesktopMCPServer]
}

private struct ClaudeDesktopMCPServer: Encodable {
    let command: String
}

#endif
