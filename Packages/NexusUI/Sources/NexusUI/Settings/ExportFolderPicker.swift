import SwiftUI
import UniformTypeIdentifiers

#if !os(watchOS)

/// Cross-platform folder picker via SwiftUI `.fileImporter`. Caller presents this view (typically
/// as `EmptyView` modifier) and toggles `isPresented` to open the picker.
public struct ExportFolderPicker: View {
    @Binding var isPresented: Bool
    public let onPicked: (URL) -> Void

    public init(isPresented: Binding<Bool>, onPicked: @escaping (URL) -> Void) {
        self._isPresented = isPresented
        self.onPicked = onPicked
    }

    public var body: some View {
        EmptyView()
            .fileImporter(
                isPresented: $isPresented,
                allowedContentTypes: [.folder],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    if let url = urls.first {
                        // Bracketed security-scoped access for sandboxed Mac builds.
                        let started = url.startAccessingSecurityScopedResource()
                        defer { if started { url.stopAccessingSecurityScopedResource() } }
                        onPicked(url)
                    }
                case .failure:
                    break
                }
            }
    }
}

#endif
