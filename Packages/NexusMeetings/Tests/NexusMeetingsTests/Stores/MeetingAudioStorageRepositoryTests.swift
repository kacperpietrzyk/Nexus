import Foundation
import SwiftData
import Testing

@testable import NexusMeetings

@MainActor
@Test func storageInsertAndFind() throws {
    let context = try MeetingsTestSupport.makeContext()
    let repo = MeetingAudioStorageRepository(context: context)
    let id = UUID()
    let storage = MeetingAudioStorage(
        meetingID: id,
        folderURL: URL(fileURLWithPath: "/tmp/\(id)"),
        retentionPolicy: .days30
    )
    try repo.insert(storage)
    let fetched = try repo.find(meetingID: id)
    #expect(fetched?.meetingID == id)
}

@MainActor
@Test func expiringSoonReturnsPastExpiries() throws {
    let context = try MeetingsTestSupport.makeContext()
    let repo = MeetingAudioStorageRepository(context: context)
    let oldID = UUID()
    let recentID = UUID()
    let foreverID = UUID()
    let old = MeetingAudioStorage(
        meetingID: oldID,
        folderURL: URL(fileURLWithPath: "/tmp/\(oldID)"),
        retentionPolicy: .never
    )
    let recent = MeetingAudioStorage(
        meetingID: recentID,
        folderURL: URL(fileURLWithPath: "/tmp/\(recentID)"),
        retentionPolicy: .days30
    )
    let foreverStorage = MeetingAudioStorage(
        meetingID: foreverID,
        folderURL: URL(fileURLWithPath: "/tmp/\(foreverID)"),
        retentionPolicy: .forever
    )
    try repo.insert(old)
    try repo.insert(recent)
    try repo.insert(foreverStorage)
    let expired = try repo.expired(asOf: Date())
    #expect(expired.map(\.meetingID) == [oldID])
}
