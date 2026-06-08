import NexusCore
import Testing

@testable import PeopleFeature

@Suite("PersonProfileFields")
struct PersonProfileFieldsTests {
    @Test("Empty optional fields are omitted; only present fields show")
    func omitsEmptyFields() {
        let person = Person(displayName: "Alice", email: "alice@example.com")
        let fields = PersonProfileFields.fields(for: person)
        #expect(fields.map(\.kind) == [.email])
        #expect(fields.first?.value == "alice@example.com")
    }

    @Test("Whitespace-only fields are treated as empty")
    func whitespaceIsEmpty() {
        let person = Person(displayName: "Bob", email: "   ", phone: "\n")
        #expect(PersonProfileFields.fields(for: person).isEmpty)
    }

    @Test("Fields are returned in the fixed order email, phone, company, aliases, note")
    func fixedOrder() {
        let person = Person(
            displayName: "Carol",
            aliases: ["C. Smith", "Caz"],
            email: "carol@example.com",
            phone: "+1 555 0101",
            company: "Acme",
            note: "Met at WWDC"
        )
        let order = PersonProfileFields.fields(for: person).map(\.kind)
        #expect(order == [.email, .phone, .company, .aliases, .note])
    }

    @Test("displayName is the header, never a field row")
    func displayNameNotAField() {
        let person = Person(displayName: "Dave")
        #expect(PersonProfileFields.fields(for: person).isEmpty)
    }

    @Test("Aliases join with comma; empty aliases dropped")
    func aliasesJoin() {
        let person = Person(displayName: "Eve", aliases: ["Eva", "", "  E  "])
        let aliasField = PersonProfileFields.fields(for: person).first { $0.kind == .aliases }
        #expect(aliasField?.value == "Eva, E")
    }
}
