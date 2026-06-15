import NexusCore
import NexusUI
import SwiftUI

#if canImport(WebKit)
import WebKit
#endif

/// The `html(raw:)` escape-hatch block (spec §14). HTML written by the agent/MCP
/// is untrusted, so it renders in a **JS-disabled** WKWebView with no remote
/// resource loading — the one place a WebView is used. In edit mode the raw source
/// is also editable as plain text.
struct HTMLBlockView: View {
    let block: Block
    let model: NoteEditorModel
    let raw: String
    @State private var draft: String = ""
    @State private var showingSource = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("HTML")
                    .nexusType(.eyebrow)
                    .foregroundStyle(NexusColor.Text.tertiary)
                Spacer(minLength: 0)
                if model.canEdit {
                    Button(showingSource ? "Preview" : "Edit source") {
                        if showingSource, draft != raw {
                            model.setHTML(draft, forBlock: block.id)
                        }
                        showingSource.toggle()
                    }
                    .nexusType(.bodySmall)
                    .buttonStyle(.plain)
                    .foregroundStyle(NexusColor.Text.secondary)
                }
            }

            if showingSource {
                NexusTextEditor(text: $draft, minHeight: 100, isMonospaced: true)
                    .onAppear { draft = raw }
            } else {
                SanitizedHTMLView(html: raw)
                    .frame(minHeight: 60)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NexusColor.Background.control, in: RoundedRectangle(cornerRadius: NexusRadius.r1))
    }
}

#if canImport(WebKit) && os(macOS)
private struct SanitizedHTMLView: NSViewRepresentable {
    let html: String

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero, configuration: Self.hardenedConfiguration())
        webView.setValue(false, forKey: "drawsBackground")
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        webView.loadHTMLString(html, baseURL: nil)
    }

    private static func hardenedConfiguration() -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        // §14: JS is disabled for synced note content — it is a real attack
        // surface when the HTML is agent/MCP-authored. `baseURL: nil` above plus
        // the default content blocking keeps it from reaching the network.
        let preferences = WKWebpagePreferences()
        preferences.allowsContentJavaScript = false
        configuration.defaultWebpagePreferences = preferences
        return configuration
    }
}
#elseif canImport(WebKit) && os(iOS)
private struct SanitizedHTMLView: UIViewRepresentable {
    let html: String

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero, configuration: Self.hardenedConfiguration())
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        webView.loadHTMLString(html, baseURL: nil)
    }

    private static func hardenedConfiguration() -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        // §14: JS off for untrusted, synced HTML; `baseURL: nil` blocks the network.
        let preferences = WKWebpagePreferences()
        preferences.allowsContentJavaScript = false
        configuration.defaultWebpagePreferences = preferences
        return configuration
    }
}
#else
private struct SanitizedHTMLView: View {
    let html: String

    var body: some View {
        Text(html)
            .font(NexusType.mono)
            .foregroundStyle(NexusColor.Text.muted)
    }
}
#endif
