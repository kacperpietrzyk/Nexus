import NexusCore
import NexusUI
import SwiftUI

/// Spec `docs/05_MODULE_TODAY.md` §Quick Capture: "input field height 72–84 pt".
private let quickCaptureMinHeight: CGFloat = 72
/// Spec §Focus Timer: "circular progress 62–70 pt".
private let focusRingSize: CGFloat = 66

/// The Today right inspector (spec §Right inspector): Daily Brief, Focus,
/// Up Next, and Quick Capture as one
/// integrated glass column. Reads the same shared `LiquidTodayModel` the main
/// column renders; cross-module intelligence arrives through injected
/// providers composed in the app layer.
public struct TodayInspector: View {

    @Environment(\.focusModeState) private var focusModeState
    @Environment(\.taskParser) private var taskParser
    @Environment(\.taskRepository) private var taskRepository

    private let model: LiquidTodayModel
    private let onNavigate: (TodayNavSelection) -> Void
    private let onOpenCapture: (CapturePane.Mode) -> Void

    /// Draft text lives in the HOST (`ContentView.todayCaptureText`), not in
    /// local `@State`: the inspector slot unmounts on every destination
    /// switch, and a half-typed capture must survive a tab round-trip.
    @Binding private var captureText: String
    @State private var captureIsSaving = false
    @State private var captureSavedFeedback = false
    @State private var captureError: String?
    /// The inspector is a fixed, non-scrolling column (see `body`), so the brief
    /// preview is clamped to 5 lines. Tapping the card opens the full text in a
    /// popover (adapts to a sheet in compact width) — the only way to read a
    /// brief that overflows the preview.
    @State private var showFullBrief = false

    public init(
        model: LiquidTodayModel,
        captureText: Binding<String>,
        onNavigate: @escaping (TodayNavSelection) -> Void,
        onOpenCapture: @escaping (CapturePane.Mode) -> Void
    ) {
        self.model = model
        self._captureText = captureText
        self.onNavigate = onNavigate
        self.onOpenCapture = onOpenCapture
    }

    public var body: some View {
        // No ScrollView — the inspector is a fixed column that must fit the
        // window height. Empty cards collapse to a single muted line (see
        // `inspectorEmptyLine`) so vertical demand tracks real content and the
        // cards fit without scrolling.
        VStack(spacing: DS.Space.s) {
            dailyBriefCard
            focusCard
            quickCaptureCard
        }
        .padding(.horizontal, DS.Space.m)
        .padding(.vertical, DS.Space.m)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background {
            TodayInspectorColumnWash()
                .allowsHitTesting(false)
        }
    }

    /// Compact empty affordance for inspector cards: one muted line, no hero
    /// glyph. Keeps an empty card ~1 row tall so the column fits without scroll.
    private func inspectorEmptyLine(_ message: String) -> some View {
        Text(message)
            .font(DS.FontToken.metadata)
            .foregroundStyle(DS.ColorToken.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var reference: LiquidTodayReferenceData.Snapshot? {
        LiquidReferenceMode.isEnabled ? LiquidTodayReferenceData.snapshot(now: .now) : nil
    }

    // MARK: - Daily Brief

    @ViewBuilder
    private var dailyBriefCard: some View {
        TodayInspectorSection("Daily Brief") {
            if let brief = reference?.brief, !brief.isEmpty {
                briefText(brief)
            } else if model.briefIsLoading && model.brief.isEmpty {
                Text("Preparing your brief…")
                    .font(DS.FontToken.body)
                    .foregroundStyle(DS.ColorToken.textTertiary)
            } else if model.brief.isEmpty {
                VStack(alignment: .leading, spacing: DS.Space.s) {
                    inspectorEmptyLine("The agent writes a daily brief here once it's enabled.")
                    LiquidPrimaryButton("Open Settings") { onNavigate(.settings) }
                }
            } else {
                briefText(model.brief)
            }
        } trailing: {
            Image(systemName: "sparkles")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(DS.ColorToken.accentPrimaryHover)
                .accessibilityHidden(true)
        }
    }

    private func briefText(_ text: String) -> some View {
        Button {
            showFullBrief = true
        } label: {
            VStack(alignment: .leading, spacing: DS.Space.xxs) {
                Text(LiquidTodayText.strippingMarkers(from: text))
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(DS.ColorToken.textSecondary)
                    .lineSpacing(4)
                    .lineLimit(5)
                    .padding(.top, DS.Space.xs)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Read full brief")
                    .font(DS.FontToken.metadata)
                    .foregroundStyle(DS.ColorToken.accentPrimaryHover)
            }
            .background(alignment: .topTrailing) {
                Circle()
                    .fill(DS.ColorToken.accentBlue.opacity(0.10))
                    .frame(width: 120, height: 120)
                    .blur(radius: 26)
                    .offset(x: 40, y: -52)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Read the full daily brief")
        .accessibilityLabel("Read the full daily brief")
        .popover(isPresented: $showFullBrief, arrowEdge: .leading) {
            fullBriefPopover(text)
        }
    }

    private func fullBriefPopover(_ text: String) -> some View {
        ScrollView {
            Text(LiquidTodayText.strippingMarkers(from: text))
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(DS.ColorToken.textPrimary)
                .lineSpacing(4)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(DS.Space.l)
        }
        .frame(idealWidth: 360, maxWidth: 460, minHeight: 160, idealHeight: 360, maxHeight: 520)
    }

    // MARK: - Focus

    /// One card, two states. State A (a focus task is set) shows the running
    /// timer ring + task; State B (none set) shows today's focus-context line
    /// and a way to choose a task. Merges the former Focus Suggestion + Focus
    /// Timer cards; keyed on the same `pinnedAsFocus` task the ⌘. command reads.
    @ViewBuilder
    private var focusCard: some View {
        TodayInspectorSection("Focus") {
            if let task = reference?.pinnedFocusTask ?? model.pinnedFocusTask {
                focusActiveState(task)
            } else {
                focusEmptyState
            }
        }
    }

    /// State A: the live focus timer for the set task (ring + name + controls).
    private func focusActiveState(_ task: TaskItem) -> some View {
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
                let names = reference?.projectNamesByID ?? model.projectNamesByID
                if let projectID = task.projectID, let name = names[projectID] {
                    Text(name)
                        .font(DS.FontToken.metadata)
                        .foregroundStyle(DS.ColorToken.textTertiary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            playButton(task)
        }
    }

    /// State B: no focus task set — one context line + a way to choose one.
    private var focusEmptyState: some View {
        VStack(spacing: DS.Space.m) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.10), lineWidth: 7)
                    .frame(width: focusRingSize, height: focusRingSize)
                Circle()
                    .trim(from: 0, to: 0.22)
                    .stroke(
                        DS.ColorToken.accentPrimary,
                        style: StrokeStyle(lineWidth: 7, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .frame(width: focusRingSize, height: focusRingSize)
                    .shadow(color: DS.ColorToken.accentPrimary.opacity(0.24), radius: 10)
                Image(systemName: "timer")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(DS.ColorToken.textTertiary)
            }
            Text(focusContextLine)
                .font(DS.FontToken.metadata)
                .foregroundStyle(DS.ColorToken.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            LiquidPrimaryButton("Browse tasks") { onNavigate(.tasks) }
        }
        .frame(maxWidth: .infinity, minHeight: 138)
    }

    /// The single context line for State B — the former Focus Suggestion copy:
    /// a real free gap when one exists, an open-day line when the calendar is
    /// empty, otherwise a no-gaps line. Reads the stored model values (computed
    /// during reload via the SchedulingIntelligence seam) — no per-render work.
    private var focusContextLine: String {
        if let gap = reference?.focusSuggestion ?? model.focusSuggestion {
            return "You have \(Self.durationText(gap.duration)) of focus time "
                + "from \(TodayUpNextCard.timeFormatter.string(from: gap.start)). "
                + "Set a focus task to begin."
        }
        if !model.focusHasCalendarEvents {
            return "No meetings today — the day is open for focus. Set a focus task to begin."
        }
        return "No free focus gaps left in today's workday."
    }

    static func durationText(_ duration: TimeInterval) -> String {
        let totalMinutes = Int(duration / 60)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0 && minutes > 0 { return "\(hours)h \(minutes)m" }
        if hours > 0 { return "\(hours)h" }
        return "\(minutes)m"
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
        TodayInspectorSection("Quick Capture") {
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
                            .fill(Color.white.opacity(0.018))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: DS.Radius.s, style: .continuous)
                            .stroke(DS.ColorToken.strokeHairline, lineWidth: 1)
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

private struct TodayInspectorSection<Content: View, Trailing: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content
    @ViewBuilder let trailing: () -> Trailing

    init(
        _ title: String,
        @ViewBuilder content: @escaping () -> Content,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) {
        self.title = title
        self.content = content
        self.trailing = trailing
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            HStack(spacing: DS.Space.s) {
                Text(title)
                    .font(DS.FontToken.section)
                    .foregroundStyle(DS.ColorToken.textPrimary)
                Spacer(minLength: 0)
                trailing()
            }
            .frame(height: 22)

            content()
        }
        .padding(.horizontal, DS.Space.m)
        .padding(.vertical, DS.Space.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous)
                .fill(Color.white.opacity(0.010))
                .overlay {
                    RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.042),
                                    .clear,
                                    Color.black.opacity(0.014),
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .blendMode(.softLight)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.052), lineWidth: 1)
                }
        }
    }
}

extension TodayInspectorSection where Trailing == EmptyView {
    fileprivate init(_ title: String, @ViewBuilder content: @escaping () -> Content) {
        self.init(title, content: content, trailing: { EmptyView() })
    }
}

private struct TodayInspectorColumnWash: View {
    var body: some View {
        ZStack {
            LinearGradient(
                stops: [
                    .init(color: Color.white.opacity(0.006), location: 0),
                    .init(color: DS.ColorToken.accentBlue.opacity(0.008), location: 0.25),
                    .init(color: .clear, location: 0.62),
                    .init(color: DS.ColorToken.accentPurple.opacity(0.006), location: 1),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [
                    DS.ColorToken.accentBlue.opacity(0.014),
                    .clear,
                ],
                center: UnitPoint(x: 0.72, y: 0.16),
                startRadius: 0,
                endRadius: 260
            )
        }
    }
}
