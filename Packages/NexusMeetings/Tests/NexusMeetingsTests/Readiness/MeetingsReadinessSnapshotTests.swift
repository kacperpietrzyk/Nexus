import Foundation
import Testing
@testable import NexusMeetings

@Suite("MeetingsReadinessSnapshot")
struct MeetingsReadinessSnapshotTests {
    @Test("round-trips through Codable including enum associated values")
    func roundTrip() throws {
        let snapshot = MeetingsReadinessSnapshot(
            permissions: .init(microphone: .granted, accessibility: .denied, audioCapture: .unknown),
            models: [
                ModelReadiness(id: .parakeet, downloaded: true, sizeBytes: 1_234, state: .ready),
                ModelReadiness(
                    id: .sortformer,
                    downloaded: false,
                    sizeBytes: nil,
                    state: .downloading(fraction: 0.5)
                ),
                ModelReadiness(
                    id: .whisperKit,
                    downloaded: false,
                    sizeBytes: nil,
                    state: .failed(reason: "network")
                ),
            ],
            environment: .init(macOSCompatible: true, autoRecordEnabled: false),
            lastUpdated: Date(timeIntervalSince1970: 1_000)
        )

        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(MeetingsReadinessSnapshot.self, from: data)

        #expect(decoded == snapshot)
        #expect(decoded.models[1].state == .downloading(fraction: 0.5))
        #expect(decoded.models[2].state == .failed(reason: "network"))
    }
}
