import NexusUI
import SwiftUI

extension UUID: @retroactive Identifiable {
    public var id: UUID { self }
}

struct WatchRootView: View {
    @State private var captureSheetPresented = false
    @State private var askNexusSheetPresented = false
    @State private var notesSheetPresented = false
    @State private var meetingsSheetPresented = false
    @State private var customSnoozeTaskID: UUID?

    let actionHandler: WatchNotificationActionHandler?

    init(actionHandler: WatchNotificationActionHandler? = nil) {
        self.actionHandler = actionHandler
    }

    var body: some View {
        NavigationStack {
            WatchAgendaView(
                onCapture: { captureSheetPresented = true },
                onAskNexus: { askNexusSheetPresented = true }
            )
            .navigationTitle("Nexus")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        askNexusSheetPresented = true
                    } label: {
                        Label("Ask Nexus", systemImage: "sparkles")
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        captureSheetPresented = true
                    } label: {
                        Label("Capture", systemImage: "mic.fill")
                    }
                }

                ToolbarItem(placement: .bottomBar) {
                    Button {
                        notesSheetPresented = true
                    } label: {
                        Label("Notes", systemImage: "note.text")
                    }
                }

                ToolbarItem(placement: .bottomBar) {
                    Button {
                        meetingsSheetPresented = true
                    } label: {
                        Label("Meetings", systemImage: "person.2.wave.2")
                    }
                }
            }
            .sheet(isPresented: $captureSheetPresented) {
                WatchCaptureView()
            }
            .sheet(isPresented: $notesSheetPresented) {
                NavigationStack {
                    WatchNotesView()
                }
            }
            .sheet(isPresented: $meetingsSheetPresented) {
                NavigationStack {
                    WatchMeetingsView()
                }
            }
            .sheet(isPresented: $askNexusSheetPresented) {
                AskNexusInputView()
            }
            .sheet(item: $customSnoozeTaskID) { id in
                WatchCustomSnoozeView(
                    taskID: id,
                    onCommit: { until in
                        _Concurrency.Task { @MainActor in
                            await actionHandler?.snoozeCustom(taskID: id, until: until)
                            customSnoozeTaskID = nil
                        }
                    },
                    onCancel: { customSnoozeTaskID = nil }
                )
            }
            .onOpenURL { url in handleURL(url) }
        }
    }

    private func handleURL(_ url: URL) {
        guard url.scheme == "nexus", url.host == "task" else { return }
        let pathComponents = url.pathComponents.filter { $0 != "/" }
        guard pathComponents.count >= 2,
            let id = UUID(uuidString: pathComponents[0]),
            pathComponents[1] == "snooze"
        else { return }
        customSnoozeTaskID = id
    }
}

#Preview { WatchRootView() }
