// NexusNavigator: the shell-owned navigation keystone for macOS.
//
// Owns the current `destination`, the optional detail breadcrumb, and a
// back/forward `NavigationHistory` (the tested pure value type from NexusCore).
// Destinations drive it via `open(_:deepLink:)`, set their own `detailCrumb`
// and `onPopToRoot`, and consume the `pendingDeepLink` it stages.

import NexusCore
import Observation
import TasksFeature

@MainActor
@Observable
final class NexusNavigator {
    /// The active top-level destination.
    private(set) var destination: TodayNavSelection

    /// Detail breadcrumb for the current page, or `nil` at the destination root.
    /// The active destination sets this when it pushes a detail and clears it on root.
    var detailCrumb: NavCrumb?

    /// Set by the active destination; clears that destination's own selection so
    /// `popToRoot()` returns the destination to its root list.
    var onPopToRoot: (() -> Void)?

    /// A deep link staged by `open`/`goBack`/`goForward` for the active
    /// destination to consume (open the item, then re-resolve its `detailCrumb`).
    /// The destination should nil this out once consumed.
    var pendingDeepLink: DeepLinkTarget?

    /// Pure back/forward stack (delegated to — not reimplemented).
    private(set) var history: NavigationHistory

    init(destination: TodayNavSelection = .today) {
        self.destination = destination
        self.history = NavigationHistory(
            current: NavLocation(destinationToken: destination.token, detailToken: nil)
        )
    }

    // MARK: Breadcrumbs

    /// `[root]` + optional leaf detail crumb.
    var crumbs: [NavCrumb] {
        let root = NavCrumb(id: "root", label: destination.title, isLeaf: detailCrumb == nil)
        return [root] + (detailCrumb.map { [$0] } ?? [])
    }

    // MARK: History flags

    var canGoBack: Bool { history.canGoBack }
    var canGoForward: Bool { history.canGoForward }

    // MARK: Navigation

    /// Switches to `destination`, optionally staging a deep link, and records the
    /// move in history. Clears any stale detail crumb — the destination re-sets it.
    func open(_ destination: TodayNavSelection, deepLink: DeepLinkTarget? = nil) {
        self.destination = destination
        detailCrumb = nil
        pendingDeepLink = deepLink
        history.visit(
            NavLocation(destinationToken: destination.token, detailToken: deepLink?.token)
        )
    }

    /// Returns the active destination to its root: clears the detail crumb and
    /// asks the destination to clear its own selection.
    func popToRoot() {
        detailCrumb = nil
        pendingDeepLink = nil
        onPopToRoot?()
    }

    /// Restores destination + detail from one step back in history.
    func goBack() {
        guard let location = history.goBack() else { return }
        restore(location)
    }

    /// Restores destination + detail from one step forward in history.
    func goForward() {
        guard let location = history.goForward() else { return }
        restore(location)
    }

    /// Applies a restored `NavLocation`: sets the destination and re-stages the
    /// deep link (if any) so the destination re-resolves its own detail crumb.
    private func restore(_ location: NavLocation) {
        if let destination = TodayNavSelection.from(token: location.destinationToken) {
            self.destination = destination
        }
        detailCrumb = nil
        pendingDeepLink = location.detailToken.flatMap(DeepLinkTarget.init(token:))
    }
}
