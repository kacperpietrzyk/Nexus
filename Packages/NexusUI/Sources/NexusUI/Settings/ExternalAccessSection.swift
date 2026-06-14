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
        VStack(alignment: .leading, spacing: DS.Space.l) {
            LiquidGlassCard("External Access") {
                VStack(spacing: 0) {
                    // Description
                    Text(
                        """
                        Claude Desktop, Claude Code, and other MCP clients can access tasks through a local Model \
                        Context Protocol server. Single-machine, no network exposure.
                        """
                    )
                    .font(DS.FontToken.caption)
                    .foregroundStyle(DS.ColorToken.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, DS.Space.s)

                    Divider()
                        .overlay(DS.ColorToken.strokeHairline)

                    // MCP server toggle
                    HStack {
                        Text("MCP server")
                            .font(DS.FontToken.body)
                            .foregroundStyle(DS.ColorToken.textPrimary)
                        Spacer()
                        Toggle("", isOn: $enabled)
                            .labelsHidden()
                            .toggleStyle(.switch)
                    }
                    .frame(minHeight: 44)

                    Divider()
                        .overlay(DS.ColorToken.strokeHairline)

                    // Status row
                    HStack {
                        Text("Status")
                            .font(DS.FontToken.body)
                            .foregroundStyle(DS.ColorToken.textPrimary)
                        Spacer()
                        // §3 emphasis: conveys active state by ink brightness;
                        // enabled is the salient state → textPrimary;
                        // off is settled-low → textSecondary.
                        Text(enabled ? "running" : "off")
                            .font(DS.FontToken.body)
                            .foregroundStyle(enabled ? DS.ColorToken.textPrimary : DS.ColorToken.textSecondary)
                    }
                    .frame(minHeight: 44)

                    Divider()
                        .overlay(DS.ColorToken.strokeHairline)

                    // Sidecar path row
                    HStack {
                        Text("Sidecar")
                            .font(DS.FontToken.body)
                            .foregroundStyle(DS.ColorToken.textPrimary)
                        Spacer()
                        Text(sidecarPath)
                            .font(DS.FontToken.metadata.monospaced())
                            .foregroundStyle(DS.ColorToken.textTertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .frame(minHeight: 44)

                    Divider()
                        .overlay(DS.ColorToken.strokeHairline)

                    // Copy buttons
                    HStack(spacing: DS.Space.m) {
                        NexusButton(
                            variant: .primary,
                            size: .sm,
                            action: { copyClaudeDesktopConfig() },
                            label: { Text("Copy Claude Desktop config") }
                        )
                        NexusButton(
                            variant: .default,
                            size: .sm,
                            action: { copyClaudeCodeCommand() },
                            label: { Text("Copy Claude Code command") }
                        )
                        Spacer()
                    }
                    .padding(.vertical, DS.Space.s)

                    // Copy feedback
                    copyStatusView
                    commandCopyStatusView
                }
            }

            LiquidGlassCard("Recent activity") {
                AgentActivityLogView(log: activityLog)
            }
        }
    }

    @ViewBuilder
    private var copyStatusView: some View {
        switch copyStatus {
        case .idle:
            EmptyView()
        case .copied:
            // §3 categorical: checkmark.circle.fill glyph carries success
            // semantic; no hue.
            Label(
                "Copied. Paste into ~/Library/Application Support/Claude/claude_desktop_config.json",
                systemImage: "checkmark.circle.fill"
            )
            .foregroundStyle(DS.ColorToken.textSecondary)
            .font(DS.FontToken.caption)
        case .failed(let message):
            // §3 categorical: exclamationmark.triangle carries error semantic;
            // ink steps to most-salient.
            Label(message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(DS.ColorToken.textPrimary)
                .font(DS.FontToken.caption)
        }
    }

    @ViewBuilder
    private var commandCopyStatusView: some View {
        switch commandCopyStatus {
        case .idle:
            EmptyView()
        case .copied:
            Label("Copied. Paste into a terminal, then restart Claude Code.", systemImage: "checkmark.circle.fill")
                .foregroundStyle(DS.ColorToken.textSecondary)
                .font(DS.FontToken.caption)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(DS.ColorToken.textPrimary)
                .font(DS.FontToken.caption)
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
