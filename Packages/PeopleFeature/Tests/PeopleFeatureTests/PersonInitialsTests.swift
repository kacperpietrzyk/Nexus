import Testing

@testable import PeopleFeature

@Suite("PersonInitials")
struct PersonInitialsTests {
    @Test("Two-word names take both first letters")
    func twoWordName() {
        #expect(PersonInitials.initials(from: "Maya Chen") == "MC")
    }

    @Test("Single names take one letter")
    func singleName() {
        #expect(PersonInitials.initials(from: "Maya") == "M")
    }

    @Test("Empty and whitespace-only names fall back to ?")
    func emptyName() {
        #expect(PersonInitials.initials(from: "") == "?")
        #expect(PersonInitials.initials(from: "   ") == "?")
    }

    @Test("Names with more than two parts use only the first two")
    func extraParts() {
        #expect(PersonInitials.initials(from: "Anna Maria Kowalska") == "AM")
    }

    @Test("Initials are uppercased")
    func uppercased() {
        #expect(PersonInitials.initials(from: "maya chen") == "MC")
    }
}
