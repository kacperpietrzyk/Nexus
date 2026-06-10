import NexusCore
import NexusUI
import SwiftUI

/// Spec `docs/05_MODULE_TODAY.md` §Projects card: "project row height 46–52 pt".
private let projectRowMinHeight: CGFloat = 46
/// Row hover wash — same calibration as the kit's task-row hover
/// (`LiquidListKit`): subtle fill, no scale.
private let projectRowHoverFill = Color.white.opacity(0.04)

/// `Projects` card (spec §Main bottom row 1): active projects with a real
/// completion progress line (done/total tasks), the lifecycle status as phase
/// metadata, and a right-aligned percentage.
struct TodayProjectsCard: View {

    let projects: [LiquidProjectProgress]
    let onOpenProjects: () -> Void

    var body: some View {
        LiquidGlassCard("Projects") {
            if projects.isEmpty {
                LiquidEmptyState(
                    systemImage: "square.stack.3d.up",
                    message: "No active projects right now."
                ) {
                    LiquidPrimaryButton("Open Projects", action: onOpenProjects)
                }
                .frame(maxHeight: .infinity)
            } else {
                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    ForEach(projects) { entry in
                        TodayProjectRow(entry: entry, action: onOpenProjects)
                    }
                    Spacer(minLength: 0)
                    LiquidCardFooterLink("View all projects", action: onOpenProjects)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
    }
}

private struct TodayProjectRow: View {
    let entry: LiquidProjectProgress
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                HStack(spacing: DS.Space.xs) {
                    Image(systemName: nexusProjectGlyph(named: entry.project.color))
                        // Spec §Projects card: "project icon left 14 pt".
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(DS.ColorToken.textSecondary)
                    Text(entry.project.name)
                        .font(DS.FontToken.bodyStrong)
                        .foregroundStyle(DS.ColorToken.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: DS.Space.s)
                    Text("\(Int((entry.fraction * 100).rounded()))%")
                        .font(DS.FontToken.metadata)
                        .foregroundStyle(DS.ColorToken.textSecondary)
                        .monospacedDigit()
                }
                LiquidProgressLine(value: entry.fraction)
                Text(Self.statusLabel(entry.project.status))
                    .font(DS.FontToken.metadata)
                    .foregroundStyle(DS.ColorToken.textTertiary)
                    .lineLimit(1)
            }
            .padding(DS.Space.s)
            .frame(minHeight: projectRowMinHeight)
            .background {
                RoundedRectangle(cornerRadius: DS.Radius.s, style: .continuous)
                    .fill(hovering ? projectRowHoverFill : .clear)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open project \(entry.project.name)")
        #if os(macOS)
        .onHover { value in
            withAnimation(DS.Motion.hover) { hovering = value }
        }
        #endif
    }

    /// Phase metadata = the project's real lifecycle status (spec §Projects
    /// card "phase metadata"; raw values are CloudKit-bound — display copy here).
    static func statusLabel(_ status: ProjectStatus) -> String {
        switch status {
        case .backlog: return "Backlog"
        case .planned: return "Planned"
        case .active: return "Active"
        case .inReview: return "In review"
        case .completed: return "Completed"
        case .cancelled: return "Cancelled"
        }
    }
}
