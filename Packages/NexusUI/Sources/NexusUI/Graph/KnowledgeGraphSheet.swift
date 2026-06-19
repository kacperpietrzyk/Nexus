#if os(macOS) || os(iOS)
import SwiftUI
import NexusCore

extension View {
    /// Presents `KnowledgeGraphView` on a large sheet (~80% of the window) with a
    /// header, depth toggle, reset, and close controls. `snapshotForDepth` is called
    /// with the current depth (1...maxDepth) to (re)derive the graph.
    public func knowledgeGraphSheet(  // swiftlint:disable:this function_parameter_count
        isPresented: Binding<Bool>,
        rootID: GraphNodeID?,
        style: KnowledgeGraphStyle,
        header: String,
        initialDepth: Int = 1,
        maxDepth: Int = 2,
        snapshotForDepth: @escaping (Int) -> GraphSnapshot,
        onSelect: @escaping (GraphNodeID) -> Void
    ) -> some View {
        sheet(isPresented: isPresented) {
            KnowledgeGraphSheetContent(
                isPresented: isPresented,
                rootID: rootID,
                style: style,
                header: header,
                depth: initialDepth,
                maxDepth: maxDepth,
                snapshotForDepth: snapshotForDepth,
                onSelect: onSelect
            )
        }
    }
}

private struct KnowledgeGraphSheetContent: View {
    @Binding var isPresented: Bool
    let rootID: GraphNodeID?
    let style: KnowledgeGraphStyle
    let header: String
    @State var depth: Int
    let maxDepth: Int
    let snapshotForDepth: (Int) -> GraphSnapshot
    let onSelect: (GraphNodeID) -> Void
    @State private var redrawToken = 0

    var body: some View {
        let snapshot = snapshotForDepth(depth)
        return VStack(spacing: 0) {
            HStack(spacing: DS.Space.m) {
                // DS.FontToken.title3 does not exist; DS.FontToken.title (17pt semibold) is
                // the nearest title token and is used here instead.
                Text(header)
                    .font(DS.FontToken.title.weight(.semibold))
                if snapshot.isTruncated {
                    Text("Showing \(snapshot.nodes.count) of \(snapshot.totalNodeCount)")
                        .font(DS.FontToken.metadata)
                        .foregroundStyle(DS.ColorToken.textTertiary)
                }
                Spacer()
                if maxDepth > 1 {
                    Picker("Depth", selection: $depth) {
                        ForEach(1...maxDepth, id: \.self) { hop in
                            Text("\(hop)-hop").tag(hop)
                        }
                    }
                    .pickerStyle(.segmented)
                    .fixedSize()
                    .onChange(of: depth) { _, _ in redrawToken += 1 }
                }
                Button {
                    redrawToken += 1
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Reset layout")
                Button {
                    isPresented = false
                } label: {
                    Image(systemName: "xmark")
                }
                .keyboardShortcut(.cancelAction)
            }
            .buttonStyle(.plain)
            .padding(DS.Space.m)
            Divider()
                .overlay(DS.ColorToken.strokeHairline)
            KnowledgeGraphView(
                snapshot: snapshot,
                rootID: rootID,
                style: style,
                onSelect: { id in
                    onSelect(id)
                    isPresented = false
                }
            )
            .id(redrawToken)  // reset / depth change re-runs onAppear layout
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 720, minHeight: 560)
        .frame(idealWidth: 1000, idealHeight: 760)
    }
}
#endif
