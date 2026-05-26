import NexusUI
import SwiftUI

struct WatchCaptureView: View {
    @State private var state = WatchCaptureState()
    @FocusState private var inputFocused: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("New task")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(NexusColor.Text.primary)
                    .lineLimit(1)

                Text("Dictate briefly. iPhone will parse the date and project.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(NexusColor.Text.tertiary)
                    .lineLimit(2)

                TextField("...", text: $state.input, axis: .vertical)
                    .font(.system(size: 16))
                    .lineLimit(4, reservesSpace: true)
                    .focused($inputFocused)
                    .padding(10)
                    .background(NexusColor.Background.control, in: RoundedRectangle(cornerRadius: 12))

                if case .error(let message) = state.phase {
                    Text(message)
                        .font(.system(size: 12, weight: .medium))
                        // §2 value-identical zero-pixel rename: Semantic.negative
                        // and Text.primary are both 0xF2F2F4 (canonical §5
                        // error-row anchor).
                        .foregroundStyle(NexusColor.Text.primary)
                }

                Button {
                    _Concurrency.Task {
                        await state.send()
                        if case .sent = state.phase {
                            dismiss()
                        }
                    }
                } label: {
                    Label("Save", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: 38)
                }
                .buttonStyle(.borderedProminent)
                // §2 value-identical zero-pixel rename: Semantic.positive and
                // Text.secondary are both 0xC7C8CE (5.1d `.tint` precedent —
                // re-point the tint value, the `.tint` modifier itself is
                // frozen watchOS chrome).
                .tint(NexusColor.Text.secondary)
                .disabled(state.input.trimmingCharacters(in: .whitespaces).isEmpty || state.phase == .sending)
            }
            .padding(.horizontal, 6)
        }
        .navigationTitle("Capture")
        .onAppear { inputFocused = true }
    }
}
