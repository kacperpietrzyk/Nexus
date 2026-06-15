#if os(macOS)
import NexusUI
import SwiftUI

/// macOS Agent surface: a persistent thread rail fronting the chat so past
/// conversations are selectable/archivable. iOS ships the equivalent via a
/// `NavigationSplitView`, but nesting another split view inside the app's detail
/// column fights the outer sidebar on macOS, so this uses a plain leading
/// `HStack` panel. The same upstream `viewModel` drives the rail, the top
/// "+ New" control, the composer, and the chat, so selection/create/archive
/// stay in sync across all of them.
public struct AgentThreadRail: View {
    @ObservedObject private var viewModel: AgentChatViewModel

    public init(viewModel: AgentChatViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        HStack(spacing: 0) {
            ThreadListView(
                threads: viewModel.threads,
                currentThreadID: viewModel.currentThreadID,
                onSelect: viewModel.selectThread(id:),
                onArchive: viewModel.archive(threadID:)
            )
            .frame(width: 248)

            Rectangle()
                .fill(DS.ColorToken.strokeHairline)
                .frame(width: 1)

            AgentChatView(viewModel: viewModel)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
#endif
