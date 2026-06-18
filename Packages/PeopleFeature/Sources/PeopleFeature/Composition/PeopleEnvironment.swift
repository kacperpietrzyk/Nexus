import NexusCore
import SwiftUI

private struct PersonRepositoryEnvironmentKey: EnvironmentKey {
    static let defaultValue: PersonRepository? = nil
}

extension EnvironmentValues {
    /// Injected by app composition roots. `@MainActor`-bound because
    /// `PersonRepository` is `@MainActor`. People surfaces access via
    /// `@Environment(\.personRepository)`. Mirrors `\.noteRepository`.
    public var personRepository: PersonRepository? {
        get { self[PersonRepositoryEnvironmentKey.self] }
        set { self[PersonRepositoryEnvironmentKey.self] = newValue }
    }
}

/// Resolves a meeting graph endpoint (`UUID`) into a displayable `Linkable` row for
/// the person profile's meeting history (spec §6 aggregate).
///
/// PeopleFeature depends ONLY on NexusCore + NexusUI and cannot import
/// `NexusMeetings` (the `Meeting` `@Model` lives there) — feature modules never
/// import each other (CLAUDE.md). Tasks/notes are resolved directly (`TaskItem` /
/// `Note` are in NexusCore), but meetings need the host (Mac/iOS app, which imports
/// NexusMeetings) to inject a resolver. nil ⇒ meetings are listed by id only / the
/// host did not wire meeting resolution.
public struct PersonMeetingResolver: Sendable {
    public let resolve: @MainActor @Sendable (UUID) -> (any Linkable)?

    public init(resolve: @escaping @MainActor @Sendable (UUID) -> (any Linkable)?) {
        self.resolve = resolve
    }
}

private struct PersonMeetingResolverEnvironmentKey: EnvironmentKey {
    static let defaultValue: PersonMeetingResolver? = nil
}

extension EnvironmentValues {
    /// Host-supplied bridge from a meeting `UUID` to a displayable row. See
    /// `PersonMeetingResolver`. nil on hosts that do not import Meetings.
    public var personMeetingResolver: PersonMeetingResolver? {
        get { self[PersonMeetingResolverEnvironmentKey.self] }
        set { self[PersonMeetingResolverEnvironmentKey.self] = newValue }
    }
}

// MARK: - New linked task callback

private struct OnCreateLinkedTaskEnvironmentKey: EnvironmentKey {
    static let defaultValue: (@MainActor (Person) -> Void)? = nil
}

extension EnvironmentValues {
    /// Host-injected closure that creates a new task linked (via `.mentions`) to
    /// the given `Person`. PeopleFeature cannot import TasksFeature or
    /// TaskItemRepository (CLAUDE.md isolation), so the actual task creation
    /// belongs to the app composition root which imports both. When nil the
    /// "New Linked Task" context-menu item is hidden.
    public var onCreateLinkedTask: (@MainActor (Person) -> Void)? {
        get { self[OnCreateLinkedTaskEnvironmentKey.self] }
        set { self[OnCreateLinkedTaskEnvironmentKey.self] = newValue }
    }
}
