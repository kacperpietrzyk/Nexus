import Foundation
import Testing

@testable import NexusMeetings

private actor RecordingPrefetcher: MeetingsModelPrefetching {
    private(set) var requested: [MeetingsModelID] = []
    func prefetch(_ id: MeetingsModelID, progress: @Sendable @escaping (Double) -> Void) async throws {
        requested.append(id)
        progress(1.0)
    }
}

@Suite("MeetingsModelPrefetching")
struct MeetingsModelPrefetchingTests {
    @Test("prefetchAll invokes prefetch for every model id")
    func prefetchAll() async throws {
        let prefetcher = RecordingPrefetcher()
        try await prefetcher.prefetchAll(progress: { _, _ in })
        let requested = await prefetcher.requested
        #expect(Set(requested) == Set(MeetingsModelID.allCases))
    }
}
