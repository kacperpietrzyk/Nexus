public enum CommandRegistryError: Error, Equatable {
    case missingCommand(String)
    case disabledCommand(String, reason: String)
}

public actor CommandRegistry {
    public static let shared = CommandRegistry()

    private var commands: [String: any Command] = [:]

    public init() {}

    public func register(_ command: any Command) {
        commands[command.id] = command
    }

    public func unregister(id: String) {
        commands[id] = nil
    }

    public func allCommands() -> [any Command] {
        commands.values.sorted { lhs, rhs in
            lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }
    }

    public func search(_ query: String) -> [any Command] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return allCommands() }
        return allCommands().filter { command in
            let haystack = ([command.title, command.subtitle ?? ""] + command.keywords)
                .joined(separator: " ")
                .lowercased()
            return haystack.contains(trimmed)
        }
    }

    public func availability(id: String) async throws -> CommandAvailability {
        guard let command = commands[id] else {
            throw CommandRegistryError.missingCommand(id)
        }
        return await command.availability
    }

    public func availabilitySnapshot(for ids: [String]) async -> [String: CommandAvailability] {
        var snapshot: [String: CommandAvailability] = [:]
        for id in ids {
            guard let command = commands[id] else { continue }
            snapshot[id] = await command.availability
        }
        return snapshot
    }

    public func execute(id: String) async throws {
        guard let command = commands[id] else {
            throw CommandRegistryError.missingCommand(id)
        }
        let availability = await command.availability
        guard availability.isEnabled else {
            throw CommandRegistryError.disabledCommand(
                id,
                reason: availability.disabledReason ?? "Command unavailable"
            )
        }
        try await command.execute()
    }
}
