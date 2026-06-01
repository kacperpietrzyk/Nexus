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
                        .foregroundStyle(NexusColor.Status.danger)
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
                        // limeInk for contrast on lime fill.
                        .foregroundStyle(NexusColor.Accent.limeInk)
                        .frame(maxWidth: .infinity, minHeight: 38)
                }
                .buttonStyle(.borderedProminent)
                // Lime: single primary action on this surface (save captured task).
                .tint(NexusColor.Accent.lime)
                .disabled(state.input.trimmingCharacters(in: .whitespaces).isEmpty || state.phase == .sending)
            }
            .padding(.horizontal, 6)
        }
        .navigationTitle("Capture")
        .onAppear { inputFocused = true }
    }
}
