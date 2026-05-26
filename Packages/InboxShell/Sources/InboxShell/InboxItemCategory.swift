enum InboxItemCategory: Hashable {
    case people
    case tasks
    case digests
    case mentions
}

extension InboxItem {
    var category: InboxItemCategory {
        let searchable = ([sourceID, title, body ?? ""] + tags).joined(separator: " ").lowercased()
        if searchable.contains("@") || searchable.contains("mention") || searchable.contains("linear") {
            return .mentions
        }
        if searchable.contains("digest") || searchable.contains("github") || searchable.contains("calendar") {
            return .digests
        }
        if searchable.contains("task") || sourceID.hasPrefix("tasks.") {
            return .tasks
        }
        return .people
    }
}
