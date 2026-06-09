import Foundation

public protocol MeetingsModelPrefetching: Sendable {
    /// Ensures the model's files are present, downloading if needed. Reports
    /// 0.0...1.0 progress. Throws on download failure.
    func prefetch(_ id: MeetingsModelID, progress: @Sendable @escaping (Double) -> Void) async throws
}

extension MeetingsModelPrefetching {
    public func prefetchAll(progress: @Sendable @escaping (MeetingsModelID, Double) -> Void) async throws {
        for id in MeetingsModelID.allCases {
            try await prefetch(id) { fraction in progress(id, fraction) }
        }
    }
}
