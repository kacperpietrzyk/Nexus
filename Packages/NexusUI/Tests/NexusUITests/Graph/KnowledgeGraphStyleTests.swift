import NexusCore
import SwiftUI
import Testing
@testable import NexusUI

@Suite struct KnowledgeGraphStyleTests {
    @Test func stylePassesThroughHostMapping() {
        let style = KnowledgeGraphStyle(
            color: { $0 == .task ? .blue : .gray },
            icon: { $0 == .note ? "doc.text" : "circle" })
        #expect(style.color(.task) == .blue)
        #expect(style.icon(.note) == "doc.text")
    }
}
