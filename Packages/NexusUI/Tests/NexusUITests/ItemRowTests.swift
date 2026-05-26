import Foundation
import NexusCore
import SwiftUI
import Testing

@testable import NexusUI

@MainActor
@Test func itemRow_rendersTaskItem() {
    let item = TaskItem(title: "Plan 0c review")
    let row = ItemRow(item: item)
    #expect(row.title == "Plan 0c review")
    #expect(row.kind == .task)
}

@MainActor
@Test func itemRow_titleFormatter_truncatesLongTitles() {
    let long = String(repeating: "x", count: 200)
    let item = TaskItem(title: long)
    let row = ItemRow(item: item, maxTitleLength: 60)
    #expect(row.displayTitle.count <= 61)  // 60 + ellipsis
    #expect(row.displayTitle.hasSuffix("…"))
}

@MainActor
@Test func itemRow_initializesViaLinkable() {
    let item: any Linkable = TaskItem(title: "x")
    let row = ItemRow(item: item)
    _ = row.body
}

@MainActor
@Test func itemRow_chipTone_isNeutralForAllKinds() {
    #expect(ItemRow.chipTone(for: .task) == .neutral)
    #expect(ItemRow.chipTone(for: .note) == .neutral)
    #expect(ItemRow.chipTone(for: .meeting) == .neutral)
    #expect(ItemRow.chipTone(for: .project) == .neutral)
    #expect(ItemRow.chipTone(for: .section) == .neutral)
    #expect(ItemRow.chipTone(for: .savedFilter) == .neutral)
    #expect(ItemRow.chipTone(for: .debug) == .neutral)
    #expect(ItemRow.chipTone(for: .agentMemory) == .neutral)
}

@MainActor
@Test func itemRow_background_isFlatNotOpaqueRaised() {
    let row = ItemRow(item: TaskItem(title: "x"))
    #expect(row.rowBackgroundColor.resolvedRGBA == Color.clear.resolvedRGBA)
    #expect(row.rowBackgroundColor.resolvedRGBA != NexusColor.Background.raised.resolvedRGBA)
}

@MainActor
@Test func itemRow_iconName_coversAllKinds() {
    #expect(ItemRow.iconName(for: .note) == "doc.text")
    #expect(ItemRow.iconName(for: .task) == "checkmark.circle")
    #expect(ItemRow.iconName(for: .meeting) == "person.2")
    #expect(ItemRow.iconName(for: .project) == "folder")
    #expect(ItemRow.iconName(for: .section) == "square.split.2x1")
    #expect(ItemRow.iconName(for: .savedFilter) == "line.3.horizontal.decrease.circle")
    #expect(ItemRow.iconName(for: .debug) == "ladybug")
}
