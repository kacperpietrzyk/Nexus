import Foundation
import Testing

@testable import TasksFeature

@Suite("CaptureChipModel project chip")
struct CaptureChipModelProjectTests {
    let now = Date(timeIntervalSince1970: 1_777_000_000)

    @Test("resolved project renders a folder chip with the canonical project name")
    func resolvedProjectChip() {
        let result = ParseResult(title: "ship", tags: ["work"], projectToken: "nexus", confidence: 0.95)
        let chips = CaptureChipModel.chips(for: result, now: now, resolvedProjectName: "Nexus")
        #expect(chips.contains { $0.icon == "folder" && $0.label == "Nexus" })
        #expect(!chips.contains { $0.icon == "folder.badge.questionmark" })
    }

    @Test("unresolved project renders a questionmark folder chip echoing the typed token")
    func unresolvedProjectChip() {
        let result = ParseResult(title: "ship", projectToken: "Unknown", confidence: 0.95)
        let chips = CaptureChipModel.chips(for: result, now: now, resolvedProjectName: nil)
        #expect(chips.contains { $0.icon == "folder.badge.questionmark" && $0.label == "@Unknown" })
    }

    @Test("project chip is emitted after tags and before recurrence")
    func projectChipOrder() {
        let result = ParseResult(
            title: "ship", tags: ["work"], projectToken: "nexus", recurrence: "FREQ=WEEKLY", confidence: 0.95)
        let labels = CaptureChipModel.chips(for: result, now: now, resolvedProjectName: "Nexus").map(\.label)
        #expect(labels == ["#work", "Nexus", "Repeats"])
    }

    @Test("no project token means no project chip")
    func noTokenNoChip() {
        let result = ParseResult(title: "ship", tags: ["work"], confidence: 0.95)
        let chips = CaptureChipModel.chips(for: result, now: now)
        #expect(!chips.contains { $0.icon == "folder" || $0.icon == "folder.badge.questionmark" })
    }
}
