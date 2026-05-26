import SwiftUI

#if os(macOS)

import AppKit
import NexusAgentTools

public struct ExternalAccessSection: View {
    @AppStorage(NexusPreferences.Keys.mcpEnabled) private var enabled = false
    @State private var copyStatus: CopyStatus = .idle
    @State private var addToClaudeCodeStatus: AddCLIStatus = .idle

    public let sidecarPath: String
    public let activityLog: AgentActivityLog
    public let isClaudeCLIAvailable: Bool

    public init(
        sidecarPath: String,
        activityLog: AgentActivityLog,
        isClaudeCLIAvailable: Bool
    ) {
        self.sidecarPath = sidecarPath
        self.activityLog = activityLog
        self.isClaudeCLIAvailable = isClaudeCLIAvailable
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

                Button("Add to Claude Code") { addToClaudeCode() }
                    .buttonStyle(.bordered)
                    .disabled(!isClaudeCLIAvailable || addToClaudeCodeStatus == .running)
            }
            .padding(.vertical, 4)

            copyStatusView
            addToClaudeCodeStatusView
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
    private var addToClaudeCodeStatusView: some View {
        switch addToClaudeCodeStatus {
        case .idle:
            EmptyView()
        case .running:
            Label("Adding to Claude Code...", systemImage: "clock")
                .foregroundStyle(.secondary)
                .font(.caption)
        case .added:
            // §3 categorical: Accent.solid → Text.secondary; the
            // `checkmark.circle.fill` glyph shape carries the success
            // semantic (oracle has no hue, §2 LabPalette.read).
            Label("Added to Claude Code.", systemImage: "checkmark.circle.fill")
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

    private func addToClaudeCode() {
        addToClaudeCodeStatus = .running
        let sidecarPath = sidecarPath
        Task {
            addToClaudeCodeStatus = await Self.addToClaudeCode(sidecarPath: sidecarPath)
        }
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
        ["claude", "mcp", "add", "--scope", "user", "nexus", sidecarPath]
    }

    nonisolated private static func addToClaudeCode(sidecarPath: String) async -> AddCLIStatus {
        await Task.detached(priority: .userInitiated) {
            runClaudeCodeAdd(sidecarPath: sidecarPath)
        }.value
    }

    nonisolated private static func runClaudeCodeAdd(sidecarPath: String, timeout: TimeInterval = 10) -> AddCLIStatus {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        task.arguments = claudeCodeArguments(sidecarPath: sidecarPath)

        let standardError = Pipe()
        task.standardError = standardError
        task.standardOutput = Pipe()

        do {
            try task.run()
        } catch {
            return .failed("Could not run claude CLI: \(error.localizedDescription)")
        }

        let deadline = Date().addingTimeInterval(timeout)
        while task.isRunning {
            if Date() >= deadline {
                task.terminate()
                return .failed("claude CLI timed out")
            }
            Thread.sleep(forTimeInterval: 0.05)
        }

        if task.terminationStatus == 0 {
            return .added
        }

        let errorData = standardError.fileHandleForReading.readDataToEndOfFile()
        let stderr =
            String(bytes: errorData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let suffix = stderr.isEmpty ? "" : ": \(stderr)"
        return .failed("claude CLI exited \(task.terminationStatus)\(suffix)")
    }

    private enum CopyStatus: Equatable {
        case idle
        case copied
        case failed(String)
    }

    private enum AddCLIStatus: Equatable {
        case idle
        case running
        case added
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
