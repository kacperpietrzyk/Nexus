import Foundation
import SwiftUI

public struct MeetingsStorageUsageView: View {
    public struct Row: Identifiable, Equatable {
        public let id: UUID
        public let title: String
        public let bytes: Int
    }

    private let composition: MeetingsComposition
    @State private var rows: [Row] = []
    @State private var confirmingDeleteAll = false
    @State private var errorMessage: String?

    public init(composition: MeetingsComposition) {
        self.composition = composition
    }

    public var body: some View {
        List {
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            ForEach(rows) { row in
                HStack {
                    Text(row.title)
                    Spacer()
                    Text(Self.formatBytes(row.bytes))
                        .foregroundStyle(.secondary)
                }
            }

            Button("Delete all audio (keep transcripts)", role: .destructive) {
                confirmingDeleteAll = true
            }
            .disabled(rows.isEmpty)
        }
        .navigationTitle("Storage usage")
        .confirmationDialog(
            "Delete all audio?",
            isPresented: $confirmingDeleteAll,
            titleVisibility: .visible
        ) {
            Button("Delete all audio", role: .destructive) {
                deleteAll()
            }
        } message: {
            Text("Transcripts and summaries will be kept.")
        }
        .onAppear {
            reload()
        }
    }

    private func reload() {
        errorMessage = nil
        let meetings = (try? composition.meetingRepository.allChronological()) ?? []
        rows = meetings.compactMap { meeting in
            guard
                let storage = try? composition.audioStorageRepository.find(meetingID: meeting.id),
                storage.hasAudio
            else {
                return nil
            }

            return Row(id: meeting.id, title: meeting.title, bytes: storage.totalBytes)
        }
    }

    private func deleteAll() {
        var failures: [String] = []

        for meeting in (try? composition.meetingRepository.allChronological()) ?? [] {
            guard
                let storage = try? composition.audioStorageRepository.find(meetingID: meeting.id),
                storage.hasAudio
            else {
                continue
            }

            if FileManager.default.fileExists(atPath: storage.folderURL.path) {
                do {
                    try FileManager.default.removeItem(at: storage.folderURL)
                } catch {
                    failures.append("\(meeting.title): \(error.localizedDescription)")
                    continue
                }
            }

            do {
                try composition.audioStorageRepository.markPruned(storage)
            } catch {
                failures.append("\(meeting.title): \(error.localizedDescription)")
            }
        }

        reload()
        if !failures.isEmpty {
            errorMessage = "Some audio could not be deleted. \(failures.joined(separator: " "))"
        }
    }

    private static func formatBytes(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}
