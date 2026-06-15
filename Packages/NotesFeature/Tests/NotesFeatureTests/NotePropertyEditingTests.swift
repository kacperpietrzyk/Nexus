import Foundation
import NexusCore
import Testing

@testable import NotesFeature

@Suite("NotePropertyEditing")
struct NotePropertyEditingTests {
    private let base = [
        NoteProperty(key: "status", value: .string("active")),
        NoteProperty(key: "priority", value: .number(2)),
    ]

    // MARK: - add / rename / setValue / remove

    @Test("add appends a trimmed key with an empty string value; rejects blank and duplicate keys")
    func add() {
        let added = NotePropertyEditing.add(key: "  owner ", to: base)
        #expect(added == base + [NoteProperty(key: "owner", value: .string(""))])
        #expect(NotePropertyEditing.add(key: "   ", to: base) == nil)
        #expect(NotePropertyEditing.add(key: "status", to: base) == nil)  // case-sensitive unique
    }

    @Test("rename keeps position and value; rejects missing source, blank or colliding target")
    func rename() {
        let renamed = NotePropertyEditing.rename(key: "status", to: " state ", in: base)
        #expect(
            renamed == [
                NoteProperty(key: "state", value: .string("active")),
                NoteProperty(key: "priority", value: .number(2)),
            ])
        #expect(NotePropertyEditing.rename(key: "missing", to: "x", in: base) == nil)
        #expect(NotePropertyEditing.rename(key: "status", to: "", in: base) == nil)
        #expect(NotePropertyEditing.rename(key: "status", to: "priority", in: base) == nil)
        // Renaming to itself is a valid no-op.
        #expect(NotePropertyEditing.rename(key: "status", to: "status", in: base) == base)
    }

    @Test("setValue replaces in place; nil for a missing key")
    func setValue() {
        let updated = NotePropertyEditing.setValue(.bool(true), forKey: "priority", in: base)
        #expect(updated?[1] == NoteProperty(key: "priority", value: .bool(true)))
        #expect(NotePropertyEditing.setValue(.bool(true), forKey: "missing", in: base) == nil)
    }

    @Test("remove drops the key; unknown key is a no-op")
    func remove() {
        #expect(NotePropertyEditing.remove(key: "status", from: base) == [base[1]])
        #expect(NotePropertyEditing.remove(key: "missing", from: base) == base)
    }

    // MARK: - type conversion

    @Test("convert maps between property types best-effort and is identity for the same type")
    func convert() {
        let anchor = Date(timeIntervalSince1970: 1_700_000_000)
        #expect(NotePropertyEditing.convert(.number(2.5), to: .text, now: anchor) == .string("2.5"))
        #expect(NotePropertyEditing.convert(.string("3"), to: .number, now: anchor) == .number(3))
        #expect(NotePropertyEditing.convert(.string("abc"), to: .number, now: anchor) == .number(0))
        #expect(NotePropertyEditing.convert(.string("true"), to: .boolean, now: anchor) == .bool(true))
        #expect(NotePropertyEditing.convert(.string("nope"), to: .boolean, now: anchor) == .bool(false))
        #expect(NotePropertyEditing.convert(.string("a, b ,c"), to: .list, now: anchor) == .list(["a", "b", "c"]))
        #expect(NotePropertyEditing.convert(.list(["a", "b"]), to: .text, now: anchor) == .string("a, b"))
        #expect(NotePropertyEditing.convert(.string("x"), to: .date, now: anchor) == .date(anchor))
        #expect(
            NotePropertyEditing.convert(.string("2023-11-14T22:13:20Z"), to: .date, now: anchor)
                == .date(Date(timeIntervalSince1970: 1_700_000_000))
        )
        // Identity: same type returns the value untouched.
        #expect(NotePropertyEditing.convert(.bool(true), to: .boolean, now: anchor) == .bool(true))
    }

    @Test("PropertyType classifies every NotePropertyValue case")
    func propertyType() {
        #expect(NotePropertyEditing.PropertyType(of: .string("x")) == .text)
        #expect(NotePropertyEditing.PropertyType(of: .number(1)) == .number)
        #expect(NotePropertyEditing.PropertyType(of: .bool(true)) == .boolean)
        #expect(NotePropertyEditing.PropertyType(of: .date(.now)) == .date)
        #expect(NotePropertyEditing.PropertyType(of: .list([])) == .list)
    }

    @Test("numberText collapses integral doubles")
    func numberText() {
        #expect(NotePropertyEditing.numberText(2.0) == "2")
        #expect(NotePropertyEditing.numberText(2.5) == "2.5")
    }
}

@Suite("NoteEditorModel organization state")
@MainActor
struct NoteEditorModelOrganizationTests {
    @Test("property ops mutate ordered state even without a repository")
    func propertyOps() {
        let note = Note(title: "n")
        let model = NoteEditorModel(note: note, repository: nil)

        model.addProperty(key: "status")
        #expect(model.properties == [NoteProperty(key: "status", value: .string(""))])

        model.setPropertyValue(.string("active"), forKey: "status")
        #expect(model.properties == [NoteProperty(key: "status", value: .string("active"))])

        model.renameProperty("status", to: "state")
        #expect(model.properties == [NoteProperty(key: "state", value: .string("active"))])

        model.removeProperty("state")
        #expect(model.properties.isEmpty)
    }

    @Test("duplicate add and colliding rename are rejected without state change")
    func rejections() {
        let note = Note(title: "n")
        let model = NoteEditorModel(note: note, repository: nil)
        model.addProperty(key: "a")
        model.addProperty(key: "b")

        model.addProperty(key: "a")
        #expect(model.properties.map(\.key) == ["a", "b"])
        model.renameProperty("a", to: "b")
        #expect(model.properties.map(\.key) == ["a", "b"])
    }

    @Test("setFolderPath normalizes state")
    func folderState() {
        let note = Note(title: "n")
        let model = NoteEditorModel(note: note, repository: nil)

        model.setFolderPath("/projects//nexus/")
        #expect(model.folderPath == "projects/nexus")

        model.setFolderPath("   ")
        #expect(model.folderPath == nil)
    }

    @Test("init reads existing properties and folderPath from the note")
    func initReads() {
        let note = Note(title: "n")
        note.properties = [NoteProperty(key: "k", value: .bool(true))]
        note.folderPath = "area"

        let model = NoteEditorModel(note: note, repository: nil)

        #expect(model.properties == [NoteProperty(key: "k", value: .bool(true))])
        #expect(model.folderPath == "area")
    }
}
