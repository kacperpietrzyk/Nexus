import NexusCore
import NexusUI
import SwiftData
import SwiftUI

public struct ProjectEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    private let project: Project?
    private let onSave: (() -> Void)?

    @State private var name: String
    @State private var colorToken: String
    @State private var status: ProjectStatus
    @State private var type: ProjectType
    @State private var stage: ProjectStage?
    @State private var vendor: String
    @State private var error: String?

    public init(project: Project? = nil, onSave: (() -> Void)? = nil) {
        self.project = project
        self.onSave = onSave
        self._name = State(initialValue: project?.name ?? "")
        self._colorToken = State(initialValue: project?.color ?? ProjectColorToken.defaultName)
        self._status = State(initialValue: project?.status ?? .backlog)
        self._type = State(initialValue: project?.type ?? .generic)
        self._stage = State(initialValue: project?.stage)
        self._vendor = State(initialValue: project?.vendor ?? "")
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header

            VStack(alignment: .leading, spacing: 8) {
                Text("Name")
                    .nexusType(.eyebrow)
                    .foregroundStyle(NexusColor.Text.muted)

                TextField("Project name", text: $name)
                    .textFieldStyle(.plain)
                    .nexusType(.body)
                    .foregroundStyle(NexusColor.Text.primary)
                    .padding(.horizontal, 12)
                    .frame(height: 36)
                    .background(NexusColor.Background.control, in: RoundedRectangle(cornerRadius: NexusRadius.r2))
                    .overlay {
                        RoundedRectangle(cornerRadius: NexusRadius.r2)
                            .strokeBorder(NexusColor.Line.regular, lineWidth: 1)
                    }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Shape")
                    .nexusType(.eyebrow)
                    .foregroundStyle(NexusColor.Text.muted)

                HStack(spacing: 8) {
                    ForEach(ProjectColorToken.all) { token in
                        colorButton(token)
                    }
                }
            }

            statusSection

            Picker("Type", selection: $type) {
                ForEach(ProjectType.allCases, id: \.self) { t in
                    Text(t.displayName).tag(t)
                }
            }
            .pickerStyle(.menu)
            .onChange(of: type) { _, newType in
                if let s = stage, !newType.stages.contains(s) { stage = nil }
            }

            if !type.stages.isEmpty {
                Picker("Stage", selection: $stage) {
                    Text("—").tag(ProjectStage?.none)
                    ForEach(type.stages, id: \.self) { s in
                        Text(s.displayName).tag(ProjectStage?.some(s))
                    }
                }
                .pickerStyle(.menu)
            }

            TextField("Vendor / product", text: $vendor)
                .textFieldStyle(.plain)
                .nexusType(.body)
                .foregroundStyle(NexusColor.Text.primary)
                .padding(.horizontal, 12)
                .frame(height: 36)
                .background(NexusColor.Background.control, in: RoundedRectangle(cornerRadius: NexusRadius.r2))
                .overlay {
                    RoundedRectangle(cornerRadius: NexusRadius.r2)
                        .strokeBorder(NexusColor.Line.regular, lineWidth: 1)
                }

            ForEach(ProjectEditorAccessorySection.sections(for: project), id: \.self) { section in
                switch section {
                case .labels(let projectID):
                    ProjectLabelsSection(projectID: projectID)
                case .comments(let projectID):
                    VStack(alignment: .leading, spacing: 10) {
                        if let title = section.editorTitle {
                            Text(title)
                                .nexusType(.eyebrow)
                                .foregroundStyle(NexusColor.Text.muted)
                        }

                        CommentsSection(
                            itemID: projectID,
                            itemKind: .project,
                            repository: CommentRepository(context: modelContext)
                        )
                    }
                }
            }

            if let error {
                Text(error)
                    .nexusType(.caption)
                    .foregroundStyle(NexusColor.Text.primary)
            }

            HStack {
                Spacer()
                NexusButton(
                    variant: .ghost, size: .md, action: { dismiss() },
                    label: {
                        Text("Cancel")
                    })
                NexusButton(
                    variant: .primary, size: .md, action: save,
                    label: {
                        Text(project == nil ? "Create" : "Save")
                    }
                )
                .disabled(trimmedName.isEmpty)
            }
        }
        .padding(24)
        .frame(minWidth: 360)
        .background(NexusColor.Background.panel)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(project == nil ? "New Project" : "Edit Project")
                .font(NexusType.h2)
                .foregroundStyle(NexusColor.Text.primary)

            Text(project == nil ? "Create a root project for task grouping." : "Update the project label and shape.")
                .nexusType(.bodySmall)
                .foregroundStyle(NexusColor.Text.tertiary)
        }
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedVendor: String {
        vendor.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Project lifecycle picker (Projects tier, spec §4.1). Persisted via
    /// `ProjectRepository.setStatus`; archive stays a separate, orthogonal action.
    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Status")
                .nexusType(.eyebrow)
                .foregroundStyle(NexusColor.Text.muted)

            Picker("Status", selection: $status) {
                ForEach(ProjectStatus.allCases, id: \.self) { value in
                    Text(statusLabel(value)).tag(value)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .tint(NexusColor.Text.primary)
        }
    }

    private func statusLabel(_ status: ProjectStatus) -> String {
        switch status {
        case .backlog: return "Backlog"
        case .planned: return "Planned"
        case .active: return "Active"
        case .inReview: return "In Review"
        case .completed: return "Completed"
        case .cancelled: return "Cancelled"
        }
    }

    private func colorButton(_ token: ProjectColorToken) -> some View {
        let shapeLabel = projectShapeLabel(named: token.name)
        return Button {
            colorToken = token.name
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: NexusRadius.r2)
                    .fill(NexusColor.Background.control)
                    .frame(width: 24, height: 24)
                    .overlay {
                        RoundedRectangle(cornerRadius: NexusRadius.r2)
                            .strokeBorder(
                                colorToken == token.name ? NexusColor.Text.primary : NexusColor.Line.regular,
                                lineWidth: colorToken == token.name ? 2 : 1
                            )
                    }
                Image(systemName: nexusProjectGlyph(named: token.name))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(NexusColor.Text.primary)
            }
        }
        .buttonStyle(.plain)
        .help(shapeLabel)
        .accessibilityLabel(shapeLabel)
    }

    @MainActor
    private func save() {
        let cleanedName = trimmedName
        guard !cleanedName.isEmpty else { return }

        let repository = ProjectRepository(context: modelContext)
        do {
            if let project {
                if project.name != cleanedName {
                    try repository.rename(project, to: cleanedName)
                }
                if project.color != colorToken {
                    try repository.recolor(project, to: colorToken)
                }
                if project.status != status {
                    try repository.setStatus(status, on: project)
                }
                if project.type != type {
                    try repository.setType(type, on: project)
                }
                if project.stage != stage {
                    if let stage {
                        try repository.setStage(stage, on: project)
                    } else {
                        // No repo clearStage(): clear directly, but re-anchor statusRaw to the
                        // Status picker's chosen value so the coarse status set by the prior
                        // stage's coarseStatus doesn't linger stale.
                        project.stage = nil
                        project.statusRaw = status.rawValue
                        project.updatedAt = .now
                        try modelContext.save()
                    }
                }
                if (project.vendor ?? "") != trimmedVendor {
                    try repository.setVendor(trimmedVendor.isEmpty ? nil : trimmedVendor, on: project)
                }
            } else {
                let created = try repository.create(name: cleanedName, color: colorToken, type: type)
                if status != .backlog {
                    try repository.setStatus(status, on: created)
                }
                if let stage {
                    try repository.setStage(stage, on: created)
                }
                if !trimmedVendor.isEmpty {
                    try repository.setVendor(trimmedVendor, on: created)
                }
            }
            onSave?()
            dismiss()
        } catch {
            self.error = String(describing: error)
        }
    }
}

enum ProjectEditorAccessorySection: Hashable {
    case labels(UUID)
    case comments(UUID)

    var editorTitle: String? {
        switch self {
        case .labels:
            return nil
        case .comments:
            return "Comments"
        }
    }

    static func sections(for project: Project?) -> [ProjectEditorAccessorySection] {
        guard let project else { return [] }
        return [
            .labels(project.id),
            .comments(project.id),
        ]
    }
}

public struct ProjectColorToken: Identifiable, Hashable, Sendable {
    public let name: String
    public let label: String
    public let color: Color

    public var id: String { name }

    public static let defaultName = "azure"

    public static let all: [ProjectColorToken] = [
        .init(name: "azure", label: "Azure", color: NexusColor.Text.primary),
        .init(name: "gold", label: "Gold", color: NexusColor.Text.primary),
        .init(name: "emerald", label: "Emerald", color: NexusColor.Text.primary),
        .init(name: "rose", label: "Rose", color: NexusColor.Text.primary),
        .init(name: "violet", label: "Violet", color: NexusColor.Text.primary),
        .init(name: "slate", label: "Slate", color: NexusColor.Text.primary),
    ]

    /// Render-inert since MP-2.1 slice 3c — always returns `NexusColor.Text.primary` regardless of
    /// `name`; project differentiation is carried by SF Symbol shape (`nexusProjectGlyph(named:)`),
    /// not hue. Signature preserved for source compatibility.
    public static func color(named name: String) -> Color {
        all.first { $0.name == name }?.color ?? NexusColor.Text.primary
    }
}
