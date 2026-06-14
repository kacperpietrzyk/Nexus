import SwiftUI

/// Observable model backing the confirm card. Plain inputs only — no domain types.
@MainActor
@Observable
public final class ProposalConfirmCardModel {
    public let title: String
    public let rationale: String
    public let previews: [String]
    public private(set) var isApplying = false
    private let onAccept: () async -> Void
    private let onReject: () -> Void

    public init(
        title: String,
        rationale: String,
        previews: [String],
        onAccept: @escaping () async -> Void,
        onReject: @escaping () -> Void
    ) {
        self.title = title
        self.rationale = rationale
        self.previews = previews
        self.onAccept = onAccept
        self.onReject = onReject
    }

    public func accept() async {
        isApplying = true
        await onAccept()
        isApplying = false
    }

    public func reject() {
        onReject()
    }
}

/// Presentation-only confirm card. Each feature maps its own Proposal → these inputs.
public struct ProposalConfirmCard: View {
    @State private var model: ProposalConfirmCardModel

    public init(model: ProposalConfirmCardModel) {
        self._model = State(initialValue: model)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(model.title).font(.headline)
            if !model.rationale.isEmpty {
                Text(model.rationale).font(.caption).foregroundStyle(.secondary)
            }
            ForEach(Array(model.previews.enumerated()), id: \.offset) { _, line in
                Text(line).font(.callout)
            }
            HStack {
                Button("Discard") { model.reject() }
                Button("Apply") { Task { await model.accept() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.isApplying)
            }
        }
        .padding()
    }
}
