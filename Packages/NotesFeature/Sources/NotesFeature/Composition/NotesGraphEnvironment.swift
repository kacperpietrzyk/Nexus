import Foundation
import NexusCore
import SwiftUI

/// Host-injected titles for graph node kinds whose models live outside
/// NexusCore. The app composition root resolves them; NotesFeature consumes.
public struct NotesGraphExternalTitlesProvider: Sendable {
    private let provide: @MainActor @Sendable () -> [ItemKind: [UUID: String]]

    public init(_ provide: @escaping @MainActor @Sendable () -> [ItemKind: [UUID: String]]) {
        self.provide = provide
    }

    @MainActor
    public func callAsFunction() -> [ItemKind: [UUID: String]] {
        provide()
    }
}

private struct NotesGraphExternalTitlesKey: EnvironmentKey {
    static let defaultValue: NotesGraphExternalTitlesProvider? = nil
}

extension EnvironmentValues {
    /// Injected by app composition roots. nil means externally owned node kinds
    /// resolve to nothing and are surfaced through the graph's unresolved count.
    public var notesGraphExternalTitles: NotesGraphExternalTitlesProvider? {
        get { self[NotesGraphExternalTitlesKey.self] }
        set { self[NotesGraphExternalTitlesKey.self] = newValue }
    }
}
