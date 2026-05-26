import Foundation
import NexusSync
import Testing

@testable import NexusMeetings

@Test func meetingAudioRootPrefersAppGroupContainer() {
    let groupURL = URL(fileURLWithPath: "/group/container")
    let applicationSupportURL = URL(fileURLWithPath: "/user/Application Support")

    let root = MeetingAudioRootResolver.resolveRootFolder(
        groupContainerURL: groupURL,
        applicationSupportURL: applicationSupportURL
    )

    #expect(root.path == "/group/container/Nexus/Meetings")
}

@Test func meetingAudioRootFallsBackToApplicationSupport() {
    let applicationSupportURL = URL(fileURLWithPath: "/user/Application Support")

    let root = MeetingAudioRootResolver.resolveRootFolder(
        groupContainerURL: nil,
        applicationSupportURL: applicationSupportURL
    )

    #expect(root.path == "/user/Application Support/com.kacperpietrzyk.Nexus/Meetings")
}
