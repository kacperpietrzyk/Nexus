import CoreGraphics
import NexusCore

/// Semantic vertical rhythm for the document editor: the top gap before a block,
/// given its kind and the previous block's kind. Pure — unit-tested; the macOS
/// `LazyVStack` applies it as `.padding(.top, …)`.
enum BlockRhythm {
    static func spacingBefore(_ kind: BlockKind, previous: BlockKind?) -> CGFloat {
        guard let previous else { return 0 }
        if case .heading = kind { return 24 }
        if sameListKind(kind, previous) { return 2 }
        if isParagraph(kind), isParagraph(previous) { return 8 }
        return 12
    }

    private static func isParagraph(_ kind: BlockKind) -> Bool {
        if case .paragraph = kind { return true }
        return false
    }

    private static func sameListKind(_ a: BlockKind, _ b: BlockKind) -> Bool {
        switch (a, b) {
        case (.bulleted, .bulleted), (.numbered, .numbered), (.todo, .todo): return true
        default: return false
        }
    }
}
