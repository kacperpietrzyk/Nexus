import Foundation
import SwiftUI

extension Notification.Name {
    /// Posted by the "Select All Items" command-palette entry; the active list
    /// surface observes it to enter selection mode + select its visible rows.
    /// The shell's menu-bar ⌘A uses the `\.selectAllAction` focused value
    /// instead — this notification is the palette-driven sibling path. Lives in
    /// NexusUI (not a feature module) so every selectable surface can observe it.
    public static let nexusSelectAllActiveSurface = Notification.Name("nexus.selectAllActiveSurface")
}

/// A surface-published "select all" entry point for the global ⌘A command.
///
/// Selectable surfaces (Tasks list, Inbox, Notes, People, …) own their
/// `SelectionModel` as private `@State`, so the shell can't reach into it to
/// route a menu-bar ⌘A. Instead each surface publishes this action through
/// `.focusedValue(\.selectAllAction, …)` while it holds keyboard focus, and the
/// shell's `Commands` reads it back via `@FocusedValue` to drive a single
/// global ⌘A.
///
/// The contract is deliberately a value type carrying one closure: invoking it
/// enters selection mode AND selects every row the surface currently shows.
/// The surface decides what "every row" means (its visible / filtered set), so
/// the shell never needs to know the row type.
///
/// ## Why a focus-scoped value (and not a broadcast notification or scene value)
/// A plain `Button(…).keyboardShortcut("a", .command)` registers an app-wide
/// ⌘A key-equivalent that AppKit fires *before* the focused text field, which
/// would shadow the system text "Select All" in every text field / editor.
/// Routing ⌘A through a `@FocusedValue` + `.disabled(action == nil)` keeps the
/// menu item **disabled** whenever no selectable surface holds focus — and a
/// disabled menu key-equivalent is NOT consumed, so AppKit/UIKit fall through
/// to the responder chain and text "Select All" keeps working.
///
/// This MUST use `.focusedValue` (focus-chain-scoped), NOT `.focusedSceneValue`
/// (scene-wide): a scene value stays non-nil while a sibling text surface — e.g.
/// the Quick Capture overlay, a search field — holds focus, which would
/// re-enable the item and hijack that field's text Select-All. Focus scoping is
/// exactly what makes the value go nil when a text field is focused, so the
/// disabled-fallthrough is statically safe rather than merely hopeful. As a
/// bonus, a hidden iOS `TabView` tab cannot hold focus → never publishes → no
/// multi-mount double-publish.
public struct SelectAllAction: Equatable {
    private let perform: @MainActor () -> Void
    /// Stable identity so SwiftUI's `Equatable` focused-value diffing doesn't
    /// thrash when the same surface re-publishes an equivalent closure each
    /// render (closures aren't `Equatable`).
    private let identity: AnyHashable

    public init(identity: AnyHashable, perform: @escaping @MainActor () -> Void) {
        self.identity = identity
        self.perform = perform
    }

    @MainActor
    public func callAsFunction() {
        perform()
    }

    public static func == (lhs: SelectAllAction, rhs: SelectAllAction) -> Bool {
        lhs.identity == rhs.identity
    }
}

private struct SelectAllActionKey: FocusedValueKey {
    typealias Value = SelectAllAction
}

extension FocusedValues {
    /// The active surface's "select all" action, or `nil` when no selectable
    /// surface is in the focused scene (text fields, settings, etc.).
    public var selectAllAction: SelectAllAction? {
        get { self[SelectAllActionKey.self] }
        set { self[SelectAllActionKey.self] = newValue }
    }
}

/// The shell-level ⌘A command, shared by the macOS and iOS scenes.
///
/// Reads the active surface's `SelectAllAction` from the focused scene and
/// fires it on ⌘A. When no selectable surface is active the value is `nil`, the
/// button is `.disabled`, and AppKit/UIKit let ⌘A fall through to the system
/// text "Select All" — so the global command never shadows text selection.
///
/// Attach via `.commands { SelectAllCommands() }` on the app's scene.
///
/// Guarded to iOS/macOS: the SwiftUI `Commands`/`CommandGroup` surface is
/// unavailable on watchOS (and NexusUI compiles for the watch target), and a
/// global ⌘A menu command only applies to platforms with a menu bar / hardware
/// keyboard.
#if os(iOS) || os(macOS)
public struct SelectAllCommands: Commands {
    @FocusedValue(\.selectAllAction) private var selectAllAction: SelectAllAction?

    public init() {}

    public var body: some Commands {
        // ADD (not replace) a ⌘A item after the standard Edit text-editing group.
        // The system "Select All" stays in place; our item only WINS when a
        // selectable surface is active (`selectAllAction != nil`). When no list
        // is active the item is `.disabled`, and a disabled menu key-equivalent
        // is NOT consumed by AppKit/UIKit → ⌘A falls through to the responder
        // chain's text Select All. This is why text selection is never shadowed.
        CommandGroup(after: .textEditing) {
            Button("Select All Items") { selectAllAction?() }
                .keyboardShortcut("a", modifiers: .command)
                .disabled(selectAllAction == nil)
        }
    }
}
#endif

extension View {
    /// Publishes a focus-scoped `SelectAllAction` that enters selection mode on
    /// `model` and selects everything in `ids`.
    ///
    /// Apply this on a selectable surface. The value is published through
    /// `.focusedValue`, so it is visible to the shell's ⌘A command only while
    /// this surface is in the keyboard-focus chain — which is what keeps text
    /// fields' system Select-All intact (see `SelectAllAction`). No `isActive`
    /// gate is needed: a focused text field or a hidden iOS tab simply isn't in
    /// the focus chain, so the value is absent there by construction.
    public func selectAllCommandTarget<ID: Hashable>(
        in model: SelectionModel<ID>,
        ids: @autoclosure @escaping () -> [ID]
    ) -> some View {
        focusedValue(
            \.selectAllAction,
            SelectAllAction(identity: ObjectIdentifier(model)) {
                model.enterSelection()
                model.selectAll(ids())
            }
        )
    }
}
