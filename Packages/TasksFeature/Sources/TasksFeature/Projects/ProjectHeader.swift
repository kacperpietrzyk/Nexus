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
    var clientName: String?
    let onBack: () -> Void
    let onEdit: () -> Void

    @State private var statusError: String?
    @State private var addingKeyDate = false
    @State private var labelDraft = ""
    @State private var dateDraft = Date.now
    @State private var contractualDraft = false

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            #if !os(macOS)
            breadcrumb
            #endif

            HStack(spacing: DS.Space.m) {
                Image(systemName: nexusProjectGlyph(token: project.color, id: project.id))
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
                stageMenu
                Spacer(minLength: DS.Space.m)
                addKeyDateButton
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

            metadataRow
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

    // MARK: - Stage menu

    /// Editable stage chip: shown when the project type has a pipeline preset.
    /// Mirrors `statusMenu` — writes via `ProjectRepository`, refreshes via
    /// `reloadOnStoreChange` (no manual reload needed).
    @ViewBuilder
    private var stageMenu: some View {
        if !project.type.stages.isEmpty {
            Menu {
                ForEach(project.type.stages, id: \.self) { s in
                    Button {
                        setStage(s)
                    } label: {
                        if s == project.stage {
                            Label(s.displayName, systemImage: "checkmark")
                        } else {
                            Text(s.displayName)
                        }
                    }
                }
                if project.stage != nil {
                    Divider()
                    Button("Clear stage", role: .destructive) { clearStage() }
                }
            } label: {
                LiquidPill(
                    project.stage?.displayName ?? "Set stage",
                    color: DS.ColorToken.statusNeutral,
                    filled: false
                )
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .buttonStyle(.plain)
            .fixedSize()
            .accessibilityLabel(
                project.stage.map { "Stage: \($0.displayName)" } ?? "Set stage"
            )
        }
    }

    @MainActor
    private func setStage(_ s: ProjectStage) {
        do {
            try ProjectRepository(context: modelContext).setStage(s, on: project)
            statusError = nil
        } catch {
            statusError = String(describing: error)
        }
    }

    @MainActor
    private func clearStage() {
        do {
            try ProjectRepository(context: modelContext).clearStage(on: project)
            statusError = nil
        } catch {
            statusError = String(describing: error)
        }
    }

    // MARK: - Add key date

    private var addKeyDateButton: some View {
        LiquidIconButton(
            systemImage: "calendar.badge.plus",
            accessibilityLabel: "Add key date",
            action: { addingKeyDate = true }
        )
        .popover(isPresented: $addingKeyDate) {
            addKeyDateForm
        }
    }

    private var addKeyDateForm: some View {
        VStack(alignment: .leading, spacing: DS.Space.m) {
            Text("Add Key Date")
                .font(DS.FontToken.body.weight(.semibold))
                .foregroundStyle(DS.ColorToken.textPrimary)

            TextField("Label", text: $labelDraft)
                .textFieldStyle(.roundedBorder)

            DatePicker("Date", selection: $dateDraft, displayedComponents: .date)

            Toggle("Contractual", isOn: $contractualDraft)

            HStack {
                Spacer()
                Button("Save") {
                    saveKeyDate()
                }
                .disabled(labelDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(DS.Space.m)
        .frame(minWidth: 280)
    }

    @MainActor
    private func saveKeyDate() {
        let trimmed = labelDraft.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        do {
            try ProjectKeyDateRepository(context: modelContext).setKeyDate(
                projectID: project.id,
                anchorKey: UUID().uuidString,
                label: trimmed,
                date: dateDraft,
                isContractual: contractualDraft
            )
            statusError = nil
            addingKeyDate = false
            labelDraft = ""
            dateDraft = .now
            contractualDraft = false
        } catch {
            statusError = String(describing: error)
        }
    }

    // MARK: - Metadata row

    private var metadataRow: some View {
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
