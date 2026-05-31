import NexusCore
import NexusUI
import SwiftData
import SwiftUI

/// The capture surface. Used both as the Mac floating-window content
/// (CaptureWindowController hosts it via NSHostingView) and as the iOS
/// quick-capture sheet body. Built around `CapturePaneState` — drives parsing
/// debounced on input change.
public struct CapturePane: View {
    public enum Mode: String, Sendable, Hashable {
        case task
        case voiceMemo

        var systemImage: String {
            switch self {
            case .task: return "checklist"
            case .voiceMemo: return "mic"
            }
        }

        var label: String {
            switch self {
            case .task: return "Task"
            case .voiceMemo: return "Voice"
            }
        }

        var placeholder: String {
            switch self {
            case .task: return "what to add?"
            case .voiceMemo: return "dictate a note..."
            }
        }
    }

    @Environment(\.taskParser) private var parser
    @Environment(\.taskRepository) private var repository
    @Environment(\.dismiss) private var dismiss

    public let mode: Mode
    public let onSaved: (() -> Void)?
    public let onCancelled: (() -> Void)?
    public let showsCancelAction: Bool

    @State private var state: CapturePaneState?
    @State private var isSaving = false
    @State private var saveFeedbackVisible = false
    @FocusState private var inputFocused: Bool

    public init(
        mode: Mode = .task,
        onSaved: (() -> Void)? = nil,
        onCancelled: (() -> Void)? = nil,
        showsCancelAction: Bool = true
    ) {
        self.mode = mode
        self.onSaved = onSaved
        self.onCancelled = onCancelled
        self.showsCancelAction = showsCancelAction
    }

    public var body: some View {
        Group {
            #if os(macOS)
            macCapturePanel
            #else
            iosCapturePanel
            #endif
        }
        .onAppear {
            inputFocused = true
            ensureState()
        }
        .onKeyPress(.escape) {
            cancel()
            return .handled
        }
    }

    /// Mac panel chrome transcribed from oracle `CapturePreview` onto the §1-host-frozen
    /// NSPanel (host owns glass via `.nexusGlass(.elevated, r4)+rim+shadow`; content owns
    /// layout only). `TodayHUDPreview().blur(9)` + black-scrim + `.padding(.bottom, 90)`
    /// omitted — Lab-staging-device (MP-4.2 §1 reuse), not runtime. 600-content-in-640-window
    /// delta is intentional and host-frozen. Eyebrow glyph + text = `Text.muted`
    /// (eyebrow-icon ≠ hero-icon). §8 raw GeistMono for eyebrow and kbd chip.
    /// Slice 1 removes: `macCapturePill`, `capturePill`, `pillTintColor`, `pillBorder`,
    /// `pillBackground`, `pillAccentColor`, `pillShadowColor` (all pill-chrome-only).
    /// Slice 2: inputField retypographed (§8 Geist-Regular 18 / §10-omit multi-color spans),
    /// divider + ROZPOZNANO + parsed row + chips row rebuilt to oracle idiom (data-gated).
    /// Slice 3: action row rebuilt to oracle NexusButton idiom; hue machine collapsed (§3
    /// state-via-glyph+text: saveFeedbackVisible drives text/glyph swap, zero hue);
    /// `saveButton`/`dismissButton`/`saveButtonBackground` removed; Do-Inbox pill and
    /// trailing sparkles+hint caption §10-omitted (no inbox-route or ⌘↩/agent-finalize
    /// backend); xmark dismissButton removed (cancel reachable via esc kbd chip + .onKeyPress).
    #if os(macOS)
    private var macCapturePanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row: eyebrow icon + label + esc kbd chip
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(NexusColor.Text.muted)
                Text("QUICK CAPTURE")
                    .font(Font.custom("GeistMono-SemiBold", size: 10))
                    .tracking(1.8)
                    .foregroundStyle(NexusColor.Text.muted)
                Spacer()
                Button(action: cancel) {
                    Text("esc")
                        .font(NexusType.metaMono)
                        .foregroundStyle(NexusColor.Text.disabled)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(NexusColor.Glass.surface2, in: RoundedRectangle(cornerRadius: 4))
                }
                .buttonStyle(.plain)
                .help("Dismiss capture")
                .accessibilityLabel("Dismiss capture")
            }
            .padding(.bottom, 16)

            // Input row: §8 Geist-Regular 18 on macOS; §10 multi-color token spans omitted
            // (ParseResult has no token-span API — single functional TextField retypographed only);
            // iOS #else keeps NexusType.body byte-identical to pre-slice-2 render.
            inputField
                .padding(.bottom, 20)

            // Recognized section: data-gated on lastResult (oracle storyboard always-populated;
            // runtime follows MP-3.x precedent — Lab shows populated state, runtime is data-gated).
            if let result = state?.lastResult {
                Rectangle()
                    .fill(NexusColor.Line.hairline)
                    .frame(height: 1)
                    .padding(.bottom, 16)

                Text("RECOGNIZED")
                    .font(Font.custom("GeistMono-SemiBold", size: 9))
                    .tracking(1.8)
                    .foregroundStyle(NexusColor.Text.disabled)
                    .padding(.bottom, 10)

                HStack(spacing: 12) {
                    oracleParsedRow(result.title)
                }
                .nexusReveal(0)
                .padding(.bottom, 12)

                HStack(spacing: 8) {
                    ForEach(Array(CaptureChipModel.chips(for: result, now: .now).enumerated()), id: \.offset) { i, entry in
                        CaptureChipModel.chip(icon: entry.icon, label: entry.label)
                            .nexusReveal(i + 1)
                    }
                }
                .padding(.bottom, 22)
            }

            // Action row (oracle NexusButton idiom; §3 state-via-glyph+text; zero hue)
            // Do-Inbox pill §10-omitted (no inbox-route backend).
            // Trailing sparkles+caption §10-omitted (no ⌘↩ binding or agent-finalize backend).
            // xmark dismissButton removed (cancel via esc kbd chip + .onKeyPress(.escape)).
            // .padding(.top) dropped: when lastResult is present the chips block ends with
            // .padding(.bottom, 22), providing rhythm; when lastResult == nil the chips block
            // is absent and inputField.padding(.bottom, 20) supplies the spacing instead.
            HStack(spacing: 9) {
                NexusButton(variant: .primary, size: .sm, action: commit) {
                    HStack(spacing: 6) {
                        Image(systemName: saveFeedbackVisible ? "checkmark" : "return")
                            .accessibilityHidden(true)
                        Text(saveFeedbackVisible ? "Saved" : "Save")
                    }
                }
                .disabled(!canSave)
                .opacity(canSave ? 1 : 0.55)
                Spacer()
            }
        }
        .padding(22)
        .frame(width: 600)
        .nexusOverlayEnter()
    }

    // MARK: - Mac-only oracle helpers (CapturePreview idiom, §2 token map applied)
    // Called only from macCapturePanel; not accessible on other platforms.

    /// Replicates oracle `parsed(_:_:)`: title row with circle icon + body text.
    private func oracleParsedRow(_ title: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: "circle")
                .font(.system(size: 11))
                .foregroundStyle(NexusColor.Text.muted)
            Text(title)
                .font(Font.custom("Geist-Medium", size: 14))
                .foregroundStyle(NexusColor.Text.secondary)
            Spacer(minLength: 0)
        }
    }
    #endif

    private var iosCapturePanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            inputField
            CaptureChipsView(result: state?.lastResult)
            HStack(spacing: 10) {
                if showsCancelAction {
                    NexusButton(variant: .outline, size: .lg, action: cancel) {
                        Label("Cancel", systemImage: "xmark")
                    }
                    .frame(minHeight: 44)
                    .accessibilityLabel("Cancel capture")
                }
                Spacer()
                NexusButton(variant: .primary, size: .lg, action: commit) {
                    Label(saveFeedbackVisible ? "Saved" : "Save", systemImage: saveFeedbackVisible ? "checkmark" : "plus")
                }
                .frame(minHeight: 44)
                .accessibilityLabel(saveFeedbackVisible ? "Saved" : "Save task")
                .disabled(!canSave)
                .opacity(canSave ? 1 : 0.55)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .nexusGlass(.elevated, cornerRadius: NexusRadius.r5)
        .nexusGlassRim(cornerRadius: NexusRadius.r5)
        .nexusShadow(NexusShadow.glass)
    }

    // §8 stopgap: macOS uses raw Geist-Regular 18 (oracle size, no NexusType token);
    // iOS #else keeps NexusType.body — byte-identical to pre-slice-2 render (§10-omit,
    // §11 iOS byte-frozen). Multi-color ink/soft/faint token spans omitted (§10) —
    // ParseResult has no token-span API; single TextField retypographed only.
    private var inputFont: Font {
        #if os(macOS)
        Font.custom("Geist-Regular", size: 18)
        #else
        NexusType.body
        #endif
    }

    private var inputField: some View {
        TextField(mode.placeholder, text: bindingForInput, axis: .horizontal)
            .textFieldStyle(.plain)
            .lineLimit(1)
            .truncationMode(.tail)
            .font(inputFont)
            .foregroundStyle(NexusColor.Text.primary)
            .focused($inputFocused)
            .submitLabel(.done)
            .onSubmit { commit() }
            .onChange(of: bindingForInput.wrappedValue) { _, newValue in
                ensureState()
                _Concurrency.Task { await state?.handleInputChange(newValue) }
            }
            .frame(minWidth: 140)
    }

    private var canSave: Bool {
        !isSaving && state?.lastResult != nil
    }

    private var bindingForInput: Binding<String> {
        Binding(
            get: { state?.input ?? "" },
            set: { newValue in
                ensureState()
                state?.input = newValue
            }
        )
    }

    @MainActor
    private func ensureState() {
        guard state == nil, let parser else { return }
        state = CapturePaneState(parser: parser)
    }

    @MainActor
    private func commit() {
        guard let state, let repository, state.lastResult != nil, !isSaving else { return }
        isSaving = true
        _Concurrency.Task { @MainActor in
            await state.commit { task in
                try? repository.insert(task)
            }
            saveFeedbackVisible = true
            try? await _Concurrency.Task.sleep(for: .milliseconds(180))
            onSaved?()
            dismiss()
            isSaving = false
            saveFeedbackVisible = false
        }
    }

    @MainActor
    private func cancel() {
        guard !isSaving else { return }
        onCancelled?()
        dismiss()
    }
}
