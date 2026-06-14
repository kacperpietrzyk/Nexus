import Foundation
import Testing

@testable import TasksFeature

@Suite("ProjectExecutionModel.keyDateDiff pure helper")
struct ProjectKeyDateDiffTests {

    private static let baseDate = Date(timeIntervalSince1970: 1_700_000_000)
    private static let otherDate = Date(timeIntervalSince1970: 1_800_000_000)

    private func draft(
        key: String,
        label: String = "Label",
        date: Date = ProjectKeyDateDiffTests.baseDate,
        isContractual: Bool = false
    ) -> ProjectExecutionModel.KeyDateDraft {
        .init(anchorKey: key, label: label, date: date, isContractual: isContractual)
    }

    // MARK: - Add new

    @Test("New anchor produces upsert, no deletions")
    func addNew() {
        let current: [ProjectExecutionModel.KeyDateDraft] = []
        let desired = [draft(key: "PO")]

        let result = ProjectExecutionModel.keyDateDiff(current: current, desired: desired)

        #expect(result.upserts.count == 1)
        #expect(result.upserts[0].anchorKey == "PO")
        #expect(result.deletions.isEmpty)
    }

    // MARK: - Update existing

    @Test("Changed date produces upsert")
    func updateChangedDate() {
        let current = [draft(key: "PO", date: Self.baseDate)]
        let desired = [draft(key: "PO", date: Self.otherDate)]

        let result = ProjectExecutionModel.keyDateDiff(current: current, desired: desired)

        #expect(result.upserts.count == 1)
        #expect(result.upserts[0].date == Self.otherDate)
        #expect(result.deletions.isEmpty)
    }

    @Test("Changed label produces upsert")
    func updateChangedLabel() {
        let current = [draft(key: "T0", label: "Start")]
        let desired = [draft(key: "T0", label: "Kick-off")]

        let result = ProjectExecutionModel.keyDateDiff(current: current, desired: desired)

        #expect(result.upserts.count == 1)
        #expect(result.upserts[0].label == "Kick-off")
        #expect(result.deletions.isEmpty)
    }

    @Test("Changed isContractual produces upsert")
    func updateChangedContractual() {
        let current = [draft(key: "T0", isContractual: false)]
        let desired = [draft(key: "T0", isContractual: true)]

        let result = ProjectExecutionModel.keyDateDiff(current: current, desired: desired)

        #expect(result.upserts.count == 1)
        #expect(result.upserts[0].isContractual == true)
        #expect(result.deletions.isEmpty)
    }

    // MARK: - Remove

    @Test("Anchor absent from desired produces deletion, no upsert")
    func removeAnchor() {
        let current = [draft(key: "PO"), draft(key: "T0")]
        let desired = [draft(key: "PO")]

        let result = ProjectExecutionModel.keyDateDiff(current: current, desired: desired)

        #expect(result.deletions == ["T0"])
        // PO is unchanged — no upsert needed.
        #expect(result.upserts.isEmpty)
    }

    // MARK: - No-op

    @Test("Identical drafts produce no upserts and no deletions")
    func noOpWhenIdentical() {
        let current = [draft(key: "PO"), draft(key: "T0")]
        let desired = [draft(key: "PO"), draft(key: "T0")]

        let result = ProjectExecutionModel.keyDateDiff(current: current, desired: desired)

        #expect(result.upserts.isEmpty)
        #expect(result.deletions.isEmpty)
    }

    // MARK: - Combined

    @Test("Mixed add/update/remove/no-op all computed correctly in one call")
    func combinedDiff() {
        let current = [
            draft(key: "T0", label: "Old Label"),
            draft(key: "PO"),
            draft(key: "KICK"),
        ]
        let desired = [
            draft(key: "T0", label: "New Label"),  // update
            draft(key: "PO"),  // no-op
            draft(key: "DECISION"),  // add
            // KICK is removed
        ]

        let result = ProjectExecutionModel.keyDateDiff(current: current, desired: desired)

        let upsertKeys = Set(result.upserts.map(\.anchorKey))
        #expect(upsertKeys == ["T0", "DECISION"])
        #expect(result.deletions == ["KICK"])
    }

    // MARK: - Crash safety

    @Test("Duplicate anchorKey in current does not trap (hardened dictionary build)")
    func duplicateAnchorKeyDoesNotTrap() {
        // A corrupt import could yield two rows sharing an anchorKey; the diff must
        // not crash building its keyed lookup. The last duplicate wins.
        let current = [
            draft(key: "PO", label: "First"),
            draft(key: "PO", label: "Second"),
        ]
        let desired = [draft(key: "PO", label: "Second")]

        let result = ProjectExecutionModel.keyDateDiff(current: current, desired: desired)

        // Desired matches the last-wins current entry, so no upsert; nothing deleted.
        #expect(result.upserts.isEmpty)
        #expect(result.deletions.isEmpty)
    }
}
