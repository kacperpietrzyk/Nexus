import Foundation

#if canImport(AppKit)
import AppKit
import ApplicationServices
#endif

public struct RunningAppSnapshot: Sendable, Equatable {
    public let bundleID: String
    public let pid: Int32
    public let isFrontmost: Bool
    public let windowTitles: [String]

    public init(bundleID: String, pid: Int32, isFrontmost: Bool, windowTitles: [String]) {
        self.bundleID = bundleID
        self.pid = pid
        self.isFrontmost = isFrontmost
        self.windowTitles = windowTitles
    }
}

public protocol WindowTitleWorkspaceProviding: Sendable {
    func currentSnapshots(trackedBundleIDs: Set<String>) -> [RunningAppSnapshot]
}

public struct WindowTitleMatch: Sendable, Equatable {
    public let bundleID: String
    public let pid: Int32
    public let title: String
    public let fingerprint: String?
    public let normalizedTitle: String?
    public let observedAt: Date

    public init(
        bundleID: String,
        pid: Int32,
        title: String,
        fingerprint: String? = nil,
        normalizedTitle: String? = nil,
        observedAt: Date
    ) {
        self.bundleID = bundleID
        self.pid = pid
        self.title = title
        self.fingerprint = fingerprint
        self.normalizedTitle = normalizedTitle
        self.observedAt = observedAt
    }
}

public typealias AppPatternRegistryProvider = @Sendable () -> AppPatternRegistry

public final class WindowTitlePoller: Sendable {
    private static let minimumCadence: TimeInterval = 0.01

    private let registryProvider: AppPatternRegistryProvider
    private let workspace: any WindowTitleWorkspaceProviding
    private let activeCadence: TimeInterval
    private let idleCadence: TimeInterval

    public init(
        registry: AppPatternRegistry = .makeDefault(),
        workspace: any WindowTitleWorkspaceProviding,
        registryProvider: AppPatternRegistryProvider? = nil,
        activeCadence: TimeInterval = 2,
        idleCadence: TimeInterval = 10
    ) {
        self.registryProvider = registryProvider ?? { registry }
        self.workspace = workspace
        self.activeCadence = Self.clampedCadence(activeCadence)
        self.idleCadence = Self.clampedCadence(idleCadence)
    }

    /// Emits raw window-title observations; debouncing belongs to DetectionDebouncer/MeetingDetector.
    public func matches() -> AsyncStream<WindowTitleMatch> {
        AsyncStream { continuation in
            let task = Task {
                while !Task.isCancelled {
                    let registry = registryProvider()
                    let trackedBundleIDs = Set(registry.patterns.filter(\.enabled).map(\.bundleID))
                    let snapshots = workspace.currentSnapshots(trackedBundleIDs: trackedBundleIDs)
                    var hasFrontmostTrackedApp = false

                    for snapshot in snapshots where trackedBundleIDs.contains(snapshot.bundleID) {
                        if snapshot.isFrontmost {
                            hasFrontmostTrackedApp = true
                        }

                        for title in snapshot.windowTitles where registry.matches(bundleID: snapshot.bundleID, title: title) {
                            continuation.yield(
                                WindowTitleMatch(
                                    bundleID: snapshot.bundleID,
                                    pid: snapshot.pid,
                                    title: title,
                                    fingerprint: registry.fingerprint(
                                        bundleID: snapshot.bundleID,
                                        title: title
                                    ),
                                    normalizedTitle: registry.normalizedTitle(title),
                                    observedAt: Date()
                                )
                            )
                        }
                    }

                    let cadence = hasFrontmostTrackedApp ? activeCadence : idleCadence
                    try? await Task.sleep(nanoseconds: cadence.nanoseconds)
                }

                continuation.finish()
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private static func clampedCadence(_ cadence: TimeInterval) -> TimeInterval {
        guard cadence.isFinite else { return minimumCadence }
        return max(cadence, minimumCadence)
    }
}

#if canImport(AppKit)
public struct NSWorkspaceProvider: WindowTitleWorkspaceProviding {
    public init() {}

    public func currentSnapshots(trackedBundleIDs: Set<String>) -> [RunningAppSnapshot] {
        NSWorkspace.shared.runningApplications.compactMap { app -> RunningAppSnapshot? in
            guard let bundleID = app.bundleIdentifier else { return nil }
            guard trackedBundleIDs.contains(bundleID) else { return nil }
            return RunningAppSnapshot(
                bundleID: bundleID,
                pid: app.processIdentifier,
                isFrontmost: app.isActive,
                windowTitles: readWindowTitles(pid: app.processIdentifier)
            )
        }
    }

    private func readWindowTitles(pid: pid_t) -> [String] {
        let appElement = AXUIElementCreateApplication(pid)
        var windowsValue: CFTypeRef?
        let windowsResult = AXUIElementCopyAttributeValue(
            appElement,
            kAXWindowsAttribute as CFString,
            &windowsValue
        )

        guard windowsResult == .success, let windows = windowsValue as? [AXUIElement] else {
            return []
        }

        return windows.compactMap { window -> String? in
            var titleValue: CFTypeRef?
            let titleResult = AXUIElementCopyAttributeValue(
                window,
                kAXTitleAttribute as CFString,
                &titleValue
            )

            guard titleResult == .success else { return nil }
            return titleValue as? String
        }
    }
}
#endif

extension TimeInterval {
    fileprivate var nanoseconds: UInt64 {
        UInt64((self * 1_000_000_000).rounded())
    }
}
