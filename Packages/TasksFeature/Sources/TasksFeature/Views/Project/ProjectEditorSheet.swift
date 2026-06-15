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
    @State private var clientID: UUID?
    @State private var clientName: String = ""
    @State private var clientPickerPresented = false
    @State private var customFields: [String: String]
    @State private var newFieldKey = ""
    @State private var newFieldValue = ""
    @State var keyDates: [ProjectExecutionModel.KeyDateDraft] = []
    @State var newAnchorKey = ""
    @State var newKeyDateLabel = ""
    @State var newKeyDate = Date.now
    @State var newKeyDateContractual = false
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
        self._clientID = State(initialValue: project?.clientID)
        self._customFields = State(initialValue: project?.customFields ?? [:])
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

            VStack(alignment: .leading, spacing: 8) {
                Text("Type")
                    .nexusType(.eyebrow)
                    .foregroundStyle(NexusColor.Text.muted)

                NexusSelect(
                    selection: $type,
                    options: ProjectType.allCases,
                    label: { $0.displayName },
                    accessibilityLabel: "Type"
                )
                .onChange(of: type) { _, newType in
                    if let s = stage, !newType.stages.contains(s) { stage = nil }
                }
            }

            if !type.stages.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Stage")
                        .nexusType(.eyebrow)
                        .foregroundStyle(NexusColor.Text.muted)

                    NexusSelect(
                        selection: $stage,
                        options: [ProjectStage?.none] + type.stages.map { ProjectStage?.some($0) },
                        label: { $0?.displayName ?? "—" },
                        accessibilityLabel: "Stage"
                    )
                }
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

            Button {
                clientPickerPresented = true
            } label: {
                HStack {
                    Text("Client")
                        .nexusType(.body)
                        .foregroundStyle(NexusColor.Text.muted)
                    Spacer()
                    Text(clientName.isEmpty ? "None" : clientName)
                        .nexusType(.body)
                        .foregroundStyle(NexusColor.Text.primary)
                }
                .padding(.horizontal, 12)
                .frame(height: 36)
                .background(NexusColor.Background.control, in: RoundedRectangle(cornerRadius: NexusRadius.r2))
                .overlay {
                    RoundedRectangle(cornerRadius: NexusRadius.r2)
                        .strokeBorder(NexusColor.Line.regular, lineWidth: 1)
                }
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $clientPickerPresented) {
                OrganizationPickerSheet { selected in
                    clientID = selected
                    refreshClientName()
                }
            }

            customFieldsSection

            keyDatesSection

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
        .task {
            refreshClientName()
            if let project {
                loadKeyDates(context: modelContext, projectID: project.id)
            }
        }
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

    @MainActor
    private func refreshClientName() {
        guard let clientID else { clientName = ""; return }
        clientName =
            (try? OrganizationRepository(context: modelContext).find(id: clientID))?.name ?? ""
    }

    /// Project lifecycle picker (Projects tier, spec §4.1). Persisted via
    /// `ProjectRepository.setStatus`; archive stays a separate, orthogonal action.
    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Status")
                .nexusType(.eyebrow)
                .foregroundStyle(NexusColor.Text.muted)

            NexusSelect(
                selection: $status,
                options: ProjectStatus.allCases,
                label: { statusLabel($0) },
                accessibilityLabel: "Status"
            )
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

    private var customFieldsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Custom fields")
                .nexusType(.eyebrow)
                .foregroundStyle(NexusColor.Text.muted)

            ForEach(customFields.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                HStack {
                    Text(key)
                        .nexusType(.body)
                        .foregroundStyle(NexusColor.Text.muted)
                    Spacer()
                    Text(value)
                        .nexusType(.body)
                        .foregroundStyle(NexusColor.Text.primary)
                    Button {
                        customFields[key] = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(NexusColor.Text.tertiary)
                }
            }

            // Compact triple-field add row — 30pt / 8pt horizontal padding (vs the
            // 36pt / 12pt single-field rows above) so three controls fit one HStack.
            HStack {
                TextField("key", text: $newFieldKey)
                    .textFieldStyle(.plain)
                    .nexusType(.body)
                    .foregroundStyle(NexusColor.Text.primary)
                    .padding(.horizontal, 8)
                    .frame(height: 30, alignment: .leading)
                    .frame(maxWidth: 140)
                    .background(NexusColor.Background.control, in: RoundedRectangle(cornerRadius: NexusRadius.r2))
                    .overlay {
                        RoundedRectangle(cornerRadius: NexusRadius.r2)
                            .strokeBorder(NexusColor.Line.regular, lineWidth: 1)
                    }

                TextField("value", text: $newFieldValue)
                    .textFieldStyle(.plain)
                    .nexusType(.body)
                    .foregroundStyle(NexusColor.Text.primary)
                    .padding(.horizontal, 8)
                    .frame(height: 30)
                    .background(NexusColor.Background.control, in: RoundedRectangle(cornerRadius: NexusRadius.r2))
                    .overlay {
                        RoundedRectangle(cornerRadius: NexusRadius.r2)
                            .strokeBorder(NexusColor.Line.regular, lineWidth: 1)
                    }

                Button {
                    // Trim matches trimmedName/trimmedVendor; an existing key is overwritten.
                    let k = newFieldKey.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !k.isEmpty else { return }
                    customFields[k] = newFieldValue.trimmingCharacters(in: .whitespacesAndNewlines)
                    newFieldKey = ""
                    newFieldValue = ""
                } label: {
                    Image(systemName: "plus.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(NexusColor.Text.primary)
            }
        }
    }

    @MainActor
    private func save() {
        let cleanedName = trimmedName
        guard !cleanedName.isEmpty else { return }

        let repository = ProjectRepository(context: modelContext)
        do {
            if let project {
                try updateProject(project, cleanedName: cleanedName, using: repository)
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
                if let clientID {
                    try repository.setClient(clientID, on: created)
                }
                for (k, v) in customFields {
                    try repository.setCustomField(key: k, value: v, on: created)
                }
                try applyKeyDateDiff(projectID: created.id, context: modelContext)
            }
            onSave?()
            dismiss()
        } catch {
            self.error = String(describing: error)
        }
    }

    @MainActor
    private func updateProject(
        _ project: Project,
        cleanedName: String,
        using repository: ProjectRepository
    ) throws {
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
        if project.clientID != clientID {
            try repository.setClient(clientID, on: project)
        }
        try applyCustomFieldDiff(from: project.customFields, to: customFields, on: project, using: repository)
        try applyKeyDateDiff(projectID: project.id, context: modelContext)
    }

    @MainActor
    private func applyCustomFieldDiff(
        from current: [String: String],
        to updated: [String: String],
        on project: Project,
        using repository: ProjectRepository
    ) throws {
        guard current != updated else { return }
        for key in Set(current.keys).union(updated.keys) where current[key] != updated[key] {
            try repository.setCustomField(key: key, value: updated[key], on: project)
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
