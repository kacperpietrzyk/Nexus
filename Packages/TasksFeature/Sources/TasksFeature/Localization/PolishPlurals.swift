public enum PolishPlurals {
    private enum TaskCountForm: Equatable {
        case singular
        case paucal
        case genitivePlural
    }

    public static func tasksForm(count: Int) -> String {
        switch taskCountForm(count) {
        case .singular:
            return "zadanie"
        case .paucal:
            return "zadania"
        case .genitivePlural:
            return "zadań"
        }
    }

    public static func countWithTasks(_ count: Int) -> String {
        "\(count) \(tasksForm(count: count))"
    }

    public static func overdueTasksPhrase(_ count: Int) -> String {
        switch taskCountForm(count) {
        case .singular, .paucal:
            return "\(count) przeterminowane \(tasksForm(count: count))"
        case .genitivePlural:
            return "\(count) przeterminowanych \(tasksForm(count: count))"
        }
    }

    public static func awaitingBlocksPhrase(_ count: Int) -> String {
        "\(countWithTasks(count)) \(blocksVerb(count: count)) inne"
    }

    public static func noDateWaitingPhrase(_ count: Int) -> String {
        "\(countWithTasks(count)) bez daty \(waitsVerb(count: count))"
    }

    private static func taskCountForm(_ count: Int) -> TaskCountForm {
        let absoluteCount = abs(count)
        let lastTwoDigits = absoluteCount % 100
        let lastDigit = absoluteCount % 10

        if absoluteCount == 1 {
            return .singular
        }

        if (2...4).contains(lastDigit), !(12...14).contains(lastTwoDigits) {
            return .paucal
        }

        return .genitivePlural
    }

    private static func blocksVerb(count: Int) -> String {
        taskCountForm(count) == .paucal ? "blokują" : "blokuje"
    }

    private static func waitsVerb(count: Int) -> String {
        taskCountForm(count) == .paucal ? "czekają" : "czeka"
    }
}
