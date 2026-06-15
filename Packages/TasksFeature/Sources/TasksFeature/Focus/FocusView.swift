import NexusCore
import NexusUI
import SwiftData
import SwiftUI

public struct FocusView: View {
    @Environment(\.focusModeState) private var focusModeState
    @Environment(\.taskRepository) private var taskRepository
    @Environment(\.modelContext) private var modelContext
    @State private var markDoneError: String?
    @State private var cascadePrompt: CascadeCompletionPrompt?

    public let task: TaskItem
    public let now: Date

    public init(task: TaskItem, now: Date = .now) {
        self.task = task
        self.now = now
    }

    public var body: some View {
        ZStack(alignment: .topTrailing) {
            #if os(macOS)
            // Liquid backdrop: focus mode is a full-screen takeover, so it owns
            // its own aurora wallpaper for the glass column below to sample.
            // iOS keeps the opaque base until the touch Liquid pass.
            LiquidWallpaper()
                .ignoresSafeArea()
            #else
            NexusColor.Background.base
                .ignoresSafeArea()
            #endif

            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    Text("NOW · COMMITTED")
                        .nexusType(.eyebrow)
                        // MP-2 burned: emphasis eyebrow → primary ink
                        .foregroundStyle(NexusColor.Text.primary)

                    title

                    chipRow

                    bodyText

                    timePocketSection

                    actionRow
                }
                #if os(macOS)
                // Liquid re-skin: the committed-task column floats as a glass
                // panel on the aurora backdrop instead of sitting flat on the
                // opaque base. `.strong` (not `.card`): the column is text-heavy
                // over a full-screen aurora that brightens at the edges, so the
                // deeper glaze protects legibility — and it matches the verified
                // welcome hero. iOS keeps the bare centred column.
                .padding(36)
                .frame(maxWidth: 720, alignment: .leading)
                .liquidGlass(.strong, radius: DS.Radius.xl)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, 32)
                .padding(.vertical, 72)
                #else
                .frame(maxWidth: 720, alignment: .leading)
                .padding(.horizontal, 32)
                .padding(.vertical, 96)
                .frame(maxWidth: .infinity, alignment: .center)
                #endif
            }
            .scrollIndicators(.hidden)

            #if os(macOS)
            exitHintPill
            #endif
        }
        .nexusFocusExitCommand {
            focusModeState?.exit()
        }
        .alert("Focus action failed", isPresented: isShowingMarkDoneError) {
            Button("OK", role: .cancel) {
                markDoneError = nil
            }
        } message: {
            Text(markDoneError ?? "")
        }
        .cascadeCompletionConfirmation($cascadePrompt) { prompt in
            confirmCascade(prompt)
        }
    }

    private var title: some View {
        // MP-2 burned: high-priority title emphasis → primary ink (achromatic).
        // Distinct high-priority treatment deferred to MP-2.2 pattern-lock.
        Text(task.title)
            .nexusType(.display)
            .lineSpacing((NexusType.Metrics.display.lineHeight - 1) * NexusType.Metrics.display.size)
            .foregroundStyle(NexusColor.Text.primary)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var chipRow: some View {
        let chips = chipDescriptors
        if !chips.isEmpty {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    ForEach(chips) { chip in
                        NexusChip(chip.label, systemImage: chip.systemImage, tone: chip.tone)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(chips) { chip in
                        NexusChip(chip.label, systemImage: chip.systemImage, tone: chip.tone)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var bodyText: some View {
        let trimmedBody = ((try? TaskNoteContent.plainText(for: task, in: modelContext)) ?? task.body)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedBody.isEmpty {
            Text(trimmedBody)
                .nexusType(.body)
                .lineSpacing((NexusType.Metrics.body.lineHeight - 1) * NexusType.Metrics.body.size)
                .foregroundStyle(NexusColor.Text.secondary)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var timePocketSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text("Time pocket")
                    .nexusType(.caption)
                    .foregroundStyle(NexusColor.Text.muted)
                Text(focusLabel)
                    .nexusType(.caption)
                    .foregroundStyle(NexusColor.Text.tertiary)
            }

            NexusDayProgress(progress: focusProgress, focusedMinutes: elapsedFocusMinutes)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
    }

    private var actionRow: some View {
        HStack(spacing: 10) {
            NexusBadge("End focus", tone: .acc, size: .control) {
                focusModeState?.exit()
            }
            NexusBadge("Mark done", systemImage: "checkmark", tone: .acc, size: .control) {
                markTaskDone()
            }
        }
        .padding(.top, 6)
    }

    private var exitHintPill: some View {
        NexusBadge("Esc exit focus", tone: .muted)
            .padding(.top, 26)
            .padding(.trailing, 28)
    }

    private var isShowingMarkDoneError: Binding<Bool> {
        Binding {
            markDoneError != nil
        } set: { isPresented in
            if !isPresented {
                markDoneError = nil
            }
        }
    }

    private func markTaskDone() {
        guard let taskRepository else {
            markDoneError = "Couldn't mark task done."
            return
        }

        do {
            try TaskCompletionAction.complete(task, repository: taskRepository)
            focusModeState?.exit()
        } catch let error as TaskItemRepositoryError {
            if case .parentHasOpenSubtasks(let parentID, let openCount) = error, parentID == task.id {
                cascadePrompt = CascadeCompletionPrompt(task: task, openCount: openCount)
            } else {
                markDoneError = "Couldn't mark task done."
            }
        } catch {
            markDoneError = "Couldn't mark task done."
        }
    }

    private func confirmCascade(_ prompt: CascadeCompletionPrompt) {
        guard let taskRepository else {
            markDoneError = "Couldn't mark task done."
            return
        }
        do {
            try TaskCompletionAction.cascadeComplete(prompt.task, repository: taskRepository)
            focusModeState?.exit()
        } catch {
            markDoneError = "Couldn't mark task done."
        }
    }

    private var chipDescriptors: [ChipDescriptor] {
        var descriptors: [ChipDescriptor] = []
        if let externalIdentifier {
            descriptors.append(.init(id: "external", label: externalIdentifier, tone: .accent))
        }
        descriptors.append(
            contentsOf: task.tags.prefix(2).enumerated().map { index, tag in
                ChipDescriptor(id: "tag-\(index)", label: "#\(tag)", tone: .neutral)
            }
        )
        if let dueLabel {
            descriptors.append(.init(id: "due", label: dueLabel, systemImage: "calendar", tone: .accent))
        }
        return descriptors
    }

    private var externalIdentifier: String? {
        guard let raw = task.externalSourceID else { return nil }
        let candidate: Substring
        if let separator = raw.firstIndex(of: ":") {
            candidate = raw[raw.index(after: separator)...]
        } else {
            candidate = raw[...]
        }
        let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private var dueLabel: String? {
        guard let dueAt = task.dueAt else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: dueAt)
    }

    private var focusMinutes: Int {
        guard let dueAt = task.dueAt else { return 0 }
        return max(0, Int(dueAt.timeIntervalSince(now) / 60))
    }

    private var focusLabel: String {
        if focusMinutes <= 0 {
            return "Time is up — close it and move on."
        }
        let hours = focusMinutes / 60
        let remainder = focusMinutes % 60
        if hours > 0 {
            return "\(hours)h \(remainder)m of focus before deadline"
        }
        return "\(remainder)m of focus before deadline"
    }

    private var focusProgress: Double {
        FocusTimelineProgress.progress(startAt: task.startAt, endAt: task.endAt, dueAt: task.dueAt, now: now)
    }

    private var elapsedFocusMinutes: Int {
        FocusTimelineProgress.elapsedMinutes(startAt: task.startAt, now: now)
    }

}

private struct ChipDescriptor: Identifiable {
    let id: String
    let label: String
    let systemImage: String?
    let tone: NexusChipTone

    init(id: String, label: String, systemImage: String? = nil, tone: NexusChipTone) {
        self.id = id
        self.label = label
        self.systemImage = systemImage
        self.tone = tone
    }
}

extension View {
    @ViewBuilder
    fileprivate func nexusFocusExitCommand(_ action: @escaping () -> Void) -> some View {
        #if os(macOS) || os(tvOS)
        self.onExitCommand(perform: action)
        #else
        self
        #endif
    }
}
