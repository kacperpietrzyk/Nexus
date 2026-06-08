import Foundation
import Testing

@testable import NexusCore

/// `Person` model basics (People/Contacts module, spec §4.1): `kind`, the
/// `Searchable` projection, and the `title` ⇄ `displayName` bridge.
@Suite("Person model")
struct PersonTests {
    @Test("kind is fixed to .person")
    func kindIsPerson() {
        #expect(Person(displayName: "Alice").kind == .person)
    }

    @Test("searchableText concatenates displayName + aliases + company")
    func searchableText() {
        let person = Person(
            displayName: "Alice Smith",
            aliases: ["A. Smith", "Speaker_1"],
            company: "Acme"
        )
        let text = person.searchableText
        #expect(text.contains("Alice Smith"))
        #expect(text.contains("A. Smith"))
        #expect(text.contains("Speaker_1"))
        #expect(text.contains("Acme"))
    }

    @Test("searchableText omits a nil company without leaving blanks")
    func searchableTextNoCompany() {
        let person = Person(displayName: "Bob", aliases: [])
        #expect(person.searchableText == "Bob")
    }

    @Test("title bridges to displayName")
    func titleBridge() {
        let person = Person(displayName: "Carol")
        #expect(person.title == "Carol")
        person.title = "Caroline"
        #expect(person.displayName == "Caroline")
    }

    @Test("ItemKind.person has a stable raw value and display name")
    func itemKindRaw() {
        #expect(ItemKind.person.rawValue == "person")
        #expect(ItemKind.person.displayName == "Person")
    }

    @Test("LinkKind.attendee has a stable raw value")
    func linkKindRaw() {
        #expect(LinkKind.attendee.rawValue == "attendee")
    }
}
