import NexusUI
import SwiftUI

public struct MeetingsPromptSettingsView: View {
    @State private var prompt = ""
    @State private var alert: PromptAlert?

    private let composition: MeetingsComposition
    private let store: MeetingsPromptStore

    public init(
        composition: MeetingsComposition,
        store: MeetingsPromptStore = .shared
    ) {
        self.composition = composition
        self.store = store
    }

    public var body: some View {
        LiquidGlassCard("Summary prompt (custom)") {
            VStack(alignment: .leading, spacing: DS.Space.l) {
                NexusTextEditor(text: $prompt, minHeight: 160)

                HStack(spacing: DS.Space.m) {
                    NexusButton(variant: .primary, size: .sm) {
                        save()
                    } label: {
                        Text("Save")
                    }

                    NexusButton(variant: .default, size: .sm) {
                        reset()
                    } label: {
                        Text("Reset to default")
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear(perform: load)
        .alert(item: $alert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    private func load() {
        prompt = store.load() ?? ""
    }

    private func save() {
        do {
            try store.save(prompt)
            alert = PromptAlert(
                title: "Prompt saved",
                message: "Nexus will use this prompt for future meeting summaries."
            )
        } catch {
            alert = PromptAlert(
                title: "Could not save prompt",
                message: error.localizedDescription
            )
        }
    }

    private func reset() {
        prompt = ""
        do {
            try store.reset()
            alert = PromptAlert(
                title: "Prompt reset",
                message: "Nexus will use the default meeting summary prompt."
            )
        } catch {
            alert = PromptAlert(
                title: "Could not reset prompt",
                message: error.localizedDescription
            )
        }
    }
}

private struct PromptAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}
