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
                    .font(NexusType.h3)
                    .foregroundStyle(NexusColor.Text.primary)
                    .lineLimit(1)

                Text("Dictate briefly. iPhone will parse the date and project.")
                    .font(NexusType.meta)
                    .foregroundStyle(NexusColor.Text.tertiary)
                    .lineLimit(2)

                TextField("...", text: $state.input, axis: .vertical)
                    .font(NexusType.body)
                    .lineLimit(4, reservesSpace: true)
                    .focused($inputFocused)
                    .padding(10)
                    .background(
                        NexusColor.Background.control,
                        in: RoundedRectangle(cornerRadius: NexusRadius.r3, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: NexusRadius.r3, style: .continuous)
                            .strokeBorder(NexusColor.Line.regular, lineWidth: 1)
                    )

                if case .error(let message) = state.phase {
                    Text(message)
                        .font(NexusType.meta)
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
                        .font(NexusType.h3)
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
