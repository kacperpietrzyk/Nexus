import Foundation
import Testing

@testable import TasksFeature

@Suite("HandcodedParser @project token")
struct HandcodedParserProjectTests {
    let parser = HandcodedParser()
    let now = Date()
    let en = Locale(identifier: "en")

    @Test("project token at end of input is captured and stripped from title")
    func projectAtEnd() async {
        let result = await parser.parse(
            "ship build @Nexus", locale: en, now: now, calendar: ParserCalendar.deterministic)
        #expect(result.title == "ship build")
        #expect(result.projectToken == "Nexus")
    }

    @Test("project token at start and middle of input")
    func projectAtStartAndMiddle() async {
        let atStart = await parser.parse(
            "@home buy bulbs", locale: en, now: now, calendar: ParserCalendar.deterministic)
        #expect(atStart.title == "buy bulbs")
        #expect(atStart.projectToken == "home")

        let atMiddle = await parser.parse(
            "fix @home the door", locale: en, now: now, calendar: ParserCalendar.deterministic)
        #expect(atMiddle.title == "fix the door")
        #expect(atMiddle.projectToken == "home")
    }

    @Test("typed case is preserved on the raw token")
    func casePreserved() async {
        let result = await parser.parse(
            "review PR @SideProject", locale: en, now: now, calendar: ParserCalendar.deterministic)
        #expect(result.projectToken == "SideProject")
    }

    @Test("first project token wins; later ones stay in the title verbatim")
    func firstProjectWins() async {
        let result = await parser.parse(
            "plan @alpha sprint @beta", locale: en, now: now, calendar: ParserCalendar.deterministic)
        #expect(result.projectToken == "alpha")
        #expect(result.title == "plan sprint @beta")
    }

    @Test("tags and project do not collide")
    func tagsAndProjectCoexist() async {
        let result = await parser.parse(
            "kickoff #work @Nexus tomorrow", locale: en, now: now, calendar: ParserCalendar.deterministic)
        #expect(result.tags == ["work"])
        #expect(result.projectToken == "Nexus")
        #expect(result.dueAt != nil)
        #expect(result.title == "kickoff")
    }

    @Test("lone @ and mid-word @ (emails) are not project tokens")
    func nonTokensStayResidual() async {
        let loneAt = await parser.parse(
            "ping @ noon", locale: en, now: now, calendar: ParserCalendar.deterministic)
        #expect(loneAt.projectToken == nil)

        let email = await parser.parse(
            "email kacper@example.com", locale: en, now: now, calendar: ParserCalendar.deterministic)
        #expect(email.projectToken == nil)
        #expect(email.title == "email kacper@example.com")
    }

    @Test("input that is only a project token keeps the raw-input title fallback (tag-quirk symmetry)")
    func loneProjectTokenTitleFallback() async {
        let result = await parser.parse(
            "@nexus", locale: en, now: now, calendar: ParserCalendar.deterministic)
        #expect(result.projectToken == "nexus")
        #expect(result.title == "@nexus")
    }

    @Test("project token works under Polish locale (sigil is locale-independent)")
    func polishLocale() async {
        let result = await parser.parse(
            "kup chleb jutro @dom", locale: Locale(identifier: "pl"), now: now, calendar: ParserCalendar.deterministic)
        #expect(result.projectToken == "dom")
        #expect(result.dueAt != nil)
        #expect(result.title == "kup chleb")
    }
}
