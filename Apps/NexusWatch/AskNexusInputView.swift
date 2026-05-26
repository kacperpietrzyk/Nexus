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
                Text("Zapytaj Nexusa")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(NexusColor.Text.primary)
                    .lineLimit(1)

                Text("Krótka komenda albo pytanie do iPhone.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(NexusColor.Text.tertiary)
                    .lineLimit(2)

                TextField("Ask Nexus", text: $text, axis: .vertical)
                    .font(.system(size: 16))
                    .lineLimit(4, reservesSpace: true)
                    .focused($inputFocused)
                    .padding(10)
                    .background(NexusColor.Background.control, in: RoundedRectangle(cornerRadius: 12))

                if let resultMessage {
                    Text(resultMessage.message)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(resultMessage.color)
                        .lineLimit(3)
                }

                Button {
                    _Concurrency.Task { await submit() }
                } label: {
                    Label(buttonTitle, systemImage: buttonSystemImage)
                        .font(.system(size: 16, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: 38)
                }
                .buttonStyle(.borderedProminent)
                // §2 value-identical zero-pixel rename: Accent.solid and
                // Text.primary are both 0xF2F2F4 (5.1d `.tint` precedent —
                // re-point the tint value, the `.tint` modifier itself is
                // frozen watchOS chrome).
                .tint(NexusColor.Text.primary)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || phase == .sending)
            }
            .padding(.horizontal, 6)
        }
        .navigationTitle("Ask Nexus")
        .onAppear { inputFocused = true }
    }

    private var buttonTitle: String {
        phase == .sending ? "Wysyłam" : "Wyślij"
    }

    private var buttonSystemImage: String {
        phase == .sending ? "hourglass" : "paperplane.fill"
    }

    private var resultMessage: (message: String, color: Color)? {
        switch phase {
        case .idle, .sending:
            return nil
        case .sent(let message):
            // §2 value-identical zero-pixel rename: Semantic.positive and
            // Text.secondary are both 0xC7C8CE.
            return (message, NexusColor.Text.secondary)
        case .failed(let message):
            // §2 value-identical zero-pixel rename: Semantic.negative and
            // Text.primary are both 0xF2F2F4 (canonical §5 error-row anchor).
            return (message, NexusColor.Text.primary)
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
