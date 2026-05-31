import NexusUI
import SwiftUI
import TasksFeature

/// The Mac app shell's **right column** — the per-destination band stack.
///
/// Audit C3 (structural hoist "D"): the invariant chrome — `NexusWallpaper`
/// and the 54pt `NexusNavRail` — was moved OUT of this view up into
/// `ContentView`, which does NOT re-specialize. Each `dashboardShell` branch
/// still produces a distinct generic specialization of `NexusShell<…>`
/// (the constrained-init both-slots type safety is unchanged), so SwiftUI
/// still rebuilds THIS view on Inbox/Agent/other transitions — but the rail
/// is no longer inside that rebuilt subtree, so its selection-pill
/// `matchedGeometryEffect` (`@Namespace` owned by the stable `ContentView`,
/// injected via the additive `NexusNavRail.selectionNamespace`) now slides
/// across every transition instead of snapping. The wallpaper likewise no
/// longer flickers on the swap. This view is now purely:
///
/// ```
/// VStack(spacing: 0) {
///   NexusTopBar / control capsule   // == LabTopBar
///   content (fills)                 // == content slot
///   NexusCommandBar / surface input // == LabCommandBar
/// }
/// ```
///
/// `ContentView` composes it as
/// `ZStack { NexusWallpaper(); HStack { NexusNavRail; dashboardShell } }`.
/// Routing taps still go to existing callbacks
/// (`onOpenCommandPalette` / `onOpenCapture`); no new behaviour. Achromatic.
///
/// The top-bar band has **two modes** (MP-2.2 §1a, locked at MP-3.1):
/// - **Breadcrumb mode** (default) — `NexusTopBar(crumbs:onCmdK:){trailing}`,
///   exactly as Today uses it. The `NexusTopBar` MP-1 API stays byte-frozen.
/// - **Control mode** — a surface whose oracle renders an interactive
///   control strip (Inbox filter tabs, …) supplies a bespoke
///   `topControl` view; the shell wraps it in the SAME glass-capsule idiom
///   the private `NexusCommandBar` already composes directly (the §5-safe
///   precedent — `NexusTopBar` is NOT used). Selecting control mode is the
///   constrained-init opt-in below; Today never opts in, so its band is
///   byte-for-byte unaffected.
///
/// The bottom-bar band has **two modes** (MP-2.2 §1c, locked at MP-3.2,
/// symmetric to §1a — `NexusCommandBar` is app-side, NOT a frozen
/// `NexusUI` primitive, so no constrained-extension gymnastics are
/// *forced*; this still uses the §1a-symmetric constrained-init idiom for
/// file consistency):
/// - **Command-bar mode** (default — Today/Inbox/all current surfaces) —
///   the generic `NexusCommandBar` that opens the command palette /
///   capture, byte-for-byte unaffected (`BottomBar == EmptyView` is
///   inferred at every existing call site).
/// - **Surface-input mode** — a surface whose oracle bottom band is a real
///   input (Agent: `"Write to Nexus…"`, an actual message composer, not
///   the palette opener) supplies a bespoke `bottomBar` view; the shell
///   renders it in the SAME outer band padding the `NexusCommandBar`
///   already gets (`.h26/.t14/.b20`, unchanged). Backend-retention rule
///   (same precedent class as §1a keeping Inbox's Read/New actions): the
///   surface input may carry working backend the Lab did not model
///   (Agent's `AgentInputBar` = Phase 1i-Outer voice/image/file capture);
///   it is placed AS-IS structurally, never internally rebuilt here.
struct NexusShell<Content: View, TopTrailing: View, TopControl: View, BottomBar: View>: View {
    let crumbs: [String]
    let controlMode: Bool
    let surfaceBottomBar: Bool
    let onOpenCommandPalette: () -> Void
    let onOpenCapture: (CapturePane.Mode) -> Void
    @ViewBuilder let topControl: () -> TopControl
    @ViewBuilder let topTrailing: () -> TopTrailing
    @ViewBuilder let bottomBar: () -> BottomBar
    @ViewBuilder let content: () -> Content

    /// Designated init. Callers use one of the mode-specific
    /// constrained-extension inits below — never this directly.
    fileprivate init(
        crumbs: [String],
        controlMode: Bool,
        surfaceBottomBar: Bool,
        onOpenCommandPalette: @escaping () -> Void,
        onOpenCapture: @escaping (CapturePane.Mode) -> Void,
        @ViewBuilder topControl: @escaping () -> TopControl,
        @ViewBuilder topTrailing: @escaping () -> TopTrailing,
        @ViewBuilder bottomBar: @escaping () -> BottomBar,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.crumbs = crumbs
        self.controlMode = controlMode
        self.surfaceBottomBar = surfaceBottomBar
        self.onOpenCommandPalette = onOpenCommandPalette
        self.onOpenCapture = onOpenCapture
        self.topControl = topControl
        self.topTrailing = topTrailing
        self.bottomBar = bottomBar
        self.content = content
    }

    /// The top-bar band content (MP-2.2 §1a two modes).
    ///
    /// Control mode wraps the supplied bespoke content in the pinned
    /// glass-capsule idiom — the binding constants are the same status as
    /// the §2 token map and are mirrored 1:1 from the private
    /// `NexusCommandBar` below (the established §5-safe precedent: compose
    /// the glass idiom directly, never via a frozen primitive). Breadcrumb
    /// mode is `NexusTopBar` exactly as before — its public API is untouched.
    @ViewBuilder
    private var topBar: some View {
        if controlMode {
            HStack(spacing: 14) {
                topControl()
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 11)
            .nexusGlass(.regular, in: Capsule())
        } else {
            NexusTopBar(crumbs: crumbs, onCmdK: onOpenCommandPalette) {
                topTrailing()
            }
        }
    }

    var body: some View {
        // Just the band stack. Wallpaper + nav-rail live in `ContentView`
        // (audit C3 hoist) so they survive this view's re-specialization.
        VStack(spacing: 0) {
            topBar
                .padding(.horizontal, 26)
                .padding(.top, 18)
                .padding(.bottom, 18)

            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // §1c bottom-bar band — two modes. The outer band padding is
            // identical in both modes (the precedent the §1c lock requires):
            // surface-input mode supplies its own background + hairline
            // (Agent's `AgentInputBar`), so the band only contributes the
            // standing padding — no second glass capsule wrapping.
            Group {
                if surfaceBottomBar {
                    bottomBar()
                } else {
                    NexusCommandBar(
                        onOpenCommandPalette: onOpenCommandPalette,
                        onOpenCapture: { onOpenCapture(.task) }
                    )
                }
            }
            .padding(.horizontal, 26)
            .padding(.top, 14)
            .padding(.bottom, 20)
        }
    }
}

// MARK: - §1a top-bar / §1c bottom-bar band: mode-specific inits
//
// These constrained-extension inits are intentionally kept separate. They
// enforce at compile time that a caller cannot supply both a breadcrumb
// `topTrailing` slot AND a `topControl` slot in the same instantiation — the
// "both-slots guarantee". This means each mode produces a distinct generic
// specialization of NexusShell<…>, and SwiftUI rebuilds this band stack when
// ContentView.dashboardShell branches across modes. That rebuild is accepted
// (collapsing it would need the still-rejected AnyView erasure). Remaining
// observable side-effect: the bottom bar's @State is torn down with the old
// specialization (post-B1: the inline composer's in-progress
// CapturePaneState — unsent typed text is lost on an Inbox/Agent toggle;
// still acceptable). The OTHER former side-effect — the NexusNavRail
// selection pill snapping — is structurally gone as of audit C3's hoist:
// the rail (and wallpaper) now live in the invariant `ContentView`, OUTSIDE
// this re-specialized subtree, so the pill `matchedGeometryEffect` (stable
// `@Namespace` injected via `NexusNavRail.selectionNamespace`) is never torn
// down and slides across every transition. See ContentView.dashboardShell.

extension NexusShell where TopControl == EmptyView, BottomBar == EmptyView {
    /// Breadcrumb top-bar + command-bar bottom (default — Today).
    /// Byte-for-byte the call shape that shipped at MP-2:
    /// `NexusTopBar(crumbs:onCmdK:){ trailing }`. No `topControl`,
    /// `controlMode == false`; no `bottomBar`, `surfaceBottomBar == false`
    /// (`BottomBar == EmptyView` is inferred — the call site is unchanged).
    /// NexusTopBar API untouched.
    init(
        crumbs: [String],
        onOpenCommandPalette: @escaping () -> Void,
        onOpenCapture: @escaping (CapturePane.Mode) -> Void,
        @ViewBuilder topTrailing: @escaping () -> TopTrailing,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.init(
            crumbs: crumbs,
            controlMode: false,
            surfaceBottomBar: false,
            onOpenCommandPalette: onOpenCommandPalette,
            onOpenCapture: onOpenCapture,
            topControl: { EmptyView() },
            topTrailing: topTrailing,
            bottomBar: { EmptyView() },
            content: content
        )
    }
}

extension NexusShell where TopTrailing == EmptyView, BottomBar == EmptyView {
    /// Control top-bar + command-bar bottom (MP-2.2 §1a — e.g. Inbox).
    /// The surface supplies a bespoke top-bar content view; the shell wraps
    /// it in the pinned glass-capsule idiom and keeps the generic bottom
    /// `NexusCommandBar` (`BottomBar == EmptyView` inferred — call site
    /// unchanged from MP-3.1). `crumbs` is unused in this mode (no
    /// `NexusTopBar`) but kept so the caller's shell-title plumbing stays
    /// uniform.
    init(
        crumbs: [String],
        onOpenCommandPalette: @escaping () -> Void,
        onOpenCapture: @escaping (CapturePane.Mode) -> Void,
        @ViewBuilder topControl: @escaping () -> TopControl,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.init(
            crumbs: crumbs,
            controlMode: true,
            surfaceBottomBar: false,
            onOpenCommandPalette: onOpenCommandPalette,
            onOpenCapture: onOpenCapture,
            topControl: topControl,
            topTrailing: { EmptyView() },
            bottomBar: { EmptyView() },
            content: content
        )
    }
}

extension NexusShell where TopTrailing == EmptyView {
    /// Control top-bar + surface-input bottom (MP-2.2 §1c — Agent). The
    /// surface supplies BOTH a bespoke top-bar control strip AND a bespoke
    /// bottom bar (its real message composer). The shell wraps the top
    /// control in the pinned glass-capsule idiom (§1a) and renders the
    /// surface's `bottomBar` in place of the generic `NexusCommandBar`, in
    /// the SAME outer band padding (§1c). `crumbs` is unused in this mode
    /// (no `NexusTopBar`) but kept so shell-title plumbing stays uniform.
    init(
        crumbs: [String],
        onOpenCommandPalette: @escaping () -> Void,
        onOpenCapture: @escaping (CapturePane.Mode) -> Void,
        @ViewBuilder topControl: @escaping () -> TopControl,
        @ViewBuilder bottomBar: @escaping () -> BottomBar,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.init(
            crumbs: crumbs,
            controlMode: true,
            surfaceBottomBar: true,
            onOpenCommandPalette: onOpenCommandPalette,
            onOpenCapture: onOpenCapture,
            topControl: topControl,
            topTrailing: { EmptyView() },
            bottomBar: bottomBar,
            content: content
        )
    }
}

/// Bottom command bar — structurally the LabKit `LabCommandBar`
/// (`HStack { plus · field · Spacer · ⌘K kbd }` in a glass capsule).
///
/// Not a `NexusUI` primitive: a thin app-private token composition with a
/// single call site (the §1c band-shape lock governs the band, not this
/// view's internals — see `NexusShell` header).
///
/// **Audit B1 — the middle region is now a real inline composer.** The
/// placeholder text used to promise an input (`"Save a task or
/// ask Nexus…"`) while the *entire capsule* was a single
/// `.onTapGesture` that merely opened the command palette — a lying
/// affordance (the reported "quick save = UX disaster": click the
/// promised input → palette → Add Task → a mispositioned popup). It now
/// hosts a `TextField` wired to the existing, already-tested
/// `CapturePaneState` (the same parse+commit machine `CapturePane` uses),
/// so typing + Enter creates a task in place with no window. The glass
/// capsule, leading `+`, and trailing `⌘K` chip render byte-for-byte as
/// before — only the behaviour of the text region changed:
///  • `+`     → the rich capture window (now correctly centred, audit B2)
///  • field   → type + Enter creates the parsed task via the repository
///  • `⌘K`    → opens the command palette (chip tap + the global ⌘K
///              `CommandGroup` in `NexusMacApp`; the lying whole-capsule
///              tap is gone so it can no longer fight TextField focus)
///
/// Parser/repository come from the env injected at the Mac composition
/// root (`NexusMacApp` `.environment(\.taskParser/.taskRepository)`); when
/// absent (e.g. the `#Preview` harness) the field still renders and `+`/⌘K
/// still work — submit simply no-ops, mirroring `CapturePane`'s guards.
private struct NexusCommandBar: View {
    let onOpenCommandPalette: () -> Void
    let onOpenCapture: () -> Void

    @Environment(\.taskParser) private var parser
    @Environment(\.taskRepository) private var repository
    @State private var state: CapturePaneState?
    @State private var saveError: String?

    private var inputBinding: Binding<String> {
        Binding(
            get: { state?.input ?? "" },
            set: { newValue in
                ensureState()
                state?.input = newValue
            }
        )
    }

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onOpenCapture) {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(NexusColor.Text.secondary)
            }
            .buttonStyle(.plain)
            .help("Capture task")
            .accessibilityLabel("Capture task")

            // Geist-Regular 13 = the oracle `LabCommandBar` placeholder
            // type, byte-identical to the static Text it replaced; only the
            // ink moves to `Text.primary` so typed text is legible (the
            // placeholder still renders muted by default). The "or ask Nexus"
            // half was dropped: this bar only creates tasks, so
            // carrying the agent-ask promise would just be a second lie.
            TextField("Add a task or date…", text: inputBinding)
                .textFieldStyle(.plain)
                .lineLimit(1)
                .truncationMode(.tail)
                .font(Font.custom("Geist-Regular", size: 13))
                .foregroundStyle(NexusColor.Text.primary)
                .onSubmit { submit() }
                .onChange(of: inputBinding.wrappedValue) { _, newValue in
                    ensureState()
                    _Concurrency.Task { await state?.handleInputChange(newValue) }
                }
                .onAppear { ensureState() }

            Spacer(minLength: 8)

            // Oracle ⌘K kbd is `GeistMono-Medium` 10; `NexusType.metaMono`
            // matches. The kbd fill matches the oracle exactly
            // (`Color.white.opacity(0.06)`). Wrapped in a Button so the
            // visual affordance still opens the palette now that the lying
            // whole-capsule tap is removed (the global ⌘K shortcut also
            // still works via `NexusMacApp`'s `CommandGroup`).
            Button(action: onOpenCommandPalette) {
                Text("⌘K")
                    .font(NexusType.metaMono)
                    .foregroundStyle(NexusColor.Text.disabled)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Color.white.opacity(0.06),
                        in: RoundedRectangle(cornerRadius: 4)
                    )
            }
            .buttonStyle(.plain)
            .help("Open command palette")
            .accessibilityLabel("Open command palette")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 13)
        .background(Color.white.opacity(0.025), in: Capsule())
        .overlay {
            Capsule()
                .strokeBorder(Color.white.opacity(0.105), lineWidth: 1)
        }
        .nexusGlass(.regular, in: Capsule())
        .alert("Couldn’t save", isPresented: isShowingSaveError) {
            Button("OK", role: .cancel) { saveError = nil }
        } message: {
            Text(saveError ?? "")
        }
    }

    private var isShowingSaveError: Binding<Bool> {
        Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )
    }

    @MainActor
    private func ensureState() {
        guard state == nil, let parser else { return }
        state = CapturePaneState(parser: parser)
    }

    @MainActor
    private func submit() {
        guard let repository, let state else { return }
        _Concurrency.Task { @MainActor in
            // Force a parse of the current input even if the debounced
            // `.onChange` parse has not settled (user typed fast then hit
            // Enter): `handleInputChange` awaits its parse task, so
            // `lastResult` is populated synchronously here before commit —
            // otherwise a fast Enter would be a silent no-op (the inline
            // bar, unlike `CapturePane`, has no visible Save button to gate).
            await state.handleInputChange(state.input)
            guard state.lastResult != nil else { return }
            do {
                try await state.commit { task in try repository.insert(task) }
            } catch {
                // Keep the typed text in the bar and surface the failure
                // rather than letting the task vanish on a lost save.
                saveError = "Couldn’t save the task. Please try again."
            }
        }
    }
}

#Preview("NexusShell · Mac") {
    NexusShellPreviewHarness()
        .frame(width: 1240, height: 800)
}

/// Standalone preview harness for the shell band stack (rail + wallpaper
/// are composed by `ContentView` post-C3 and are not part of this view).
private struct NexusShellPreviewHarness: View {
    var body: some View {
        ZStack {
            NexusWallpaper()
            HStack(spacing: 0) {
                NexusShell(
                    crumbs: ["Personal", "Today"],
                    onOpenCommandPalette: {},
                    onOpenCapture: { _ in },
                    topTrailing: {
                        Text("7 open · 3 meetings")
                            .font(NexusType.mono)
                            .foregroundStyle(NexusColor.Text.muted)
                    },
                    content: {
                        Text("Today content slot")
                            .font(NexusType.body)
                            .foregroundStyle(NexusColor.Text.tertiary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                )
            }
        }
    }
}
