import SwiftUI

@MainActor
public struct CirclebackImportSheet: View {
    let composition: MeetingsComposition
    let bundleURL: URL
    @State private var progress: Double = 0
    @State private var result: CirclebackImportResult?
    @State private var running: Bool = false
    @State private var errorText: String?
    @Environment(\.dismiss) private var dismiss

    public init(composition: MeetingsComposition, bundleURL: URL) {
        self.composition = composition
        self.bundleURL = bundleURL
    }

    public var body: some View {
        VStack(spacing: 16) {
            Text("Importing from Circleback…").font(.headline)
            ProgressView(value: progress)
            if let result {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Imported: \(result.importedCount)")
                    Text("Skipped (duplicates / errors): \(result.skippedCount)")
                    Text("Action items created: \(result.actionItemsCreated)")
                    if result.actionItemsAlreadyDone > 0 {
                        Text("…of which already done in Circleback: \(result.actionItemsAlreadyDone)")
                            .foregroundStyle(.secondary)
                    }
                    if !result.errors.isEmpty {
                        DisclosureGroup("\(result.errors.count) error(s)") {
                            ScrollView {
                                ForEach(result.errors, id: \.self) { Text($0).font(.caption) }
                            }
                            .frame(maxHeight: 160)
                        }
                    }
                }
            } else if let errorText {
                Text(errorText).foregroundStyle(.red)
            }
            HStack {
                if running {
                    Button("Cancel") { dismiss() }.disabled(true)
                } else {
                    Button("Close") { dismiss() }.disabled(result == nil && errorText == nil)
                }
            }
        }
        .padding(20).frame(minWidth: 420, minHeight: 220)
        .task { await run() }
    }

    private func run() async {
        running = true
        defer { running = false }
        do {
            let importer = CirclebackImporter(
                meetingRepository: composition.meetingRepository,
                taskRepository: composition.taskItemRepository,
                linkRepository: composition.linkRepository
            )
            let outcome = try await importer.execute(bundleURL: bundleURL) { value in
                Task { @MainActor in progress = value }
            }
            self.result = outcome
            self.progress = 1.0
        } catch {
            errorText = error.localizedDescription
        }
    }
}
