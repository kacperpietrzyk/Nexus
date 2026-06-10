import NexusCore
import NexusUI
import SwiftUI

/// Spec `docs/05_MODULE_TODAY.md` §Quick Capture: "input field height 72–84 pt".
private let quickCaptureMinHeight: CGFloat = 72
/// Spec §Focus Timer: "circular progress 62–70 pt".
private let focusRingSize: CGFloat = 66
/// Focus Suggestion gap detection window: a standard 08:00–18:00 workday
/// (the design references morning→evening focus gaps; no workday token exists).
private let workdayStartHour = 8
private let workdayEndHour = 18

/// The Today right inspector (spec §Right inspector): Daily Brief, Focus
/// Suggestion, Up Next, Linked Notes, Focus Timer, and Quick Capture as
/// vertical glass cards. Reads the same shared `LiquidTodayModel` the main
/// column renders; cross-module intelligence arrives through injected
/// providers composed in the app layer.
public struct TodayInspector: View {

    @Environment(\.focusModeState) private var focusModeState
    @Environment(\.taskParser) private var taskParser
    @Environment(\.taskRepository) private var taskRepository

    private let model: LiquidTodayModel
    private let focusGaps: LiquidTodayFocusGapProvider?
    private let onNavigate: (TodayNavSelection) -> Void
    private let onOpenCapture: (CapturePane.Mode) -> Void

    @State private var captureText = ""
    @State private var captureIsSaving = false
    @State private var captureSavedFeedback = false
    @State private var captureError: String?

    public init(
        model: LiquidTodayModel,
        focusGaps: LiquidTodayFocusGapProvider?,
        onNavigate: @escaping (TodayNavSelection) -> Void,
        onOpenCapture: @escaping (CapturePane.Mode) -> Void
    ) {
        self.model = model
        self.focusGaps = focusGaps
        self.onNavigate = onNavigate
        self.onOpenCapture = onOpenCapture
    }

    public var body: some View {
        ScrollView(showsIndicators: false) {
            // Spec §Right inspector + 04_LAYOUT_SYSTEM.md: "Prawy panel ma
            // własne karty ułożone w pionie, spacing 12".
            VStack(spacing: DS.Space.m) {
                dailyBriefCard
                focusSuggestionCard
                upNextCard
                linkedNotesCard
                focusTimerCard
                quickCaptureCard
            }
            .padding(DS.Space.m)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: - Daily Brief

    @ViewBuilder
    private var dailyBriefCard: some View {
        LiquidGlassCard("Daily Brief") {
            if model.briefIsLoading && model.brief.isEmpty {
                Text("Preparing your brief…")
                    .font(DS.FontToken.body)
                    .foregroundStyle(DS.ColorToken.textTertiary)
            } else if model.brief.isEmpty {
                LiquidEmptyState(
                    systemImage: "sparkles",
                    message: "The agent writes a daily brief here once it's enabled."
                ) {
                    LiquidPrimaryButton("Open Settings") { onNavigate(.settings) }
                }
            } else {
                Text(LiquidTodayText.strippingMarkers(from: model.brief))
                    .font(DS.FontToken.body)
                    .foregroundStyle(DS.ColorToken.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } trailing: {
            Image(systemName: "sparkles")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(DS.ColorToken.accentPrimaryHover)
                .accessibilityHidden(true)
        }
    }

    // MARK: - Focus Suggestion

    @ViewBuilder
    private var focusSuggestionCard: some View {
        LiquidGlassCard("Focus Suggestion") {
            if let gap = suggestedFocusGap {
                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    Text(
                        "You have \(Self.durationText(gap.duration)) of focus time "
                            + "from \(TodayAgendaCard.timeFormatter.string(from: gap.start))."
                    )
                    .font(DS.FontToken.body)
                    .foregroundStyle(DS.ColorToken.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                LiquidEmptyState(
                    systemImage: "moon.zzz",
                    message: "No free focus gaps left in today's workday."
                )
            }
        }
    }

    /// First ≥1 h free gap between now and the end of the workday, computed by
    /// the injected `SchedulingIntelligence` seam over today's loaded events.
    private var suggestedFocusGap: DateInterval? {
        guard let focusGaps else { return nil }
        let now = Date.now
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: now)
        guard
            let workStart = calendar.date(byAdding: .hour, value: workdayStartHour, to: dayStart),
            let workEnd = calendar.date(byAdding: .hour, value: workdayEndHour, to: dayStart)
        else { return nil }
        let start = max(now, workStart)
        guard start < workEnd else { return nil }
        return focusGaps(model.events, DateInterval(start: start, end: workEnd)).first
    }

    static func durationText(_ duration: TimeInterval) -> String {
        let totalMinutes = Int(duration / 60)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0 && minutes > 0 { return "\(hours)h \(minutes)m" }
        if hours > 0 { return "\(hours)h" }
        return "\(minutes)m"
    }

    // MARK: - Up Next

    @ViewBuilder
    private var upNextCard: some View {
        LiquidGlassCard("Up Next") {
            if let item = model.upNextItem() {
                HStack(alignment: .top, spacing: DS.Space.s) {
                    Circle()
                        .fill(item.kind.accent)
                        .frame(width: 5, height: 5)
                        .padding(.top, 5)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title)
                            .font(DS.FontToken.bodyStrong)
                            .foregroundStyle(DS.ColorToken.textPrimary)
                            .lineLimit(2)
                        Text(
                            "\(TodayAgendaCard.timeFormatter.string(from: item.start)) – "
                                + TodayAgendaCard.timeFormatter.string(from: item.end)
                        )
                        .font(DS.FontToken.metadata)
                        .foregroundStyle(DS.ColorToken.textTertiary)
                    }
                    Spacer(minLength: 0)
                }
            } else {
                LiquidEmptyState(
                    systemImage: "clock",
                    message: "Nothing else scheduled today."
                )
            }
        }
    }

    // MARK: - Linked Notes

    @ViewBuilder
    private var linkedNotesCard: some View {
        LiquidGlassCard("Linked Notes") {
            if model.linkedNotes.isEmpty {
                LiquidEmptyState(
                    systemImage: "link",
                    message: "No notes linked to today's tasks."
                )
            } else {
                VStack(alignment: .leading, spacing: DS.Space.s) {
                    ForEach(model.linkedNotes, id: \.id) { note in
                        Button {
                            onNavigate(.notes)
                        } label: {
                            HStack(spacing: DS.Space.s) {
                                Image(systemName: "doc.text")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(DS.ColorToken.accentCyan)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(note.title.isEmpty ? "Untitled note" : note.title)
                                        .font(DS.FontToken.body)
                                        .foregroundStyle(DS.ColorToken.textPrimary)
                                        .lineLimit(1)
                                    Text("Updated \(Self.updatedFormatter.string(from: note.updatedAt))")
                                        .font(DS.FontToken.metadata)
                                        .foregroundStyle(DS.ColorToken.textTertiary)
                                }
                                Spacer(minLength: 0)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Open notes")
                    }
                }
            }
        }
    }

    /// English UI rule: explicit en_US (system locale may be pl_PL).
    private static let updatedFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateFormat = "MMM d"
        return formatter
    }()

    // MARK: - Focus Timer

    @ViewBuilder
    private var focusTimerCard: some View {
        LiquidGlassCard("Focus Timer") {
            if let task = model.pinnedFocusTask {
                HStack(spacing: DS.Space.m) {
                    LiquidCircularProgress(
                        value: FocusTimelineProgress.progress(
                            startAt: task.startAt,
                            endAt: task.endAt,
                            dueAt: task.dueAt,
                            now: .now
                        ),
                        title: Self.elapsedText(for: task, now: .now),
                        size: focusRingSize
                    )
                    VStack(alignment: .leading, spacing: 2) {
                        Text(task.title)
                            .font(DS.FontToken.bodyStrong)
                            .foregroundStyle(DS.ColorToken.textPrimary)
                            .lineLimit(2)
                        if let projectID = task.projectID, let name = model.projectNamesByID[projectID] {
                            Text(name)
                                .font(DS.FontToken.metadata)
                                .foregroundStyle(DS.ColorToken.textTertiary)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                    playButton(task)
                }
            } else {
                LiquidEmptyState(
                    systemImage: "timer",
                    message: "Pin a task as focus to start a session."
                ) {
                    LiquidPrimaryButton("Browse tasks") { onNavigate(.tasks) }
                }
            }
        }
    }

    /// The primary circular play control (spec §Focus Timer) — enters the
    /// EXISTING focus mode (`FocusModeState.enter`, the same seam the ⌘.
    /// command and the old NowCard pill use; `FocusView` takes over the shell).
    private func playButton(_ task: TaskItem) -> some View {
        Button {
            focusModeState?.enter(taskID: task.id)
        } label: {
            Image(systemName: "play.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(DS.ColorToken.textPrimary)
                .frame(width: 32, height: 32)
                .background {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [DS.ColorToken.accentPrimary, DS.ColorToken.accentPrimaryHover],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Start focus session")
        .disabled(focusModeState == nil)
    }

    /// Ring label: elapsed focus minutes against the task's own schedule
    /// (same `FocusTimelineProgress` math `FocusView` reports), tabular digits.
    static func elapsedText(for task: TaskItem, now: Date) -> String {
        let minutes = FocusTimelineProgress.elapsedMinutes(startAt: task.startAt, now: now)
        return String(format: "%d:%02d", minutes / 60, minutes % 60)
    }

    // MARK: - Quick Capture

    @ViewBuilder
    private var quickCaptureCard: some View {
        LiquidGlassCard("Quick Capture") {
            VStack(alignment: .leading, spacing: DS.Space.s) {
                TextField("Jot something down…", text: $captureText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(DS.FontToken.body)
                    .foregroundStyle(DS.ColorToken.textPrimary)
                    .lineLimit(3...5)
                    .padding(DS.Space.s)
                    .frame(minHeight: quickCaptureMinHeight, alignment: .topLeading)
                    .background {
                        RoundedRectangle(cornerRadius: DS.Radius.s, style: .continuous)
                            .fill(DS.ColorToken.backgroundSunken.opacity(0.6))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: DS.Radius.s, style: .continuous)
                            .stroke(DS.ColorToken.strokeDefault, lineWidth: 1)
                    }
                    .onSubmit { submitCapture() }

                if let captureError {
                    Text(captureError)
                        .font(DS.FontToken.metadata)
                        .foregroundStyle(DS.ColorToken.statusDanger)
                }

                // Icon row LIMITED to actions that exist: the full capture
                // sheet (task / voice modes) and inline submit. No calendar /
                // attachment icons — those flows have no backend seam here.
                HStack(spacing: DS.Space.xs) {
                    LiquidIconButton(
                        systemImage: "checklist",
                        accessibilityLabel: "Open task capture",
                        action: { onOpenCapture(.task) }
                    )
                    LiquidIconButton(
                        systemImage: "mic",
                        accessibilityLabel: "Open voice capture",
                        action: { onOpenCapture(.voiceMemo) }
                    )
                    Spacer()
                    if captureSavedFeedback {
                        Text("Saved")
                            .font(DS.FontToken.metadata)
                            .foregroundStyle(DS.ColorToken.statusSuccess)
                    }
                    LiquidIconButton(
                        systemImage: "paperplane.fill",
                        accessibilityLabel: "Save task",
                        action: { submitCapture() }
                    )
                    .disabled(captureIsSaving || trimmedCapture.isEmpty)
                }
            }
        }
    }

    private var trimmedCapture: String {
        captureText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Inline parse-and-create through the EXISTING capture seam: the same
    /// `CapturePaneState` parse→commit path the in-window `CapturePane` uses
    /// (NL parser → `TaskItemRepository.insert`). Falls back to opening the
    /// capture sheet if the parser/repository are not injected.
    private func submitCapture() {
        let text = trimmedCapture
        guard !text.isEmpty, !captureIsSaving else { return }
        guard let parser = taskParser, let repository = taskRepository else {
            onOpenCapture(.task)
            return
        }
        captureIsSaving = true
        captureError = nil
        _Concurrency.Task { @MainActor in
            let state = CapturePaneState(parser: parser, debounce: .zero)
            await state.handleInputChange(text)
            do {
                try await state.commit { task in
                    try repository.insert(task)
                }
                captureText = ""
                captureSavedFeedback = true
                try? await _Concurrency.Task.sleep(for: .seconds(2))
                captureSavedFeedback = false
            } catch {
                captureError = "Couldn't save the task. Please try again."
            }
            captureIsSaving = false
        }
    }
}
