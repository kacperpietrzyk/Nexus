import Foundation
import NexusCore

public enum ShareInputTextExtractor {
    public static func text(fromLoadedItem item: Any) -> String? {
        let text: String?
        switch item {
        case let url as URL:
            text = url.absoluteString
        case let string as String:
            text = string
        case let attributed as NSAttributedString:
            text = attributed.string
        case let data as Data:
            text = String(data: data, encoding: .utf8)
        default:
            text = nil
        }
        return trimmedNonEmpty(text)
    }

    public static func joinedText(from fragments: [String]) -> String {
        var seen = Set<String>()
        var lines: [String] = []

        for fragment in fragments {
            guard let text = trimmedNonEmpty(fragment), !seen.contains(text) else { continue }
            seen.insert(text)
            lines.append(text)
        }

        return lines.joined(separator: "\n")
    }

    private static func trimmedNonEmpty(_ text: String?) -> String? {
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

public enum ShareTaskBuilderError: Error, Equatable {
    case emptyTitle
}

public enum ShareTaskBuilder {
    @MainActor
    public static func task(from result: ParseResult) throws -> TaskItem {
        let title = result.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw ShareTaskBuilderError.emptyTitle }

        return TaskItem(
            title: title,
            dueAt: result.dueAt,
            startAt: result.startAt,
            endAt: result.endAt,
            deadlineAt: result.deadlineAt,
            priority: result.priority ?? .none,
            tags: result.tags,
            recurrenceRule: result.recurrence
        )
    }
}
