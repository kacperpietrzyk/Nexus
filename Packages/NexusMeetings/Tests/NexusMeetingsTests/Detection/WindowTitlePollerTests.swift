import Foundation
import Testing

@testable import NexusMeetings

@MainActor
@Test func pollerEmitsWhenTitleMatches() async {
    let registry = AppPatternRegistry.makeDefault()
    let workspace = StubWorkspaceProvider(
        snapshots: [
            .init(
                bundleID: "com.microsoft.teams2",
                pid: 100,
                isFrontmost: true,
                windowTitles: ["Microsoft Teams Meeting"])
        ]
    )
    let poller = WindowTitlePoller(
        registry: registry, workspace: workspace,
        activeCadence: 0.01, idleCadence: 0.1)
    let emitted = await firstMatch(from: poller)

    #expect(emitted?.bundleID == "com.microsoft.teams2")
    #expect(emitted?.title == "Microsoft Teams Meeting")
}

@MainActor
@Test func pollerIgnoresNonMatchingTitles() async {
    let registry = AppPatternRegistry.makeDefault()
    let workspace = StubWorkspaceProvider(snapshots: [
        .init(
            bundleID: "com.microsoft.teams2",
            pid: 100, isFrontmost: false,
            windowTitles: ["Inbox — Microsoft Teams"])
    ])
    let poller = WindowTitlePoller(
        registry: registry, workspace: workspace,
        activeCadence: 0.01, idleCadence: 0.05)
    var seen = false
    let task = Task { @MainActor in
        for await _ in poller.matches() {
            seen = true
            break
        }
    }
    try? await Task.sleep(nanoseconds: 50_000_000)
    task.cancel()
    #expect(seen == false)
}

@MainActor
@Test func pollerReloadsRegistryProviderBetweenCycles() async {
    let registryBox = AppPatternRegistryBox(registry: .makeDefault())
    registryBox.registry.setEnabled("com.microsoft.teams2", enabled: false)
    let workspace = StubWorkspaceProvider(
        snapshots: [
            .init(
                bundleID: "com.microsoft.teams2",
                pid: 100,
                isFrontmost: true,
                windowTitles: ["Microsoft Teams Meeting"])
        ]
    )
    let poller = WindowTitlePoller(
        registry: registryBox.registry,
        workspace: workspace,
        registryProvider: { registryBox.registry },
        activeCadence: 0.01,
        idleCadence: 0.01
    )

    let task = Task { @MainActor in
        await firstMatch(from: poller, timeoutNanoseconds: 500_000_000)
    }
    try? await Task.sleep(nanoseconds: 50_000_000)
    registryBox.registry.setEnabled("com.microsoft.teams2", enabled: true)

    let emitted = await task.value

    #expect(emitted?.bundleID == "com.microsoft.teams2")
    #expect(emitted?.fingerprint != nil)
    #expect(emitted?.normalizedTitle != nil)
}

@MainActor
@Test func pollerTerminatesWhenConsumerCancels() async {
    let registry = AppPatternRegistry.makeDefault()
    let workspace = StubWorkspaceProvider(snapshots: [
        .init(
            bundleID: "com.microsoft.teams2",
            pid: 100,
            isFrontmost: true,
            windowTitles: ["Inbox — Microsoft Teams"])
    ])
    let poller = WindowTitlePoller(
        registry: registry, workspace: workspace,
        activeCadence: 0, idleCadence: -1)

    let task = Task { @MainActor in
        for await _ in poller.matches() {}
    }

    try? await Task.sleep(nanoseconds: 20_000_000)
    task.cancel()
    await task.value
}

@MainActor
private func firstMatch(
    from poller: WindowTitlePoller,
    timeoutNanoseconds: UInt64 = 500_000_000
) async -> WindowTitleMatch? {
    await withTaskGroup(of: WindowTitleMatch?.self) { group in
        group.addTask {
            for await match in poller.matches() {
                return match
            }
            return nil
        }
        group.addTask {
            try? await Task.sleep(nanoseconds: timeoutNanoseconds)
            return nil
        }

        guard let match = await group.next() else {
            group.cancelAll()
            return nil
        }
        group.cancelAll()
        return match
    }
}

private final class AppPatternRegistryBox: @unchecked Sendable {
    var registry: AppPatternRegistry

    init(registry: AppPatternRegistry) {
        self.registry = registry
    }
}

private final class StubWorkspaceProvider: WindowTitleWorkspaceProviding, @unchecked Sendable {
    var snapshots: [RunningAppSnapshot]

    init(snapshots: [RunningAppSnapshot]) {
        self.snapshots = snapshots
    }

    func currentSnapshots(trackedBundleIDs: Set<String>) -> [RunningAppSnapshot] {
        snapshots.filter { trackedBundleIDs.contains($0.bundleID) }
    }
}
