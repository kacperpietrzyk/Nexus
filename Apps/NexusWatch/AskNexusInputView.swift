import NexusUI
import SwiftUI

struct AskNexusInputView: View {
    private enum Phase: Equatable {
        case idle
        case sending
        case sent(String)
        case failed(String)
    }

    @State private var text = ""
    @State private var phase: Phase = .idle
    @FocusState private var inputFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Ask Nexus")
                    .font(NexusType.h3)
                    .foregroundStyle(NexusColor.Text.primary)
                    .lineLimit(1)

                Text("A short command or question for iPhone.")
                    .font(NexusType.meta)
                    .foregroundStyle(NexusColor.Text.tertiary)
                    .lineLimit(2)

                TextField("Ask Nexus", text: $text, axis: .vertical)
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

                if let resultMessage {
                    Text(resultMessage.message)
                        .font(NexusType.meta)
                        .foregroundStyle(resultMessage.color)
                        .lineLimit(3)
                }

                Button {
                    _Concurrency.Task { await submit() }
                } label: {
                    Label(buttonTitle, systemImage: buttonSystemImage)
                        .font(NexusType.h3)
                        // limeInk for contrast on lime fill.
                        .foregroundStyle(NexusColor.Accent.limeInk)
                        .frame(maxWidth: .infinity, minHeight: 38)
                }
                .buttonStyle(.borderedProminent)
                // Lime: single primary action on this surface (send to iPhone).
                .tint(NexusColor.Accent.lime)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || phase == .sending)
            }
            .padding(.horizontal, 6)
        }
        .navigationTitle("Ask Nexus")
        .onAppear { inputFocused = true }
    }

    private var buttonTitle: String {
        phase == .sending ? "Sending" : "Send"
    }

    private var buttonSystemImage: String {
        phase == .sending ? "hourglass" : "paperplane.fill"
    }

    private var resultMessage: (message: String, color: Color)? {
        switch phase {
        case .idle, .sending:
            return nil
        case .sent(let message):
            return (message, NexusColor.Status.success)
        case .failed(let message):
            return (message, NexusColor.Status.danger)
        }
    }

    @MainActor
    private func submit() async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        phase = .sending
        do {
            let reply = try await WatchPhoneBridge.shared.sendAskNexus(prompt: trimmed)
            text = ""
            phase = .sent(reply)
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }
}

#Preview { AskNexusInputView() }
