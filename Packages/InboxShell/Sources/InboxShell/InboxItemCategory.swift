enum InboxItemCategory: Hashable {
    case people
    case tasks
    case digests
    case mentions
}

extension InboxItem {
    var category: InboxItemCategory {
        if sourceID.hasPrefix("tasks.") {
            return .tasks
        }
        let searchable = ([sourceID, title, body ?? ""] + tags).joined(separator: " ").lowercased()
        if searchable.contains("@") || searchable.contains("mention") || searchable.contains("linear") {
            return .mentions
        }
        if searchable.contains("digest") || searchable.contains("github") || searchable.contains("calendar") {
            return .digests
        }
        if searchable.contains("task") {
            return .tasks
        }
        return .people
    }
}
