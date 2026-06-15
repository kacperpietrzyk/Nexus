import Foundation
import NexusAI
import NexusAgent
import NexusCore
import NexusUI
import SwiftData
import SwiftUI

enum TaskAssistUIAction: CaseIterable, Identifiable, Equatable {
    case refineTitle
    case refineBody
    case breakIntoSubtasks
    case suggestDueDate

    var id: Self { self }

    var label: String {
        switch self {
        case .refineTitle: return "Refine title"
        case .refineBody: return "Refine body"
        case .breakIntoSubtasks: return "Break into subtasks"
        case .suggestDueDate: return "Suggest due date"
        }
    }

    var systemImage: String {
        switch self {
        case .refineTitle: return "textformat"
        case .refineBody: return "text.alignleft"
        case .breakIntoSubtasks: return "checklist"
        case .suggestDueDate: return "calendar.badge.clock"
        }
    }

    var serviceAction: TaskAssistService.Action {
        switch self {
        case .refineTitle: return .refine(field: .title)
        case .refineBody: return .refine(field: .body)
        case .breakIntoSubtasks: return .breakIntoSubtasks()
        case .suggestDueDate: return .suggestDueDate(now: .now)
        }
    }
}

enum TaskAssistUIError: Error, Equatable {
    case aiUnavailable
    case repositoryUnavailable
    case emptySubtasks
}

enum TaskAssistErrorCopy {
    static func message(for error: Error) -> String {
        if let uiError = error as? TaskAssistUIError {
            return message(for: uiError)
        }

        if let assistError = error as? TaskAssistService.AssistError {
            return message(for: assistError)
        }

        if let routerError = error as? AIRouterError {
            return message(for: routerError)
        }

        let description = (error as? LocalizedError)?.errorDescription
        if let description, !description.isEmpty {
            return description
        }

        return "AI Assist could not finish this action. Try again."
    }

    private static func message(for error: TaskAssistUIError) -> String {
        switch error {
        case .aiUnavailable:
            return "AI is not available in this view yet. Check AI settings and try again."
        case .repositoryUnavailable:
            return "Subtasks cannot be created because task storage is not available. Reopen the task and try again."
        case .emptySubtasks:
            return "AI did not return any usable subtasks. Add more detail to the task and try again."
        }
    }

    private static func message(for error: TaskAssistService.AssistError) -> String {
        switch error {
        case .emptyRefinement(.title):
            return "AI returned an empty title. Add more detail to the task and try again."
        case .emptyRefinement(.body):
            return "AI returned an empty body. Add notes to the task and try again."
        case .invalidDateFormat:
            return "AI did not return a usable due date. Add a clearer timing hint and try again."
        case .pastDueDate:
            return "AI suggested a past due date. Add a future timing hint and try again."
        }
    }

    private static func message(for error: AIRouterError) -> String {
        switch error {
        case .noProviderAvailable:
            return "This AI Assist action needs a local capability that is not available yet."
        case .consentRequired(let provider):
            return "\(providerDisplayName(provider)) needs consent before AI Assist can run. Open AI settings to approve it."
        case .quotaExceeded(let provider):
            return "\(providerDisplayName(provider)) has reached its daily AI quota. Wait for the quota to reset."
        case .requestFailed(let provider, _):
            return "\(providerDisplayName(provider)) could not finish this AI Assist request. Try again."
        case .capabilityNotSupported:
            return "This AI Assist action needs a local generation capability that is not available yet."
        case .providerNotImplemented(let provider):
            return "\(providerDisplayName(provider)) is not ready for task suggestions yet. Local task suggestions arrive with Phase 1l."
        }
    }

    private static func providerDisplayName(_ provider: ProviderID) -> String {
        switch provider {
        case .appleIntelligence: return "Apple Intelligence"
        case .whisperKit: return "WhisperKit"
        case .mlx: return "MLX (on-device)"
        }
    }
}

/// Wrapper making a Proposal identifiable for `.sheet(item:)`.
/// Carries the action so the card title = `action.label`.
@MainActor
struct PendingProposal: Identifiable {
    let id = UUID()
    let action: TaskAssistUIAction
    let proposal: Proposal
}

@MainActor
struct TaskAssistActionHandler {
    let task: TaskItem
    let router: AIRouter?
    let modelContext: ModelContext

    /// Obtain a Proposal for the given action via `TaskAssistService.proposal(for:on:)`.
    /// Throws `TaskAssistUIError.aiUnavailable` if the router is not available.
    func propose(_ action: TaskAssistUIAction) async throws -> Proposal {
        guard let router else {
            throw TaskAssistUIError.aiUnavailable
        }
        let service = TaskAssistService(router: router)
        return try await service.proposal(for: action.serviceAction, on: task)
    }

    /// Accept a Proposal through the audited `ToolDispatcher` → `ProposalCoordinator`.
    /// Uses `FoundationComposition.makeLocalDispatcher` so the accept is audited and undoable.
    @discardableResult
    func accept(_ proposal: Proposal) async throws -> [ToolDispatchResult] {
        let coordinator = FoundationComposition.makeLocalDispatcher(modelContext: modelContext)
        return try await coordinator.accept(proposal, threadID: nil)
    }
}

@MainActor
struct TaskAssistMenuActions {
    let inFlightAction: TaskAssistUIAction?
    let perform: (TaskAssistUIAction) -> Void

    var isBusy: Bool {
        inFlightAction != nil
    }
}

struct TaskAssistMenuSection: View {
    let actions: TaskAssistMenuActions

    var body: some View {
        Section("AI Assist") {
            ForEach(TaskAssistUIAction.allCases) { action in
                Button {
                    actions.perform(action)
                } label: {
                    Label(action.label, systemImage: action.systemImage)
                }
                .disabled(actions.isBusy)
            }
        }
    }
}

public struct TaskAssistContextMenu: ViewModifier {
    public let task: TaskItem

    public init(task: TaskItem) {
        self.task = task
    }

    public func body(content: Content) -> some View {
        content.modifier(
            TaskAssistMenuSurface(task: task) { actions in
                TaskAssistMenuSection(actions: actions)
            })
    }
}

struct TaskAssistMenuSurface<MenuContent: View>: ViewModifier {
    let task: TaskItem
    @ViewBuilder let menuContent: (TaskAssistMenuActions) -> MenuContent

    @Environment(\.aiRouter) private var router
    @Environment(\.modelContext) private var modelContext
    @State private var inFlightAction: TaskAssistUIAction?
    @State private var pendingProposal: PendingProposal?
    @State private var errorMessage: String?

    func body(content: Content) -> some View {
        content
            .contextMenu {
                menuContent(menuActions)
            }
            .overlay(alignment: .topTrailing) {
                if inFlightAction != nil {
                    ProgressView()
                        .controlSize(.small)
                        .padding(6)
                        .background(NexusColor.Background.raised, in: Circle())
                        .padding(4)
                }
            }
            .sheet(item: $pendingProposal) { pending in
                proposalCard(for: pending)
            }
            .taskAssistErrorAlert(message: $errorMessage)
    }

    private var menuActions: TaskAssistMenuActions {
        TaskAssistMenuActions(inFlightAction: inFlightAction, perform: start)
    }

    private func start(_ action: TaskAssistUIAction) {
        guard inFlightAction == nil else { return }
        inFlightAction = action
        _Concurrency.Task { @MainActor in
            await fetchProposal(for: action)
        }
    }

    private func fetchProposal(for action: TaskAssistUIAction) async {
        defer { inFlightAction = nil }
        do {
            let proposal = try await TaskAssistActionHandler(
                task: task,
                router: router,
                modelContext: modelContext
            ).propose(action)
            pendingProposal = PendingProposal(action: action, proposal: proposal)
        } catch {
            errorMessage = TaskAssistErrorCopy.message(for: error)
        }
    }

    @MainActor
    private func proposalCard(for pending: PendingProposal) -> some View {
        let handler = TaskAssistActionHandler(
            task: task,
            router: router,
            modelContext: modelContext
        )
        let model = ProposalConfirmCardModel(
            title: pending.action.label,
            rationale: pending.proposal.rationale,
            previews: pending.proposal.previews.map(\.summary),
            onAccept: {
                do {
                    try await handler.accept(pending.proposal)
                } catch {
                    errorMessage = TaskAssistErrorCopy.message(for: error)
                }
                pendingProposal = nil
            },
            onReject: {
                pendingProposal = nil
            }
        )
        return ProposalConfirmCard(model: model)
    }
}

struct TaskAssistButtonGroup: View {
    let task: TaskItem

    @Environment(\.aiRouter) private var router
    @Environment(\.modelContext) private var modelContext
    @State private var inFlightAction: TaskAssistUIAction?
    @State private var pendingProposal: PendingProposal?
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(TaskAssistUIAction.allCases) { action in
                actionButton(action)
            }
        }
        .sheet(item: $pendingProposal) { pending in
            proposalCard(for: pending)
        }
        .taskAssistErrorAlert(message: $errorMessage)
    }

    private func actionButton(_ action: TaskAssistUIAction) -> some View {
        Button {
            start(action)
        } label: {
            HStack(spacing: 10) {
                if inFlightAction == action {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 18, height: 18)
                } else {
                    Image(systemName: action.systemImage)
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 18, height: 18)
                }

                Text(action.label)
                    .nexusType(.bodySmall)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .foregroundStyle(NexusColor.Text.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                NexusColor.Background.control,
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(NexusColor.Line.hairline, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .disabled(inFlightAction != nil)
        .accessibilityLabel(action.label)
    }

    private func start(_ action: TaskAssistUIAction) {
        guard inFlightAction == nil else { return }
        inFlightAction = action
        _Concurrency.Task { @MainActor in
            await fetchProposal(for: action)
        }
    }

    private func fetchProposal(for action: TaskAssistUIAction) async {
        defer { inFlightAction = nil }
        do {
            let proposal = try await TaskAssistActionHandler(
                task: task,
                router: router,
                modelContext: modelContext
            ).propose(action)
            pendingProposal = PendingProposal(action: action, proposal: proposal)
        } catch {
            errorMessage = TaskAssistErrorCopy.message(for: error)
        }
    }

    @MainActor
    private func proposalCard(for pending: PendingProposal) -> some View {
        let handler = TaskAssistActionHandler(
            task: task,
            router: router,
            modelContext: modelContext
        )
        let model = ProposalConfirmCardModel(
            title: pending.action.label,
            rationale: pending.proposal.rationale,
            previews: pending.proposal.previews.map(\.summary),
            onAccept: {
                do {
                    try await handler.accept(pending.proposal)
                } catch {
                    errorMessage = TaskAssistErrorCopy.message(for: error)
                }
                pendingProposal = nil
            },
            onReject: {
                pendingProposal = nil
            }
        )
        return ProposalConfirmCard(model: model)
    }
}

extension View {
    public func taskAssistContextMenu(for task: TaskItem) -> some View {
        modifier(TaskAssistContextMenu(task: task))
    }

    func taskAssistContextMenu<MenuContent: View>(
        for task: TaskItem,
        @ViewBuilder menuContent: @escaping (TaskAssistMenuActions) -> MenuContent
    ) -> some View {
        modifier(TaskAssistMenuSurface(task: task, menuContent: menuContent))
    }
}

extension View {
    fileprivate func taskAssistErrorAlert(message: Binding<String?>) -> some View {
        alert(
            "AI Assist failed",
            isPresented: Binding(
                get: { message.wrappedValue != nil },
                set: { isPresented in
                    if !isPresented {
                        message.wrappedValue = nil
                    }
                }
            ),
            presenting: message.wrappedValue
        ) { _ in
            Button("OK") {
                message.wrappedValue = nil
            }
        } message: { value in
            Text(value)
        }
    }
}
