import Foundation
import Testing

@testable import NexusCore

@Test func scheduledBlockStatus_rawValues_areStable() {
    #expect(ScheduledBlockStatus.proposed.rawValue == "proposed")
    #expect(ScheduledBlockStatus.accepted.rawValue == "accepted")
    #expect(ScheduledBlockStatus.allCases == [.proposed, .accepted])
}

@Test func scheduledBlockStatus_isCodable() throws {
    let encoded = try JSONEncoder().encode(ScheduledBlockStatus.accepted)
    let decoded = try JSONDecoder().decode(ScheduledBlockStatus.self, from: encoded)
    #expect(decoded == .accepted)
}

@Test func scheduledBlockOrigin_rawValues_areStable() {
    #expect(ScheduledBlockOrigin.auto.rawValue == "auto")
    #expect(ScheduledBlockOrigin.manual.rawValue == "manual")
    #expect(ScheduledBlockOrigin.allCases == [.auto, .manual])
}

@Test func scheduledBlockOrigin_isCodable() throws {
    let encoded = try JSONEncoder().encode(ScheduledBlockOrigin.manual)
    let decoded = try JSONDecoder().decode(ScheduledBlockOrigin.self, from: encoded)
    #expect(decoded == .manual)
}

@Test func durationSource_rawValues_areStable() {
    #expect(DurationSource.explicit.rawValue == "explicit")
    #expect(DurationSource.estimated.rawValue == "estimated")
    #expect(DurationSource.allCases == [.explicit, .estimated])
}

@Test func durationSource_isCodable() throws {
    let encoded = try JSONEncoder().encode(DurationSource.explicit)
    let decoded = try JSONDecoder().decode(DurationSource.self, from: encoded)
    #expect(decoded == .explicit)
}
