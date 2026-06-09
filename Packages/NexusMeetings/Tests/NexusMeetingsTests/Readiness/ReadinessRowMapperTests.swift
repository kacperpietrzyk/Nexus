import Foundation
import Testing

@testable import NexusMeetings

@Suite("ReadinessRowMapper")
struct ReadinessRowMapperTests {
    private let mapper = ReadinessRowMapper(stalenessThreshold: 120)
    private let now = Date(timeIntervalSince1970: 10_000)

    private func snapshot(updated: Date) -> MeetingsReadinessSnapshot {
        MeetingsReadinessSnapshot(
            permissions: .init(microphone: .denied, accessibility: .granted, audioCapture: .unknown),
            models: [
                ModelReadiness(id: .parakeet, sizeBytes: 10, state: .ready),
                ModelReadiness(id: .sortformer, sizeBytes: nil, state: .absent),
                ModelReadiness(id: .whisperKit, sizeBytes: nil, state: .downloading(fraction: 0.25)),
            ],
            environment: .init(macOSCompatible: true, autoRecordEnabled: true),
            lastUpdated: updated
        )
    }

    @Test("nil snapshot yields a helper-not-running row with a start action")
    func nilSnapshot() {
        let sections = mapper.sections(from: nil, now: now)
        let environment = sections.first { $0.id == .environment }
        let helperRow = environment?.rows.first { $0.action == .startHelper }
        #expect(helperRow != nil)
        #expect(helperRow?.state == .error)
    }

    @Test("fresh snapshot maps permission/model/environment states and actions")
    func freshSnapshot() throws {
        let sections = mapper.sections(from: snapshot(updated: now.addingTimeInterval(-10)), now: now)

        let permissions = try #require(sections.first { $0.id == .permissions })
        let mic = try #require(permissions.rows.first { $0.action == .requestMicrophone })
        #expect(mic.state == .error)  // denied
        let accessibility = try #require(permissions.rows.first { $0.action == .openAccessibilitySettings })
        #expect(accessibility.state == .ok)  // granted
        let audio = try #require(
            permissions.rows.first { row in
                if case .info = row.action { return true } else { return false }
            })
        #expect(audio.state == .info)  // unknown → info ("prompts on first recording")

        let models = try #require(sections.first { $0.id == .models })
        #expect(models.rows.first { $0.action == .downloadModel(.parakeet) }?.state == .ok)
        #expect(models.rows.first { $0.action == .downloadModel(.sortformer) }?.state == .warning)
        #expect(models.rows.first { $0.action == .downloadModel(.whisperKit) }?.state == .inProgress)
        #expect(models.rows.contains { $0.action == .downloadAllModels })
    }

    @Test("stale snapshot still flags helper not running")
    func staleSnapshot() {
        let sections = mapper.sections(from: snapshot(updated: now.addingTimeInterval(-600)), now: now)
        let environment = sections.first { $0.id == .environment }
        #expect(environment?.rows.contains { $0.action == .startHelper && $0.state == .error } == true)
    }
}
