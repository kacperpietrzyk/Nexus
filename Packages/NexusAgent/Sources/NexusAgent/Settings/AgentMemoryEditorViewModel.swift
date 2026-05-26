import Combine
import Foundation

@MainActor
public final class AgentMemoryEditorViewModel: ObservableObject {
    @Published public var scope: String = "global"
    @Published public private(set) var entries: [AgentMemoryEntry] = []

    private let store: AgentMemoryStore

    public init(store: AgentMemoryStore) {
        self.store = store
        reload()
    }

    public func reload() {
        do {
            entries = try store.list(matching: scopeFilter)
        } catch {
            entries = []
        }
    }

    public func delete(id: UUID) {
        do {
            try store.softDelete(id: id)
            reload()
        } catch {
            entries = []
        }
    }

    private var scopeFilter: AgentMemoryScopeFilter {
        switch scope {
        case "global":
            .global
        case "project":
            .project
        case "tag":
            .tag
        default:
            .exact(scope)
        }
    }
}
