import NexusUI
import SwiftUI

public struct AgentScheduleEditorSection: View {
    public let context: AgentSettingsContext

    public init(context: AgentSettingsContext) {
        self.context = context
    }

    public var body: some View {
        if let store = context.scheduleStore {
            AgentScheduleEditorContent(
                store: store,
                threadStore: AgentThreadStore(context: context.auditContext)
            )
        } else {
            LiquidGlassCard("Schedules") {
                Text("Schedules are unavailable in this context.")
                    .font(DS.FontToken.caption)
                    .foregroundStyle(DS.ColorToken.textMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

private struct AgentScheduleEditorContent: View {
    @StateObject private var viewModel: AgentScheduleEditorViewModel
    @State private var threads: [AgentThread] = []
    @State private var draft: AgentScheduleEditorDraft?

    private let threadStore: AgentThreadStore

    init(store: any AgentScheduleStoreProviding, threadStore: AgentThreadStore) {
        _viewModel = StateObject(wrappedValue: AgentScheduleEditorViewModel(store: store))
        self.threadStore = threadStore
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            LiquidGlassCard("Schedules") {
                VStack(alignment: .leading, spacing: 0) {
                    if viewModel.schedules.isEmpty {
                        NexusEmptyState(
                            systemImage: "calendar.badge.clock",
                            title: "No schedules yet."
                        )
                    } else {
                        ForEach(Array(viewModel.schedules.enumerated()), id: \.element.id) { index, schedule in
                            if index > 0 {
                                Divider()
                                    .overlay(DS.ColorToken.strokeHairline)
                            }
                            scheduleRow(schedule)
                                .padding(.vertical, DS.Space.s)
                        }
                    }

                    Divider()
                        .overlay(DS.ColorToken.strokeHairline)

                    Button {
                        draft = .new()
                    } label: {
                        Label("Add schedule", systemImage: "plus")
                            .font(DS.FontToken.body.weight(.medium))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(NexusPressableButtonStyle())
                    .foregroundStyle(DS.ColorToken.textPrimary)
                    .frame(minHeight: 44)
                }
            }
            Text("Cron is validated before save.")
                .font(DS.FontToken.caption)
                .foregroundStyle(DS.ColorToken.textMuted)
        }
        .onAppear(perform: reload)
        .sheet(item: $draft) { draft in
            AgentScheduleEditorSheet(
                draft: draft,
                threads: threads,
                onCancel: { self.draft = nil },
                onSave: save
            )
        }
    }

    private func reload() {
        viewModel.reload()
        threads = (try? threadStore.allActive()) ?? []
    }

    private func scheduleRow(_ schedule: AgentSchedule) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(schedule.name)
                        .font(DS.FontToken.body)
                        .fontWeight(.bold)
                        .foregroundStyle(DS.ColorToken.textPrimary)

                    Text(schedule.cronExpression)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(DS.ColorToken.textMuted)
                }

                Spacer(minLength: 12)

                Toggle("Enabled", isOn: binding(for: schedule))
                    .labelsHidden()

                Button {
                    draft = .existing(schedule)
                } label: {
                    Image(systemName: "pencil")
                }
                .buttonStyle(NexusPressableButtonStyle())
                .help("Edit schedule")
            }

            Text(schedule.prompt)
                .font(DS.FontToken.caption)
                .foregroundStyle(DS.ColorToken.textMuted)
                .lineLimit(2)

            HStack(spacing: 8) {
                if let threadName = threadName(for: schedule.threadID) {
                    NexusBadge(threadName, tone: .muted)
                }
                if let modelHint = AgentScheduleModelHintDisplay.badgeTitle(for: schedule.modelHint) {
                    NexusBadge(modelHint, tone: .info)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func binding(for schedule: AgentSchedule) -> Binding<Bool> {
        Binding(
            get: { schedule.enabled },
            set: { enabled in
                try? viewModel.setEnabled(enabled, id: schedule.id)
            }
        )
    }

    private func threadName(for id: UUID?) -> String? {
        guard let id else { return nil }
        return threads.first { $0.id == id }?.title ?? "Pinned thread"
    }

    private func save(_ values: AgentScheduleEditorValues) throws {
        try viewModel.save(
            id: values.id,
            name: values.name,
            cronExpression: values.cronExpression,
            prompt: values.prompt,
            enabled: values.enabled,
            threadID: values.threadID,
            modelHint: values.modelHint
        )
        reload()
        draft = nil
    }
}

private struct AgentScheduleEditorSheet: View {
    @State private var name: String
    @State private var cronExpression: String
    @State private var prompt: String
    @State private var enabled: Bool
    @State private var threadID: UUID?
    @State private var modelHint: String?
    @State private var selectedPreset: String
    @State private var validationError: String?

    private let id: UUID?
    private let threads: [AgentThread]
    private let onCancel: () -> Void
    private let onSave: (AgentScheduleEditorValues) throws -> Void

    init(
        draft: AgentScheduleEditorDraft,
        threads: [AgentThread],
        onCancel: @escaping () -> Void,
        onSave: @escaping (AgentScheduleEditorValues) throws -> Void
    ) {
        self.id = draft.scheduleID
        self.threads = threads
        self.onCancel = onCancel
        self.onSave = onSave
        _name = State(initialValue: draft.name)
        _cronExpression = State(initialValue: draft.cronExpression)
        _prompt = State(initialValue: draft.prompt)
        _enabled = State(initialValue: draft.enabled)
        _threadID = State(initialValue: draft.threadID)
        _modelHint = State(initialValue: AgentScheduleModelHintDisplay.editableValue(for: draft.modelHint))
        _selectedPreset = State(initialValue: Self.presetID(for: draft.cronExpression))
    }

    var body: some View {
        NavigationStack {
            Form {
                SwiftUI.Section("Schedule") {
                    TextField("Name", text: $name)

                    Picker("Cron preset", selection: $selectedPreset) {
                        ForEach(Self.presets) { preset in
                            Text(preset.label).tag(preset.id)
                        }
                    }
                    .onChange(of: selectedPreset) { _, newValue in
                        guard let preset = Self.presets.first(where: { $0.id == newValue }),
                            let expression = preset.expression
                        else { return }
                        cronExpression = expression
                    }

                    TextField("Cron expression", text: $cronExpression)
                        .font(.system(.body, design: .monospaced))

                    Toggle("Enabled", isOn: $enabled)
                }

                SwiftUI.Section("Prompt") {
                    TextEditor(text: $prompt)
                        .frame(minHeight: 120)
                }

                SwiftUI.Section("Routing") {
                    Picker("Pin to thread", selection: $threadID) {
                        Text("Default thread").tag(UUID?.none)
                        ForEach(threads) { thread in
                            Text(thread.title.isEmpty ? "Untitled thread" : thread.title)
                                .tag(Optional(thread.id))
                        }
                    }

                    Picker("Model hint", selection: $modelHint) {
                        Text("Auto").tag(String?.none)
                    }
                }

                if let validationError {
                    SwiftUI.Section {
                        // §3 categorical: Semantic.negative → Text.primary;
                        // standalone caption-style error text with no glyph,
                        // structurally identical to slice-1 `Text("Denied")`
                        // — ink steps to most-salient, no weight bump (§2
                        // LabPalette.ink).
                        Text(validationError)
                            .font(DS.FontToken.caption)
                            .foregroundStyle(DS.ColorToken.textPrimary)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(id == nil ? "New schedule" : "Edit schedule")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(nameTrimmed.isEmpty || promptTrimmed.isEmpty)
                }
            }
        }
        .frame(minHeight: 520)
    }

    private func save() {
        do {
            _ = try CronExpression(cronExpression)
            try onSave(
                AgentScheduleEditorValues(
                    id: id,
                    name: nameTrimmed,
                    cronExpression: cronExpression,
                    prompt: promptTrimmed,
                    enabled: enabled,
                    threadID: threadID,
                    modelHint: modelHint
                )
            )
        } catch is CronExpressionError {
            validationError = "Enter a valid five-field cron expression."
        } catch {
            validationError = error.localizedDescription
        }
    }

    private var nameTrimmed: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var promptTrimmed: String {
        prompt.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func presetID(for expression: String) -> String {
        presets.first { $0.expression == expression }?.id ?? "custom"
    }

    private static let presets: [CronPreset] = [
        CronPreset(id: "morning", label: "Every morning", expression: "0 8 * * *"),
        CronPreset(id: "weekday", label: "Weekday morning", expression: "0 8 * * 1-5"),
        CronPreset(id: "hourly", label: "Hourly", expression: "0 * * * *"),
        CronPreset(id: "thirty", label: "Every 30 minutes", expression: "*/30 * * * *"),
        CronPreset(id: "custom", label: "Custom", expression: nil),
    ]
}

private struct CronPreset: Identifiable {
    let id: String
    let label: String
    let expression: String?
}

private struct AgentScheduleEditorDraft: Identifiable {
    let id = UUID()
    let scheduleID: UUID?
    let name: String
    let cronExpression: String
    let prompt: String
    let enabled: Bool
    let threadID: UUID?
    let modelHint: String?

    static func new() -> AgentScheduleEditorDraft {
        AgentScheduleEditorDraft(
            scheduleID: nil,
            name: "",
            cronExpression: "0 8 * * *",
            prompt: "",
            enabled: true,
            threadID: nil,
            modelHint: nil
        )
    }

    static func existing(_ schedule: AgentSchedule) -> AgentScheduleEditorDraft {
        AgentScheduleEditorDraft(
            scheduleID: schedule.id,
            name: schedule.name,
            cronExpression: schedule.cronExpression,
            prompt: schedule.prompt,
            enabled: schedule.enabled,
            threadID: schedule.threadID,
            modelHint: AgentScheduleModelHintDisplay.editableValue(for: schedule.modelHint)
        )
    }
}

enum AgentScheduleModelHintDisplay {
    static func badgeTitle(for modelHint: String?) -> String? {
        guard let normalized = normalizedModelHint(modelHint) else { return nil }
        return normalized == "auto" ? "Auto" : nil
    }

    static func editableValue(for _: String?) -> String? {
        nil
    }

    private static func normalizedModelHint(_ modelHint: String?) -> String? {
        let trimmed = modelHint?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let trimmed, !trimmed.isEmpty else { return nil }

        switch trimmed {
        case "auto", "openai", "byok", "claude", "claudeshell", "claude-shell", "local":
            return "auto"
        default:
            return nil
        }
    }
}

private struct AgentScheduleEditorValues {
    let id: UUID?
    let name: String
    let cronExpression: String
    let prompt: String
    let enabled: Bool
    let threadID: UUID?
    let modelHint: String?
}
