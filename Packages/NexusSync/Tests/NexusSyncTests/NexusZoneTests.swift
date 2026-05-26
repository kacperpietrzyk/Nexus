import CloudKit
import Testing

@testable import NexusSync

@Test func nexusZone_id_isStable() {
    let id = NexusZone.zoneID
    #expect(id.zoneName == "NexusZone")
    #expect(id.ownerName == CKCurrentUserDefaultName)
}

@Test func nexusZone_recordZone_returnsExpectedID() {
    let zone = NexusZone.recordZone()
    #expect(zone.zoneID == NexusZone.zoneID)
}
