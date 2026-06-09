import AVFoundation
import AppKit
import Foundation
import NexusMeetings

/// Owns readiness snapshotting and app→helper command handling inside the helper process.
@MainActor
final class HelperReadinessCoordinator {
    private let computer: MeetingsReadinessComputer
    private let store: any MeetingsReadinessWriting
    private let prefetcher: any MeetingsModelPrefetching
    private let center = DistributedNotificationCenter.default()

    init(
        computer: MeetingsReadinessComputer,
        store: any MeetingsReadinessWriting,
        prefetcher: any MeetingsModelPrefetching
    ) {
        self.computer = computer
        self.store = store
        self.prefetcher = prefetcher
    }

    func start() {
        writeSnapshot()
        observe(MeetingsReadinessNotification.refreshReadiness) { [weak self] in self?.writeSnapshot() }
        observe(MeetingsReadinessNotification.requestPermissions) { [weak self] in self?.requestPermissions() }
        observe(MeetingsReadinessNotification.downloadModels) { [weak self] in self?.downloadModels() }
    }

    private func observe(_ name: Notification.Name, _ handler: @escaping @MainActor () -> Void) {
        center.addObserver(forName: name, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { handler() }
        }
    }

    private func writeSnapshot() {
        store.write(computer.snapshot())
        center.postNotificationName(
            MeetingsReadinessNotification.readinessDidChange,
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
    }

    private func requestPermissions() {
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] _ in
            Task { @MainActor in self?.writeSnapshot() }
        }
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    private func downloadModels() {
        Task { @MainActor in
            try? await prefetcher.prefetchAll { [weak self] _, _ in
                Task { @MainActor in self?.writeSnapshot() }
            }
            writeSnapshot()
        }
    }
}
