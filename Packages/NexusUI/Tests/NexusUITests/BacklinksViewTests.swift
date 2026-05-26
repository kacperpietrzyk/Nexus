import Foundation
import NexusCore
import SwiftUI
import Testing

@testable import NexusUI

@MainActor
@Test func backlinks_emptyState_rendersWithoutCrash() {
    let view = BacklinksView(items: [])
    _ = view.body
    #expect(view.items.isEmpty)
}

@MainActor
@Test func backlinks_withItems_exposesCount() {
    let items: [any Linkable] = [
        TaskItem(title: "First"),
        TaskItem(title: "Second"),
        TaskItem(title: "Third"),
    ]
    let view = BacklinksView(items: items)
    #expect(view.items.count == 3)
}

@MainActor
@Test func backlinks_emptyMessage_isCustomizable() {
    let view = BacklinksView(items: [], emptyMessage: "Nothing links here yet")
    #expect(view.emptyMessage == "Nothing links here yet")
}
