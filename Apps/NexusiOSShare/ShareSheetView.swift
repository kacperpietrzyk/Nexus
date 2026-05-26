import NexusAI
import NexusCore
import NexusSync
import SwiftData
import SwiftUI
import TasksFeature

struct ShareSheetView: View {
    @State private var text: String
    @State private var parsedResult: ParseResult?
    @State private var isParsing = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    /// Shared SwiftData container used by both the live parser preview and `save()`.
    /// Opened once in `init`; `nil` means the App Group store failed to open and Save
    /// must stay disabled. The share extension uses the standard non-Claude-shell
    /// AIRouter; cloud access remains consent/quota gated and may be unavailable if
    /// extension Keychain access differs from the host app.
    private let container: ModelContainer?
    private let parser: CompositeNLParser
    private let onDone: (Bool) -> Void

    init(initialText: String, initialError: String? = nil, onDone: @escaping (Bool) -> Void) {
        self._text = State(initialValue: initialText)
        self.onDone = onDone

        do {
            let container = try Self.makeContainer()
            let router = AIComposition.makeRouter(container: container)
            self.container = container
            self.parser = TasksComposition.makeParser(router: router)
            self._errorMessage = State(initialValue: initialError)
        } catch {
            self.container = nil
            self.parser = TasksComposition.makeParser(
                router: AIRouter(
                    providers: [],
                    consent: InMemoryConsentStore(),
                    quota: InMemoryQuotaTracker(),
                    secrets: InMemorySecretStore()
                )
            )
            self._errorMessage = State(
                initialValue: initialError
                    ?? "Nexus could not open its shared store: \(error.localizedDescription)"
            )
        }
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                TextEditor(text: $text)
                    .font(.body)
                    .frame(minHeight: 160)
                    .padding(10)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(.quaternary)
                    }

                ParsedSummaryView(result: parsedResult, isParsing: isParsing)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }

                Spacer(minLength: 0)
            }
            .padding(20)
            .navigationTitle("Add to Nexus")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onDone(false)
                    }
                    .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await save() }
                    } label: {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text("Save")
                        }
                    }
                    .disabled(
                        isSaving
                            || container == nil
                            || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )
                }
            }
            .task(id: text) {
                await reparse(text)
            }
        }
    }

    @MainActor
    private func reparse(_ input: String) async {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            parsedResult = nil
            isParsing = false
            return
        }

        isParsing = true
        defer { isParsing = false }
        errorMessage = nil
        do {
            try await Task.sleep(for: .milliseconds(80))
            if Task.isCancelled { return }
            let result = await parser.parse(trimmed, locale: .autoupdatingCurrent, now: .now)
            if Task.isCancelled { return }
            parsedResult = result
        } catch {
            if !Task.isCancelled {
                errorMessage = "Parse failed: \(error.localizedDescription)"
            }
        }
    }

    @MainActor
    private func save() async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = "Task text cannot be empty."
            return
        }

        guard let container else {
            errorMessage = "Nexus shared store is unavailable; cannot save."
            return
        }

        isSaving = true
        defer { isSaving = false }

        let result = await parser.parse(trimmed, locale: .autoupdatingCurrent, now: .now)
        parsedResult = result

        do {
            let repository = TasksComposition.makeRepository(for: ModelContext(container))
            let task = try ShareTaskBuilder.task(from: result)
            try repository.insert(task)
            errorMessage = nil
            onDone(true)
        } catch ShareTaskBuilderError.emptyTitle {
            errorMessage = "Parser returned an empty task title."
        } catch {
            errorMessage = "Save failed: \(error.localizedDescription)"
        }
    }

    private static func makeContainer() throws -> ModelContainer {
        try NexusModelContainer.make(
            environment: ShareExtensionEnvironment(),
            groupContainerIdentifier: NexusModelContainer.appGroupIdentifier
        )
    }
}

private struct ParsedSummaryView: View {
    let result: ParseResult?
    let isParsing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Parsed")
                    .font(.headline)
                Spacer()
                if isParsing {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            if let result {
                VStack(alignment: .leading, spacing: 8) {
                    SummaryRow(label: "Title", value: result.title)
                    SummaryRow(label: "Due", value: result.dueAt.map(formatDate))
                    SummaryRow(label: "Start", value: result.startAt.map(formatDate))
                    SummaryRow(label: "End", value: result.endAt.map(formatDate))
                    SummaryRow(label: "Deadline", value: result.deadlineAt.map(formatDate))
                    SummaryRow(label: "Priority", value: result.priority?.label)
                    SummaryRow(label: "Tags", value: result.tags.isEmpty ? nil : result.tags.joined(separator: ", "))
                    SummaryRow(label: "Repeat", value: result.recurrence)
                }
            } else {
                Text("Nothing parsed yet.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    private func formatDate(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }
}

private struct SummaryRow: View {
    let label: String
    let value: String?

    var body: some View {
        if let value, !value.isEmpty {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 58, alignment: .leading)
                Text(value)
                    .font(.footnote)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Spacer(minLength: 0)
            }
        }
    }
}

private struct ShareExtensionEnvironment: NexusEnvironmentProviding {
    var cloudKitEnabled: Bool { false }
    var cloudKitContainerIdentifier: String { NexusEnvironment.containerIdentifier }
}

extension TaskPriority {
    fileprivate var label: String {
        switch self {
        case .none: return "None"
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        }
    }
}
