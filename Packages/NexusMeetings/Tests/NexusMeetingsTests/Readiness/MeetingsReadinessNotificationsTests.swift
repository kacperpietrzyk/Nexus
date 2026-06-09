import Foundation
import Testing
@testable import NexusMeetings

@Suite("MeetingsReadinessNotifications")
struct MeetingsReadinessNotificationsTests {
    @Test("names use the established meetings reverse-DNS prefix")
    func names() {
        #expect(
            MeetingsReadinessNotification.requestPermissions.rawValue
                == "com.kacperpietrzyk.nexus.meetings.requestPermissions"
        )
        #expect(
            MeetingsReadinessNotification.downloadModels.rawValue
                == "com.kacperpietrzyk.nexus.meetings.downloadModels"
        )
        #expect(
            MeetingsReadinessNotification.refreshReadiness.rawValue
                == "com.kacperpietrzyk.nexus.meetings.refreshReadiness"
        )
        #expect(
            MeetingsReadinessNotification.readinessDidChange.rawValue
                == "com.kacperpietrzyk.nexus.meetings.readinessDidChange"
        )
    }
}
