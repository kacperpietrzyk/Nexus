import NexusCore
import NexusUI
import SwiftData
import SwiftUI

/// Project Execution header (spec §Header): breadcrumb `Projects › name`,
/// identity glyph + serif display name + editable status chip, the canonical
/// note's first line as the description, real created/updated dates, and the
/// live progress line.
///
/// Honest reductions vs the mockup: no owner/team avatars (single-user app),
/// no share action (no sharing backend), no favorite star (no backend field).
struct ProjectHeader: View {
    @Environment(\.modelContext) private var modelContext

    let project: Project
    let descriptionLine: String?
    let progress: Double
    var stage: ProjectStage?
    var clientName: String?
    let onBack: () -> Void
    let onEdit: () -> Void

    @State private var statusError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            breadcrumb

            HStack(spacing: DS.Space.m) {
                Image(systemName: nexusProjectGlyph(named: project.color))
                    // 20 pt identity glyph sits optically level with the 28 pt
                    // serif display title; no DS icon-size token at this scale.
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(DS.ColorToken.textSecondary)
                    .accessibilityHidden(true)

                Text(project.name)
                    .font(DS.FontToken.displayMedium)
                    .foregroundStyle(DS.ColorToken.textPrimary)
                    .lineLimit(1)

                statusMenu

                if let stage {
                    LiquidPill(stage.displayName, color: DS.ColorToken.statusNeutral, filled: false)
                }

                Spacer(minLength: DS.Space.m)

                LiquidIconButton(
                    systemImage: "pencil",
                    accessibilityLabel: "Edit project",
                    action: onEdit
                )
            }

            if let descriptionLine {
                Text(descriptionLine)
                    .font(DS.FontToken.body)
                    .foregroundStyle(DS.ColorToken.textSecondary)
                    .lineLimit(2)
            }

            HStack(alignment: .firstTextBaseline, spacing: DS.Space.m) {
                Text(
                    "Created \(Self.dateFormatter.string(from: project.createdAt))"
                        + "  ·  Updated \(Self.dateFormatter.string(from: project.updatedAt))"
                )
                .font(DS.FontToken.metadata)
                .foregroundStyle(DS.ColorToken.textTertiary)

                if let clientName, !clientName.isEmpty {
                    Text("·")
                        .font(DS.FontToken.metadata)
                        .foregroundStyle(DS.ColorToken.textTertiary)
                    Text(clientName)
                        .font(DS.FontToken.metadata)
                        .foregroundStyle(DS.ColorToken.textSecondary)
                }

                if let vendor = project.vendor, !vendor.isEmpty {
                    Text("·")
                        .font(DS.FontToken.metadata)
                        .foregroundStyle(DS.ColorToken.textTertiary)
                    Text(vendor)
                        .font(DS.FontToken.metadata)
                        .foregroundStyle(DS.ColorToken.textSecondary)
                }

                if let statusError {
                    Text(statusError)
                        .font(DS.FontToken.metadata)
                        .foregroundStyle(DS.ColorToken.statusDanger)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }

            progressBlock
        }
    }

    // MARK: - Breadcrumb

    private var breadcrumb: some View {
        HStack(spacing: DS.Space.xs) {
            Button(action: onBack) {
                Text("Projects")
                    .font(DS.FontToken.metadata)
                    .foregroundStyle(DS.ColorToken.textTertiary)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("All projects")

            Text("›")
                .font(DS.FontToken.metadata)
                .foregroundStyle(DS.ColorToken.textMuted)
                .accessibilityHidden(true)

            Text(project.name)
                .font(DS.FontToken.metadata)
                .foregroundStyle(DS.ColorToken.textSecondary)
                .lineLimit(1)
        }
    }

    // MARK: - Status chip

    /// Editable status chip: a `LiquidPill` fronting the EXISTING lifecycle
    /// mutation seam (`ProjectRepository.setStatus` — the same write path the
    /// old `ProjectPageView` status menu used).
    private var statusMenu: some View {
        Menu {
            ForEach(ProjectStatus.allCases, id: \.self) { status in
                Button {
                    setStatus(status)
                } label: {
                    if status == project.status {
                        Label(ProjectFormatters.statusLabel(status), systemImage: "checkmark")
                    } else {
                        Text(ProjectFormatters.statusLabel(status))
                    }
                }
            }
        } label: {
            LiquidPill(
                ProjectFormatters.statusLabel(project.status),
                color: Self.statusColor(project.status),
                filled: true
            )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .fixedSize()
        .accessibilityLabel("Project status: \(ProjectFormatters.statusLabel(project.status))")
    }

    @MainActor
    private func setStatus(_ status: ProjectStatus) {
        guard status != project.status else { return }
        do {
            try ProjectRepository(context: modelContext).setStatus(status, on: project)
            statusError = nil
        } catch {
            statusError = String(describing: error)
        }
    }

    /// Lifecycle → accent mapping for the status chip (spec shows a tinted
    /// "On Track"-style chip; statuses map onto the DS accent ramp).
    static func statusColor(_ status: ProjectStatus) -> Color {
        switch status {
        case .backlog: return DS.ColorToken.statusNeutral
        case .planned: return DS.ColorToken.accentBlue
        case .active: return DS.ColorToken.accentGreen
        case .inReview: return DS.ColorToken.accentPurple
        case .completed: return DS.ColorToken.accentCyan
        case .cancelled: return DS.ColorToken.statusDanger
        }
    }

    // MARK: - Progress

    private var progressBlock: some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            HStack {
                Text("Progress")
                    .font(DS.FontToken.caption)
                    .foregroundStyle(DS.ColorToken.textTertiary)
                Spacer()
                Text("\(Int((progress * 100).rounded()))%")
                    .font(DS.FontToken.caption.monospacedDigit())
                    .foregroundStyle(DS.ColorToken.textSecondary)
            }
            LiquidProgressLine(value: progress)
        }
        .padding(.top, DS.Space.xs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Progress \(Int((progress * 100).rounded())) percent")
    }

    /// English UI rule: explicit en_US (system locale may be pl_PL).
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateFormat = "MMM d, yyyy"
        return formatter
    }()
}
