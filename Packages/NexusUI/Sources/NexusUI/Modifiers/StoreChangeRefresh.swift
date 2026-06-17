import CoreData
import SwiftData
import SwiftUI

extension View {
    /// Runs `action` whenever the underlying store changes — on a local save
    /// (`ModelContext.didSave`) **and** on a remote CloudKit / cross-process
    /// import (`.NSPersistentStoreRemoteChange`).
    ///
    /// Local writes post `ModelContext.didSave`, which manual-fetch views already
    /// reload on. CloudKit imports from other devices — and writes from a helper
    /// process recording into a *separate* persistent container — are merged on a
    /// background context and post `.NSPersistentStoreRemoteChange` instead, so a
    /// view observing only `didSave` never refreshes for those until it is
    /// re-created (the "switch tabs to see changes from other devices/the helper"
    /// symptom). Observing both keeps manual-fetch views live in either direction.
    ///
    /// Notifications are **coalesced** with a short trailing debounce: a burst of
    /// rapid saves (e.g. an agent/bulk import writing dozens of rows a second, or
    /// meeting processing) collapses into a single `action()` once writes go
    /// quiet. Without this every `didSave` re-ran each observing view's reload —
    /// and some reloads regenerate an on-device LLM brief, so a bulk import drove
    /// an Apple Foundation Models inference storm that dirtied gigabytes of
    /// file-backed memory and got the app resource-killed by the OS. The trailing
    /// edge guarantees the *final* state is identical to per-save reloading; only
    /// the number of intermediate reloads drops.
    ///
    /// `action` runs on the main actor (the remote-change notification arrives on
    /// a background queue, so the hop is handled here).
    public func reloadOnStoreChange(_ action: @escaping () -> Void) -> some View {
        modifier(ReloadOnStoreChange(action: action))
    }
}

/// Debounced store-change observer backing `View.reloadOnStoreChange`. Keeps a
/// single pending reload `Task` per view; each new notification cancels and
/// reschedules it, so a sustained write burst fires `action` only on the
/// trailing edge. The delay is small enough to be imperceptible for a single
/// user edit yet long enough to swallow an import's worth of saves.
private struct ReloadOnStoreChange: ViewModifier {
    let action: () -> Void
    @State private var pending: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { _ in
                schedule()
            }
            .onReceive(NotificationCenter.default.publisher(for: .NSPersistentStoreRemoteChange)) { _ in
                schedule()
            }
            .onDisappear {
                pending?.cancel()
                pending = nil
            }
    }

    private func schedule() {
        pending?.cancel()
        pending = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(StoreChangeCoalescer.windowMilliseconds))
            guard !Task.isCancelled else { return }
            action()
        }
    }
}

/// Pure, view-independent model of the trailing-edge debounce that
/// `reloadOnStoreChange` applies, factored out so the coalescing contract can be
/// unit-tested without SwiftUI. Feeding it a stream of timestamped events
/// reproduces exactly which events would have *fired* a reload: a burst inside
/// one window collapses to a single trailing fire; events spaced farther apart
/// than the window each fire on their own.
public enum StoreChangeCoalescer {
    /// Trailing debounce window. Imperceptible for a single user edit, long
    /// enough to swallow a bulk import's worth of saves.
    public static let windowMilliseconds = 400

    /// Given event arrival times (any monotonically comparable unit, e.g.
    /// milliseconds), returns the times at which a trailing-edge debounce of
    /// `window` would actually fire `action`.
    ///
    /// An event fires only if no later event arrives within `window` of it —
    /// i.e. it is the last event of its burst. This mirrors "cancel + reschedule
    /// the pending task on every new event": only the task that is never
    /// cancelled survives to run.
    public static func firedTimes<T: Comparable & AdditiveArithmetic>(
        events: [T],
        window: T
    ) -> [T] {
        guard !events.isEmpty else { return [] }
        let sorted = events.sorted()
        var fired: [T] = []
        for index in sorted.indices {
            let isLastOfBurst: Bool
            if index == sorted.indices.last {
                isLastOfBurst = true
            } else {
                // The next event arrives more than `window` later → this one is
                // the trailing edge of its burst and would fire.
                isLastOfBurst = sorted[index + 1] - sorted[index] > window
            }
            if isLastOfBurst {
                fired.append(sorted[index] + window)
            }
        }
        return fired
    }
}
