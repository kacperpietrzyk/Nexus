import Foundation

@MainActor
public final class SummaryFallbackScheduler {
    private let timeout: Duration
    private let status: (UUID) -> String?
    private let run: (UUID, URL) async -> Void
    private var tasks: [UUID: Task<Void, Never>] = [:]

    public init(
        timeout: Duration = .seconds(25),
        status: @escaping (UUID) -> String?,
        run: @escaping (UUID, URL) async -> Void
    ) {
        self.timeout = timeout
        self.status = status
        self.run = run
    }

    public func schedule(meetingID: UUID, audioFolder: URL) {
        tasks[meetingID]?.cancel()
        tasks[meetingID] = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: self.timeout)
            guard !Task.isCancelled else { return }
            self.tasks[meetingID] = nil
            guard let current = self.status(meetingID) else { return }
            guard SummaryFallbackDecision.shouldRun(currentStatus: current) else { return }
            await self.run(meetingID, audioFolder)
        }
    }

    public func cancel(meetingID: UUID) {
        tasks[meetingID]?.cancel()
        tasks[meetingID] = nil
    }
}
