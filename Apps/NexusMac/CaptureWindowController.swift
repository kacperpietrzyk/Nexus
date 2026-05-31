import AppKit
import NexusCore
import NexusUI
import SwiftUI
import TasksFeature

/// Hosts `CapturePane` in a borderless floating window. Toggled by
/// the ⌘⌃N hotkey via a local NSEvent monitor — global hotkey requires
/// Accessibility permission and is deferred (Phase 1e). The window
/// keeps focus when shown and dismisses on Esc / Save.
@MainActor
final class CaptureWindowController: NSWindowController {
    private let parser: any NLParser
    private let repository: TaskItemRepository
    private var localMonitor: Any?

    init(parser: any NLParser, repository: TaskItemRepository) {
        self.parser = parser
        self.repository = repository
        let window = CapturePanel(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 96),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.isFloatingPanel = true
        window.level = .floating
        window.becomesKeyOnlyIfNeeded = false
        window.hidesOnDeactivate = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.center()
        super.init(window: window)
        window.contentViewController = makeHostingController(mode: .task)
        Self.shared = self
        registerHotkey()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    isolated deinit {
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    private static var shared: CaptureWindowController?

    static func toggleStatic() {
        shared?.toggle(mode: .task)
    }

    private func makeHostingController(mode: CapturePane.Mode) -> NSHostingController<AnyView> {
        NSHostingController(
            rootView: AnyView(
                CapturePane(
                    mode: mode,
                    onSaved: { Self.toggleStatic() },
                    onCancelled: { Self.toggleStatic() }
                )
                .environment(\.taskParser, parser)
                .environment(\.taskRepository, repository)
                .nexusGlass(.elevated, cornerRadius: NexusRadius.r4)
                .nexusShadow(NexusShadow.glass)
            )
        )
    }

    private func registerHotkey() {
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if modifiers == [.command, .control], event.charactersIgnoringModifiers == "n" {
                self.toggle()
                return nil
            }
            return event
        }
    }

    func show(mode: CapturePane.Mode) {
        guard let window else { return }
        let host = makeHostingController(mode: mode)
        // Audit B2 (corrected). The first attempt called
        // `window.setContentSize(host.view.fittingSize)` *immediately* after
        // assigning the controller, but the SwiftUI host has not laid out at
        // that point → `fittingSize ≈ .zero` → a zero-size, invisible panel,
        // so "+ New" / ⌘⌃N produced no visible window at all (a regression
        // on the original which at least appeared, just off-centre). Instead
        // let the hosting controller drive the window size via
        // `.preferredContentSize` (the window tracks the SwiftUI content),
        // order it front, then re-centre on the next main-actor turn once
        // the size has actually settled — visible on every open AND centred
        // (the original `.center()` ran once in `init` and never again, so
        // it drifted top-right as the content size changed).
        host.sizingOptions = [.preferredContentSize]
        window.contentViewController = host
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        _Concurrency.Task { @MainActor [weak self] in
            self?.window?.center()
        }
    }

    func toggle(mode: CapturePane.Mode = .task) {
        guard let window else { return }
        if window.isVisible {
            window.orderOut(nil)
        } else {
            show(mode: mode)
        }
    }
}

/// Borderless capture panel that opts into key-window status. Default `NSPanel`
/// with `.nonactivatingPanel` + `.borderless` returns `false` from `canBecomeKey`,
/// so the embedded `TextField` never receives keyboard input.
private final class CapturePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
