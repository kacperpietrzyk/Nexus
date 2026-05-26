import Foundation

public final class MeetingDetector: Sendable {
    private let poller: WindowTitlePoller
    private let debouncer: DetectionDebouncer
    private let correlator: CalendarCorrelator
    private let registryProvider: AppPatternRegistryProvider

    public init(
        poller: WindowTitlePoller,
        debouncer: DetectionDebouncer,
        correlator: CalendarCorrelator,
        registry: AppPatternRegistry,
        registryProvider: AppPatternRegistryProvider? = nil
    ) {
        self.poller = poller
        self.debouncer = debouncer
        self.correlator = correlator
        self.registryProvider = registryProvider ?? { registry }
    }

    public func events() -> AsyncStream<MeetingDetectionEvent> {
        AsyncStream { continuation in
            let task = Task {
                for await match in poller.matches() {
                    if Task.isCancelled {
                        break
                    }

                    let fingerprint =
                        match.fingerprint
                        ?? registryProvider().fingerprint(bundleID: match.bundleID, title: match.title)
                    guard debouncer.canEmit(fingerprint: fingerprint) else {
                        continue
                    }

                    let correlation = await correlator.correlate(at: match.observedAt)
                    if Task.isCancelled {
                        break
                    }

                    let sanitizedTitle = sanitize(match: match)
                    let suggestedTitle = correlation?.title ?? sanitizedTitle
                    let event = MeetingDetectionEvent(
                        fingerprint: fingerprint,
                        bundleID: match.bundleID,
                        pid: match.pid,
                        suggestedTitle: suggestedTitle,
                        detectedAt: match.observedAt,
                        calendarEventID: correlation?.eventID
                    )

                    if case .terminated = continuation.yield(event) {
                        break
                    }

                    debouncer.recordEmit(fingerprint: fingerprint)

                    if Task.isCancelled {
                        break
                    }
                }

                continuation.finish()
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    public func acknowledgeRecording(fingerprint: String) {
        debouncer.reset(fingerprint: fingerprint)
    }

    private func sanitize(match: WindowTitleMatch) -> String {
        let sanitized = match.normalizedTitle ?? registryProvider().normalizedTitle(match.title)
        return sanitized.isEmpty ? match.title : sanitized
    }
}
