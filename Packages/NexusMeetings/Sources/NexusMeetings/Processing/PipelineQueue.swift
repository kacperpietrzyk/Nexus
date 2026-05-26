import Foundation

public actor PipelineQueue {
    public typealias Job = @MainActor () async -> Void

    private var pending: [Job] = []
    private var running = false

    public init() {}

    public func enqueue(_ job: @escaping Job) {
        pending.append(job)
        Task { await drainIfNeeded() }
    }

    public func waitUntilEmpty() async throws {
        while running || pending.isEmpty == false {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    private func drainIfNeeded() async {
        guard running == false else { return }
        running = true
        while pending.isEmpty == false {
            let next = pending.removeFirst()
            await next()
        }
        running = false
    }
}
