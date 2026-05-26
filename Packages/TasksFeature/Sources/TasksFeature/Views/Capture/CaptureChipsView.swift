import NexusCore
import NexusUI
import SwiftUI

/// Renders parsed metadata as chips beneath the capture text field.
/// Pure presentation — `result` is the only input.
public struct CaptureChipsView: View {

    public let result: ParseResult?
    public let now: Date

    public init(result: ParseResult?, now: Date = .now) {
        self.result = result
        self.now = now
    }

    public var body: some View {
        if let result {
            HStack(spacing: 6) {
                ForEach(Array(CaptureChipModel.chips(for: result, now: now).enumerated()), id: \.offset) { _, entry in
                    CaptureChipModel.chip(icon: entry.icon, label: entry.label)
                }
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Color.clear.frame(height: 22)
        }
    }
}
