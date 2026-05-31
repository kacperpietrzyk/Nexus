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
    func reloadOnStoreChange(_ action: @escaping () -> Void) -> some View {
        self
            .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { _ in
                action()
            }
            .onReceive(NotificationCenter.default.publisher(for: .NSPersistentStoreRemoteChange)) { _ in
                action()
            }
    }
}
