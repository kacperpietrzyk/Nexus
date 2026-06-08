import Foundation
import Testing

@testable import NexusCore

@Suite("Label model + groups")
struct LabelTests {
    @Test("Label kind is fixed to .label and Searchable returns name")
    func labelKindAndSearchable() {
        let label = Label(name: "feature", glyphKey: "sparkles", group: .domain)
        #expect(label.kind == .label)
        #expect(label.title == "feature")
        #expect(label.searchableText == "feature")
        #expect(label.group == .domain)
        #expect(label.isSystem == false)
        #expect(label.deletedAt == nil)
    }

    @Test("group accessor falls back to free for an unknown raw")
    func unknownGroupRawFallsBackToFree() {
        let label = Label(name: "x")
        label.groupRaw = "nonsense"
        #expect(label.group == .free)
    }

    @Test("LabelGroup raw values are stable")
    func labelGroupRawValues() {
        #expect(LabelGroup.domain.rawValue == "domain")
        #expect(LabelGroup.gate.rawValue == "gate")
        #expect(LabelGroup.free.rawValue == "free")
    }

    @Test("domain and gate are single-select; free is multi")
    func singleSelectFlags() {
        #expect(LabelGroup.domain.isSingleSelect)
        #expect(LabelGroup.gate.isSingleSelect)
        #expect(!LabelGroup.free.isSingleSelect)
    }

    @Test("SystemLabel catalog maps names to the right groups")
    func systemLabelGroups() {
        #expect(SystemLabel.feature.group == .domain)
        #expect(SystemLabel.bug.group == .domain)
        #expect(SystemLabel.infra.group == .domain)
        #expect(SystemLabel.security.group == .domain)
        #expect(SystemLabel.needsDecision.group == .gate)
        #expect(SystemLabel.decided.group == .gate)
        // Every system label carries a non-empty achromatic glyph key.
        for system in SystemLabel.allCases {
            #expect(!system.glyphKey.isEmpty)
        }
    }
}

@Suite("suggestedAgent auto-derive (spec §8)")
struct AgentSuggestionTests {
    private func label(_ name: String, group: LabelGroup) -> Label {
        Label(name: name, group: group)
    }

    @Test("bug domain label suggests codex")
    func bugSuggestsCodex() {
        #expect(suggestedAgent(forLabels: [label("bug", group: .domain)]) == .codex)
    }

    @Test("feature domain label suggests claude")
    func featureSuggestsClaude() {
        #expect(suggestedAgent(forLabels: [label("feature", group: .domain)]) == .claude)
    }

    @Test("no driving label yields no suggestion")
    func noSuggestionForUnrelatedLabels() {
        #expect(suggestedAgent(forLabels: [label("infra", group: .domain), label("urgent", group: .free)]) == nil)
        #expect(suggestedAgent(forLabels: []) == nil)
    }

    @Test("a free-group label named bug does not drive a suggestion (domain only)")
    func freeGroupNamedBugIgnored() {
        #expect(suggestedAgent(forLabels: [label("bug", group: .free)]) == nil)
    }

    @Test("a soft-deleted bug label is ignored")
    func softDeletedLabelIgnored() {
        let bug = label("bug", group: .domain)
        bug.deletedAt = .now
        #expect(suggestedAgent(forLabels: [bug]) == nil)
    }
}
