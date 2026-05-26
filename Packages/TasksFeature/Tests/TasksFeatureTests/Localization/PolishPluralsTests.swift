import Testing

@testable import TasksFeature

@Suite("PolishPlurals")
struct PolishPluralsTests {
    @Test("returns singular form for one task")
    func singularForm() {
        #expect(PolishPlurals.tasksForm(count: 1) == "zadanie")
    }

    @Test("returns plural paucal form for 2, 3, and 4")
    func paucalForms() {
        #expect(PolishPlurals.tasksForm(count: 2) == "zadania")
        #expect(PolishPlurals.tasksForm(count: 3) == "zadania")
        #expect(PolishPlurals.tasksForm(count: 4) == "zadania")
    }

    @Test("returns genitive plural for zero, five, six, eleven, and hundred")
    func genitivePluralForms() {
        #expect(PolishPlurals.tasksForm(count: 0) == "zadań")
        #expect(PolishPlurals.tasksForm(count: 5) == "zadań")
        #expect(PolishPlurals.tasksForm(count: 6) == "zadań")
        #expect(PolishPlurals.tasksForm(count: 11) == "zadań")
        #expect(PolishPlurals.tasksForm(count: 100) == "zadań")
    }

    @Test("returns genitive plural for teen quirk values")
    func teenQuirkForms() {
        #expect(PolishPlurals.tasksForm(count: 12) == "zadań")
        #expect(PolishPlurals.tasksForm(count: 13) == "zadań")
        #expect(PolishPlurals.tasksForm(count: 14) == "zadań")
    }

    @Test("returns recurring paucal forms for 22, 23, and 24")
    func recurringPaucalForms() {
        #expect(PolishPlurals.tasksForm(count: 22) == "zadania")
        #expect(PolishPlurals.tasksForm(count: 23) == "zadania")
        #expect(PolishPlurals.tasksForm(count: 24) == "zadania")
    }

    @Test("returns recurring genitive plural forms")
    func recurringGenitivePluralForms() {
        #expect(PolishPlurals.tasksForm(count: 25) == "zadań")
        #expect(PolishPlurals.tasksForm(count: 100) == "zadań")
        #expect(PolishPlurals.tasksForm(count: 101) == "zadań")
    }

    @Test("formats count with matching task form")
    func countWithTasksFormatsCountAndForm() {
        #expect(PolishPlurals.countWithTasks(1) == "1 zadanie")
        #expect(PolishPlurals.countWithTasks(3) == "3 zadania")
        #expect(PolishPlurals.countWithTasks(5) == "5 zadań")
        #expect(PolishPlurals.countWithTasks(13) == "13 zadań")
        #expect(PolishPlurals.countWithTasks(22) == "22 zadania")
    }

    @Test("formats overdue task phrase with count-aware adjective")
    func overdueTaskPhrase() {
        #expect(PolishPlurals.overdueTasksPhrase(1) == "1 przeterminowane zadanie")
        #expect(PolishPlurals.overdueTasksPhrase(2) == "2 przeterminowane zadania")
        #expect(PolishPlurals.overdueTasksPhrase(5) == "5 przeterminowanych zadań")
    }

    @Test("formats awaiting block phrase with count-aware verb")
    func awaitingBlocksPhrase() {
        #expect(PolishPlurals.awaitingBlocksPhrase(1) == "1 zadanie blokuje inne")
        #expect(PolishPlurals.awaitingBlocksPhrase(2) == "2 zadania blokują inne")
        #expect(PolishPlurals.awaitingBlocksPhrase(5) == "5 zadań blokuje inne")
    }

    @Test("formats no-date waiting phrase with count-aware verb")
    func noDateWaitingPhrase() {
        #expect(PolishPlurals.noDateWaitingPhrase(1) == "1 zadanie bez daty czeka")
        #expect(PolishPlurals.noDateWaitingPhrase(2) == "2 zadania bez daty czekają")
        #expect(PolishPlurals.noDateWaitingPhrase(5) == "5 zadań bez daty czeka")
    }
}
