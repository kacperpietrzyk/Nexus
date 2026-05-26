import Foundation
import Testing

@testable import NexusMeetings

@MainActor
@Test func listViewModelFiltersByThisWeek() throws {
    let context = try MeetingsTestSupport.makeContext()
    let repo = MeetingRepository(context: context)
    let now = Date()
    let recent = MeetingsTestSupport.meeting(title: "Recent", startedAt: now.addingTimeInterval(-3600))
    let old = MeetingsTestSupport.meeting(title: "Old", startedAt: now.addingTimeInterval(-30 * 86_400))
    try repo.insert(recent)
    try repo.insert(old)
    let vm = MeetingsListViewModel(repository: repo, clock: { now })
    vm.filter = .thisWeek
    vm.reload()
    #expect(vm.items.map(\.title) == ["Recent"])
}

@MainActor
@Test func listViewModelHasActionsFilter() throws {
    let context = try MeetingsTestSupport.makeContext()
    let repo = MeetingRepository(context: context)
    let withActions = MeetingsTestSupport.meeting(title: "With")
    withActions.actionItemIDs = [UUID()]
    let none = MeetingsTestSupport.meeting(title: "None")
    try repo.insert(withActions)
    try repo.insert(none)
    let vm = MeetingsListViewModel(repository: repo)
    vm.filter = .hasActions
    vm.reload()
    #expect(vm.items.map(\.title) == ["With"])
}

@MainActor
@Test func listViewModelExcludesSoftDeletedMeetings() throws {
    let context = try MeetingsTestSupport.makeContext()
    let repo = MeetingRepository(context: context)
    let visible = MeetingsTestSupport.meeting(title: "Visible")
    let deleted = MeetingsTestSupport.meeting(title: "Deleted")
    deleted.deletedAt = Date()
    try repo.insert(visible)
    try repo.insert(deleted)
    let vm = MeetingsListViewModel(repository: repo)
    vm.reload()
    #expect(vm.items.map(\.title) == ["Visible"])
}
