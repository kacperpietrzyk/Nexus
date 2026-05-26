import Testing

@testable import NexusMeetings

@Test func packageLoads() {
    #expect(NexusMeetingsInfo.identifier == "com.kacperpietrzyk.nexus.meetings")
    #expect(NexusMeetingsInfo.versionTag == "1j")
}
