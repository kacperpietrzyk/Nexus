import Foundation
import NexusCore

/// Resolves the display ordinal for each `.numbered` block: its 1-based position
/// within the current maximal run of consecutive `.numbered` blocks. Any
/// non-numbered block resets the counter. Pure — shared by both platforms.
enum NumberedOrdinals {
    static func ordinals(for blocks: [Block]) -> [UUID: Int] {
        var result: [UUID: Int] = [:]
        var counter = 0
        for block in blocks {
            if case .numbered = block.kind {
                counter += 1
                result[block.id] = counter
            } else {
                counter = 0
            }
        }
        return result
    }
}
