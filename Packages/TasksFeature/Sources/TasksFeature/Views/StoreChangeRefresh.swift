import CoreData
import SwiftData
import SwiftUI

extension View {
    /// Runs `action` whenever the underlying store changes — on a local save
    /// (`ModelContext.didSave`) **and** on a remote CloudKit import
    /// (`.NSPersistentStoreRemoteChange`).
    ///
    /// Local writes post `ModelContext.didSave`, which these task views already
    /// reloaded on. CloudKit imports from other devices, however, are merged on a
    /// background context and post `.NSPersistentStoreRemoteChange` instead — so a
    /// view observing only `didSave` never refreshes for synced changes until it is
    /// re-created (the "switch tabs to see tasks from other devices" symptom).
    /// Observing both keeps manual-fetch views live in either direction.
    ///
    /// Notifications are **coalesced** with a short trailing debounce: a burst of
    /// rapid saves (e.g. an agent/bulk import writing dozens of rows a second)
    /// collapses into a single `action()` once writes go quiet. Without this every
    /// `didSave` re-ran each observing view's reload — and Today's reload
    /// regenerates the on-device LLM brief, so a bulk import drove an Apple
    /// Foundation Models inference storm that dirtied gigabytes of file-backed
    /// memory and got the app resource-killed by the OS.
    func reloadOnStoreChange(_ action: @escaping () -> Void) -> some View {
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
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            action()
        }
    }
}
