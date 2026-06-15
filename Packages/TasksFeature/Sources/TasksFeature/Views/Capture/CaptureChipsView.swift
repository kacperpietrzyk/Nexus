import NexusCore
import NexusUI
import SwiftUI

/// Renders parsed metadata as chips beneath the capture text field.
/// Pure presentation — `result` plus the caller-resolved project name are the
/// only inputs (resolution happens in the host, keeping this view repo-free).
public struct CaptureChipsView: View {

    public let result: ParseResult?
    public let resolvedProjectName: String?
    public let now: Date

    public init(result: ParseResult?, resolvedProjectName: String? = nil, now: Date = .now) {
        self.result = result
        self.resolvedProjectName = resolvedProjectName
        self.now = now
    }

    public var body: some View {
        if let result {
            HStack(spacing: 6) {
                ForEach(
                    Array(
                        CaptureChipModel.chips(for: result, now: now, resolvedProjectName: resolvedProjectName)
                            .enumerated()),
                    id: \.offset
                ) { _, entry in
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
