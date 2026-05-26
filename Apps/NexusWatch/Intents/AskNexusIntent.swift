import AppIntents
import Foundation

struct AskNexusIntent: AppIntent {
    static let title: LocalizedStringResource = "Ask Nexus"
    static let description = IntentDescription("Send a question to the Nexus Agent on the paired device.")
    static let supportedModes: IntentModes = .background

    @Parameter(title: "Question", inputOptions: .init(keyboardType: .default))
    var question: String

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .result(dialog: "You didn't dictate anything.")
        }
        let reply = try await WatchPhoneBridge.shared.sendAskNexus(prompt: trimmed)
        return .result(dialog: IntentDialog(stringLiteral: reply))
    }
}
