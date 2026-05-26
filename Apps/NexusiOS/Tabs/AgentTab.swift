import NexusAgent
import NexusUI
import SwiftUI

struct AgentTab: View {
    let viewModel: AgentChatViewModel?

    var body: some View {
        if let viewModel {
            AgentTabContent(viewModel: viewModel)
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        NavigationStack {
            ContentUnavailableView(
                "Agent unavailable",
                systemImage: "sparkles",
                description: Text("Agent runtime is not connected yet.")
            )
            .foregroundStyle(NexusColor.Text.secondary)
            .navigationTitle("Agent")
            .toolbarBackground(.thinMaterial, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
    }
}

private struct AgentTabContent: View {
    @ObservedObject var viewModel: AgentChatViewModel

    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        agentContent
    }

    @ViewBuilder
    private var agentContent: some View {
        if sizeClass == .compact {
            compactContent
        } else {
            regularContent
        }
    }

    private var compactContent: some View {
        NavigationStack {
            AgentChatView(viewModel: viewModel)
                .navigationTitle("Agent")
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(.thinMaterial, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
        }
    }

    private var regularContent: some View {
        NavigationSplitView {
            ThreadListView(
                threads: viewModel.threads,
                currentThreadID: viewModel.currentThreadID,
                onSelect: viewModel.selectThread(id:),
                onArchive: viewModel.archive(threadID:)
            )
            .navigationTitle("Threads")
        } detail: {
            AgentChatView(viewModel: viewModel)
                .navigationTitle("Agent")
                .navigationBarTitleDisplayMode(.inline)
        }
        .toolbarBackground(.thinMaterial, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
    }
}
