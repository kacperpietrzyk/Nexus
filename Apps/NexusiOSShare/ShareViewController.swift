import SwiftUI
import TasksFeature
import UIKit
import UniformTypeIdentifiers

@objc(ShareViewController)
final class ShareViewController: UIViewController {
    private var hostingController: UIHostingController<ShareSheetView>?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        Task { [weak self] in
            guard let self else { return }
            let result = await ShareInputExtractor.extract(from: self.extensionContext)
            await MainActor.run {
                self.presentShareSheet(input: result.text, initialError: result.errorMessage)
            }
        }
    }

    private func presentShareSheet(input: String, initialError: String?) {
        let sheet = ShareSheetView(initialText: input, initialError: initialError) { [weak self] saved in
            guard let self else { return }
            if saved {
                self.extensionContext?.completeRequest(returningItems: nil)
            } else {
                let error = NSError(
                    domain: "com.kacperpietrzyk.Nexus.NexusiOSShare",
                    code: NSUserCancelledError,
                    userInfo: [NSLocalizedDescriptionKey: "Share capture cancelled."]
                )
                self.extensionContext?.cancelRequest(withError: error)
            }
        }

        let hosting = UIHostingController(rootView: sheet)
        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        addChild(hosting)
        view.addSubview(hosting.view)
        NSLayoutConstraint.activate([
            hosting.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hosting.view.topAnchor.constraint(equalTo: view.topAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        hosting.didMove(toParent: self)
        hostingController = hosting
    }
}

private enum ShareInputExtractor {
    private static let attributedStringType = "public.attributed-string"

    private static let supportedAttachmentTypes = [
        UTType.url.identifier,
        UTType.plainText.identifier,
    ]

    struct Result {
        var text: String
        var errorMessage: String?
    }

    static func extract(from extensionContext: NSExtensionContext?) async -> Result {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem], !items.isEmpty else {
            return Result(text: "", errorMessage: "No shared content was provided.")
        }

        var fragments: [String] = []
        for item in items {
            if let string = item.attributedContentText?.string.trimmedNonEmpty {
                fragments.append(string)
            } else if let string = item.attributedTitle?.string.trimmedNonEmpty {
                fragments.append(string)
            }

            for provider in item.attachments ?? [] {
                if let fragment = await loadPreferredText(from: provider), !fragments.contains(fragment) {
                    fragments.append(fragment)
                }
            }
        }

        let text = ShareInputTextExtractor.joinedText(from: fragments)

        return Result(
            text: text,
            errorMessage: text.isEmpty ? "Nexus could not read text or URL content from this share." : nil
        )
    }

    private static func loadPreferredText(from provider: NSItemProvider) async -> String? {
        for identifier in supportedAttachmentTypes where provider.hasItemConformingToTypeIdentifier(identifier) {
            if let text = await provider.loadText(forTypeIdentifier: identifier) {
                return text
            }
        }

        if provider.hasItemConformingToTypeIdentifier(attributedStringType) {
            return await provider.loadText(forTypeIdentifier: attributedStringType)
        }

        return nil
    }
}

extension NSItemProvider {
    fileprivate func loadText(forTypeIdentifier typeIdentifier: String) async -> String? {
        await withCheckedContinuation { continuation in
            loadItem(forTypeIdentifier: typeIdentifier, options: nil) { item, _ in
                continuation.resume(returning: item.flatMap(ShareInputTextExtractor.text(fromLoadedItem:)))
            }
        }
    }
}

extension String {
    fileprivate var trimmedNonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
