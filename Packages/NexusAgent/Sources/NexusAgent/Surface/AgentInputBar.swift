// swiftlint:disable file_length
import Foundation
import NexusUI
import SwiftUI
import UniformTypeIdentifiers

#if os(iOS) && canImport(PhotosUI)
import PhotosUI
#endif

private struct AgentFileContextPayload: Equatable {
    let sourceFilename: String
    let systemPrefix: String
}

private struct AgentFileDropDelegate: DropDelegate {
    @Binding var isTargeted: Bool

    let isDisabled: Bool
    let onDrop: ([NSItemProvider]) -> Bool

    func validateDrop(info: DropInfo) -> Bool {
        !isDisabled && info.hasItemsConforming(to: [UTType.fileURL.identifier])
    }

    func dropEntered(info _: DropInfo) {
        guard !isDisabled else { return }
        isTargeted = true
    }

    func dropExited(info _: DropInfo) {
        isTargeted = false
    }

    func performDrop(info: DropInfo) -> Bool {
        isTargeted = false
        guard !isDisabled else { return false }
        return onDrop(info.itemProviders(for: [UTType.fileURL.identifier]))
    }
}

private struct AgentImageDropDelegate: DropDelegate {
    @Binding var isTargeted: Bool

    let isDisabled: Bool
    let onDrop: ([NSItemProvider]) -> Bool

    func validateDrop(info: DropInfo) -> Bool {
        let isValid = !isDisabled && info.hasItemsConforming(to: [UTType.image.identifier])
        if !isValid {
            isTargeted = false
        }
        return isValid
    }

    func dropEntered(info _: DropInfo) {
        guard !isDisabled else {
            isTargeted = false
            return
        }
        isTargeted = true
    }

    func dropExited(info _: DropInfo) {
        isTargeted = false
    }

    func performDrop(info: DropInfo) -> Bool {
        isTargeted = false
        guard !isDisabled else { return false }
        return onDrop(info.itemProviders(for: [UTType.image.identifier]))
    }
}

private struct AgentInputBarImageButtonLabel: View {
    let isDisabled: Bool
    let foreground: Color
    let border: Color

    var body: some View {
        Image(systemName: "photo")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(isDisabled ? NexusColor.Text.tertiary : foreground)
            .frame(width: 30, height: 30)
            .background(NexusColor.Background.control, in: RoundedRectangle(cornerRadius: NexusRadius.r2))
            .overlay(
                RoundedRectangle(cornerRadius: NexusRadius.r2)
                    .strokeBorder(border, lineWidth: 1)
            )
    }
}

public struct AgentInputBar: View {
    public typealias OnSend = (String) -> Void
    public typealias OnSendWithAttachments = (String, [String], String?) async -> AgentInputSendResult
    public typealias ImageCaptureAvailability = () async -> Bool
    public typealias ImageAttachmentDeferralReasonProvider = () async -> ImageAttachmentDeferralReason?

    private let onSend: OnSendWithAttachments
    private let isThinking: Bool
    private let voiceCapture: AgentVoiceCapture?
    private let imageCaptureAvailability: ImageCaptureAvailability?
    private let imageAttachmentDeferralReasonProvider: ImageAttachmentDeferralReasonProvider?

    @State private var input = ""
    @FocusState private var isInputFocused: Bool
    @State private var voiceSession: AgentVoiceCaptureSession?
    @State private var voiceStartTask: Task<Void, Never>?
    @State private var isVoiceCaptureAvailable = false
    @State private var isVoiceStarting = false
    @State private var isVoiceTranscribing = false
    @State private var stopVoiceWhenReady = false
    @State private var isSending = false
    @State private var voiceError: String?
    @State private var attachedImages: [AgentAttachmentPayload] = []
    @State private var attachedFileContexts: [AgentFileContextPayload] = []
    @State private var isImageCaptureAvailable = false
    @State private var isImageDropTargeted = false
    @State private var isFileDropTargeted = false
    @State private var isFileImporterPresented = false
    @State private var imageAttachmentDeferralReason: ImageAttachmentDeferralReason?
    @State private var imageError: String?
    @State private var fileError: String?

    #if os(iOS) && canImport(PhotosUI)
    @State private var selectedPhotoItem: PhotosPickerItem?
    #endif

    public init(
        onSend: @escaping OnSend,
        isThinking: Bool,
        voiceCapture: AgentVoiceCapture? = nil
    ) {
        self.onSend = { text, _, _ in
            onSend(text)
            return .accepted
        }
        self.isThinking = isThinking
        self.voiceCapture = voiceCapture
        self.imageCaptureAvailability = nil
        self.imageAttachmentDeferralReasonProvider = nil
    }

    public init(
        onSendWithAttachments: @escaping OnSendWithAttachments,
        isThinking: Bool,
        voiceCapture: AgentVoiceCapture? = nil,
        imageCaptureAvailability: ImageCaptureAvailability? = nil,
        imageAttachmentDeferralReason: ImageAttachmentDeferralReasonProvider? = nil
    ) {
        self.onSend = onSendWithAttachments
        self.isThinking = isThinking
        self.voiceCapture = voiceCapture
        self.imageCaptureAvailability = imageCaptureAvailability
        self.imageAttachmentDeferralReasonProvider = imageAttachmentDeferralReason
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !attachedFileContexts.isEmpty {
                fileContextPreviewRow
            }

            if !attachedImages.isEmpty {
                attachmentPreviewRow
            }

            if let imageAttachmentDeferralReason {
                imageAttachmentDeferralBanner(reason: imageAttachmentDeferralReason)
            }

            HStack(alignment: .bottom, spacing: 10) {
                voiceButton
                imageButton

                TextField("Message Nexus…", text: $input, axis: .vertical)
                    .lineLimit(1...6)
                    .textFieldStyle(.plain)
                    .foregroundStyle(NexusColor.Text.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(NexusColor.Background.control, in: fieldShape)
                    .overlay(fieldShape.strokeBorder(NexusColor.Line.hairline, lineWidth: 1))
                    .disabled(isThinking || isSending)
                    .focused($isInputFocused)
                    .submitLabel(.send)
                    .onSubmit { Task { await send() } }

                NexusButton(
                    variant: .primary,
                    size: .md,
                    action: { Task { await send() } },
                    label: {
                        Text(isThinking || isSending ? "..." : "Send")
                    }
                )
                .disabled(!canSend)
                .opacity(canSend ? 1 : 0.56)
                .accessibilityLabel("Send message")
            }

            if isThinking {
                Text("Nexus is thinking...")
                    .font(.caption)
                    .foregroundStyle(NexusColor.Text.tertiary)
                    .accessibilityLabel("Nexus is thinking")
            } else if isVoiceTranscribing {
                Text("Transcribing voice...")
                    .font(.caption)
                    .foregroundStyle(NexusColor.Text.tertiary)
                    .accessibilityLabel("Nexus is transcribing voice")
            } else if let voiceError {
                Text(voiceError)
                    .font(.caption)
                    .foregroundStyle(NexusColor.Text.primary)
                    .accessibilityLabel("Voice capture failed")
            } else if let imageError {
                Text(imageError)
                    .font(.caption)
                    .foregroundStyle(NexusColor.Text.primary)
                    .accessibilityLabel("Image attachment failed")
            } else if let fileError {
                Text(fileError)
                    .font(.caption)
                    .foregroundStyle(NexusColor.Text.primary)
                    .accessibilityLabel("File attachment failed")
            }
        }
        .padding(12)
        .background(NexusColor.Background.raised.opacity(0.84), in: RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(NexusColor.Line.regular.opacity(0.9), lineWidth: 1)
        }
        .overlay {
            if shouldShowActiveDropRing {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(NexusColor.Line.strong, lineWidth: 1)
            }
        }
        .shadow(color: .black.opacity(0.24), radius: 18, x: 0, y: 10)
        .overlay(alignment: .topTrailing) {
            if isFileDropTargeted {
                fileDropChip
                    .padding(.top, 8)
                    .padding(.trailing, 10)
            }
        }
        .onDrop(
            of: [UTType.fileURL.identifier],
            delegate: AgentFileDropDelegate(
                isTargeted: $isFileDropTargeted,
                isDisabled: isThinking || isSending,
                onDrop: handleFileDrop(providers:)
            )
        )
        .onDrop(
            of: [UTType.image.identifier],
            delegate: AgentImageDropDelegate(
                isTargeted: $isImageDropTargeted,
                isDisabled: !imageDropTargetingEnabled,
                onDrop: handleImageDrop(providers:)
            )
        )
        .fileImporter(
            isPresented: $isFileImporterPresented,
            allowedContentTypes: [.image],
            allowsMultipleSelection: false,
            onCompletion: handleFileImport(_:)
        )
        #if os(iOS)
        // Without an explicit dismiss affordance the software keyboard stays up
        // and occludes the tab bar / nav, trapping the user in the agent chat.
        // A standard keyboard-accessory "Done" button releases focus; the
        // message ScrollView additionally gets `.scrollDismissesKeyboard` in
        // `AgentChatView`. iOS-gated so the shared Mac `regularBody` path that
        // reuses `messageList` stays byte-identical (no AppKit keyboard concept).
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { isInputFocused = false }
                .accessibilityLabel("Dismiss keyboard")
            }
        }
        #endif
        .onDisappear {
            cleanupVoiceCapture()
        }
        .task {
            await refreshVoiceCaptureAvailability()
            await refreshImageCaptureAvailability()
            await refreshImageAttachmentDeferralReason()
        }
        .onChange(of: imageDropTargetingEnabled) { _, isEnabled in
            clearImageDropTargetingIfNeeded(isEnabled: isEnabled)
        }
        #if os(iOS) && canImport(PhotosUI)
        .onChange(of: selectedPhotoItem) { _, item in
            guard let item else { return }
            Task { await attachPhotoPickerItem(item) }
        }
        #endif
    }
}

extension AgentInputBar {
    nonisolated public static func shouldEnableSend(
        input: String,
        isThinking: Bool = false,
        isSending: Bool = false
    ) -> Bool {
        !isThinking && !isSending && !normalize(input).isEmpty
    }

    nonisolated public static func normalize(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated public static func appendTranscript(_ transcript: String, to input: String) -> String {
        let trimmedTranscript = normalize(transcript)
        guard !trimmedTranscript.isEmpty else { return input }

        let trimmedInput = normalize(input)
        guard !trimmedInput.isEmpty else { return trimmedTranscript }
        return "\(trimmedInput) \(trimmedTranscript)"
    }

    nonisolated public static func shouldDisableVoiceButton(
        hasVoiceCapture: Bool,
        isVoiceCaptureAvailable: Bool = true,
        isThinking: Bool = false,
        isVoiceStarting: Bool = false,
        hasActiveVoiceSession: Bool = false,
        isVoiceTranscribing: Bool = false
    ) -> Bool {
        !hasVoiceCapture || !isVoiceCaptureAvailable || isThinking || isVoiceStarting || hasActiveVoiceSession
            || isVoiceTranscribing
    }

    nonisolated public static func shouldDisableImageButton(
        isImageCaptureAvailable: Bool,
        isThinking: Bool = false
    ) -> Bool {
        !isImageCaptureAvailable || isThinking
    }

    nonisolated public static func shouldEnableImageDropTargeting(
        isImageCaptureAvailable: Bool,
        isThinking: Bool = false,
        isSending: Bool = false
    ) -> Bool {
        isImageCaptureAvailable && !isThinking && !isSending
    }

    nonisolated public static func localizedImageDeferralMessage(
        reason: ImageAttachmentDeferralReason
    ) -> String {
        switch reason {
        case .pendingLocalAIPhase:
            return "Image attachments arrive with the on-device model in a later phase."
        }
    }

    nonisolated public static func shouldClearImageDropTargeting(
        isTargeted: Bool,
        isImageDropTargetingEnabled: Bool
    ) -> Bool {
        isTargeted && !isImageDropTargetingEnabled
    }
}

extension AgentInputBar {
    private var canSend: Bool {
        Self.shouldEnableSend(input: input, isThinking: isThinking, isSending: isSending)
    }

    private var voiceIsActive: Bool {
        isVoiceStarting || voiceSession != nil
    }

    private var voiceButtonDisabled: Bool {
        Self.shouldDisableVoiceButton(
            hasVoiceCapture: voiceCapture != nil,
            isVoiceCaptureAvailable: isVoiceCaptureAvailable,
            isThinking: isThinking,
            isVoiceStarting: isVoiceStarting,
            hasActiveVoiceSession: voiceSession != nil,
            isVoiceTranscribing: isVoiceTranscribing
        )
    }

    private var fieldShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: NexusRadius.r3, style: .continuous)
    }

    private var imageDropTargetingEnabled: Bool {
        Self.shouldEnableImageDropTargeting(
            isImageCaptureAvailable: isImageCaptureAvailable,
            isThinking: isThinking,
            isSending: isSending
        )
    }

    private var shouldShowActiveDropRing: Bool {
        isFileDropTargeted || (isImageDropTargeted && imageDropTargetingEnabled)
    }

    private var fileContextPreviewRow: some View {
        HStack(spacing: 8) {
            ForEach(Array(attachedFileContexts.enumerated()), id: \.offset) { index, context in
                HStack(spacing: 6) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 12, weight: .semibold))
                    Text(context.sourceFilename)
                        .font(.caption2)
                        .lineLimit(1)

                    Button {
                        attachedFileContexts.remove(at: index)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .frame(width: 16, height: 16)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove file context")
                }
                .foregroundStyle(NexusColor.Text.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(NexusColor.Background.control, in: Capsule())
                .overlay(Capsule().strokeBorder(NexusColor.Line.regular, lineWidth: 1))
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("File context attachments")
    }

    private var fileDropChip: some View {
        Label("Drop a file", systemImage: "doc.text")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(NexusColor.Text.primary)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(NexusColor.Background.control, in: Capsule())
            .overlay(Capsule().strokeBorder(NexusColor.Line.strong, lineWidth: 1))
            .shadow(color: .black.opacity(0.18), radius: 8, x: 0, y: 4)
            .accessibilityLabel("Drop a file")
    }

    private func imageAttachmentDeferralBanner(reason: ImageAttachmentDeferralReason) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "photo.badge.clock")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(NexusColor.Text.tertiary)
                .frame(width: 18, height: 18)

            Text(Self.localizedImageDeferralMessage(reason: reason))
                .font(.footnote)
                .foregroundStyle(NexusColor.Text.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NexusColor.Background.control.opacity(0.54), in: RoundedRectangle(cornerRadius: NexusRadius.r2))
        .overlay(
            RoundedRectangle(cornerRadius: NexusRadius.r2)
                .strokeBorder(NexusColor.Line.hairline, lineWidth: 1)
        )
        .accessibilityLabel(Self.localizedImageDeferralMessage(reason: reason))
    }

    private var attachmentPreviewRow: some View {
        HStack(spacing: 8) {
            ForEach(Array(attachedImages.enumerated()), id: \.offset) { index, image in
                HStack(spacing: 6) {
                    Image(systemName: "photo")
                        .font(.system(size: 12, weight: .semibold))
                    Text("\(image.mime) - \(image.dataLength) B")
                        .font(.caption2)
                        .lineLimit(1)

                    Button {
                        attachedImages.remove(at: index)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .frame(width: 16, height: 16)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove image attachment")
                }
                .foregroundStyle(NexusColor.Text.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(NexusColor.Background.control, in: Capsule())
                .overlay(Capsule().strokeBorder(NexusColor.Line.regular, lineWidth: 1))
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Image attachments")
    }

    @ViewBuilder
    private var imageButton: some View {
        let isDisabled = imageButtonDisabled
        let foreground = imageButtonForeground
        let border = imageButtonBorder
        #if os(iOS) && canImport(PhotosUI)
        PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
            AgentInputBarImageButtonLabel(
                isDisabled: isDisabled,
                foreground: foreground,
                border: border
            )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.46 : 1)
        .accessibilityLabel("Attach image")
        #else
        Button(
            action: { isFileImporterPresented = true },
            label: {
                AgentInputBarImageButtonLabel(
                    isDisabled: isDisabled,
                    foreground: foreground,
                    border: border
                )
            }
        )
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.46 : 1)
        .accessibilityLabel("Attach image")
        #endif
    }

    private var imageButtonForeground: Color {
        attachedImages.isEmpty ? NexusColor.Text.secondary : NexusColor.Text.primary
    }

    private var imageButtonBorder: Color {
        if imageButtonDisabled {
            return NexusColor.Line.hairline
        }

        return attachedImages.isEmpty ? NexusColor.Line.regular : NexusColor.Line.strong
    }

    private var imageButtonDisabled: Bool {
        Self.shouldDisableImageButton(
            isImageCaptureAvailable: isImageCaptureAvailable,
            isThinking: isThinking
        )
    }

    private var voiceButton: some View {
        Button(
            action: {},
            label: {
                Image(systemName: voiceIsActive ? "mic.fill" : "mic")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(voiceIsActive ? NexusColor.Text.primary : NexusColor.Text.secondary)
                    .frame(width: 30, height: 30)
                    .background(NexusColor.Background.control, in: RoundedRectangle(cornerRadius: NexusRadius.r2))
                    .overlay(
                        RoundedRectangle(cornerRadius: NexusRadius.r2)
                            .strokeBorder(voiceIsActive ? NexusColor.Line.strong : NexusColor.Line.regular, lineWidth: 1)
                    )
            }
        )
        .buttonStyle(.plain)
        .disabled(voiceButtonDisabled)
        .opacity(voiceButtonDisabled ? 0.46 : 1)
        .accessibilityLabel(voiceIsActive ? "Stop recording voice input" : "Record voice input")
        .accessibilityHint("Hold to record, release to transcribe")
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in startVoiceCaptureIfNeeded() }
                .onEnded { _ in Task { await finishVoiceCaptureIfNeeded() } }
        )
    }

    @MainActor
    private func send() async {
        let trimmed = Self.normalize(input)
        guard Self.shouldEnableSend(input: trimmed, isThinking: isThinking, isSending: isSending) else { return }

        isSending = true
        defer { isSending = false }

        guard await canSendCurrentAttachments() else { return }

        let attachments = attachedImages.map(\.dataURL)
        let sentImages = attachedImages
        let sentFileContexts = attachedFileContexts
        let contextPrefix = AgentFileCapture.joinContextPrefixes(attachedFileContexts.map(\.systemPrefix))
        let result = await onSend(trimmed, attachments, contextPrefix)

        switch result {
        case .accepted:
            if Self.normalize(input) == trimmed {
                input = ""
            }
            if attachedImages == sentImages {
                attachedImages = []
            }
            if attachedFileContexts == sentFileContexts {
                attachedFileContexts = []
            }
            imageError = nil
            fileError = nil
        case .rejected(let message):
            imageError = message
        }
    }

    @MainActor
    private func canSendCurrentAttachments() async -> Bool {
        guard !attachedImages.isEmpty else { return true }

        guard let imageCaptureAvailability else {
            imageError = imageUnavailableMessage()
            return false
        }

        let isAvailable = await imageCaptureAvailability()
        isImageCaptureAvailable = isAvailable
        if !isAvailable {
            await refreshImageAttachmentDeferralReason()
            imageError = imageUnavailableMessage()
        }
        return isAvailable
    }

    private func handleImageDrop(providers: [NSItemProvider]) -> Bool {
        guard
            Self.shouldEnableImageDropTargeting(
                isImageCaptureAvailable: isImageCaptureAvailable,
                isThinking: isThinking,
                isSending: isSending
            )
        else {
            isImageDropTargeted = false
            imageError = imageUnavailableMessage()
            return false
        }

        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.image.identifier) })
        else {
            return false
        }

        Task { await attachItemProvider(provider) }
        return true
    }

    private func handleFileDrop(providers: [NSItemProvider]) -> Bool {
        guard !isThinking, !isSending else { return false }
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) })
        else {
            return false
        }

        Task { await attachFileProvider(provider) }
        return true
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        guard isImageCaptureAvailable, !isThinking else {
            imageError = imageUnavailableMessage()
            return
        }

        do {
            guard let url = try result.get().first else { return }
            let didStartAccessing = url.startAccessingSecurityScopedResource()
            defer {
                if didStartAccessing {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            let data = try Data(contentsOf: url)
            let mime = AgentImageCapture.detectedMIME(
                for: data, fallback: UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "image/png")
            try attachImageData(data, mime: mime)
        } catch {
            imageError = AgentImageCapture.userFacingErrorMessage(for: error)
        }
    }

    private func attachImageData(_ data: Data, mime: String) throws {
        let payload = try AgentImageCapture.makePayload(data: data, mime: mime, userText: "")
        attachedImages = payload.attachments
        imageAttachmentDeferralReason = nil
        imageError = nil
        fileError = nil
    }

    @MainActor
    private func attachItemProvider(_ provider: NSItemProvider) async {
        do {
            let data = try await loadImageData(from: provider)
            let mime = AgentImageCapture.detectedMIME(for: data)
            try attachImageData(data, mime: mime)
        } catch {
            imageError = AgentImageCapture.userFacingErrorMessage(for: error)
        }
    }

    @MainActor
    private func attachFileProvider(_ provider: NSItemProvider) async {
        do {
            let url = try await loadFileURL(from: provider)
            try await attachFileURL(url)
        } catch {
            imageError = nil
            fileError = AgentFileCapture.userFacingErrorMessage(for: error)
        }
    }

    @MainActor
    private func attachFileURL(_ url: URL) async throws {
        let result = try await Task.detached(priority: .userInitiated) {
            let didStartAccessing = url.startAccessingSecurityScopedResource()
            defer {
                if didStartAccessing {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            return try AgentFileCapture.extract(from: url)
        }.value

        attachedFileContexts = [
            AgentFileContextPayload(
                sourceFilename: result.sourceFilename,
                systemPrefix: AgentFileCapture.formatSystemPrefix(result)
            )
        ]
        imageError = nil
        fileError = nil
    }

    private func loadImageData(from provider: NSItemProvider) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, error in
                if let data {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(throwing: error ?? AgentImageCaptureError.emptyImage)
                }
            }
        }
    }

    private func loadFileURL(from provider: NSItemProvider) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
                if let url = Self.fileURL(fromProviderItem: item) {
                    continuation.resume(returning: url)
                } else {
                    continuation.resume(throwing: error ?? AgentFileCaptureError.readFailed("Dropped file URL is invalid."))
                }
            }
        }
    }

    nonisolated static func fileURL(fromProviderItem item: NSSecureCoding?) -> URL? {
        func fileURL(_ candidate: URL?) -> URL? {
            guard let candidate, candidate.isFileURL else { return nil }
            return candidate
        }

        if let url = item as? URL {
            return fileURL(url)
        }
        if let url = item as? NSURL {
            return fileURL(url as URL)
        }
        if let data = item as? Data, let value = String(data: data, encoding: .utf8) {
            return fileURL(URL(string: value.trimmingCharacters(in: .whitespacesAndNewlines)))
        }
        if let value = item as? String {
            return fileURL(URL(string: value.trimmingCharacters(in: .whitespacesAndNewlines)))
        }
        return nil
    }

    #if os(iOS) && canImport(PhotosUI)
    @MainActor
    private func attachPhotoPickerItem(_ item: PhotosPickerItem) async {
        guard isImageCaptureAvailable, !isThinking else {
            imageError = imageUnavailableMessage()
            selectedPhotoItem = nil
            return
        }

        defer {
            selectedPhotoItem = nil
        }

        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                throw AgentImageCaptureError.emptyImage
            }
            let mime = AgentImageCapture.detectedMIME(for: data)
            try attachImageData(data, mime: mime)
        } catch {
            imageError = AgentImageCapture.userFacingErrorMessage(for: error)
        }
    }
    #endif

    @MainActor
    private func startVoiceCaptureIfNeeded() {
        guard
            let voiceCapture,
            isVoiceCaptureAvailable,
            !isThinking,
            !isVoiceStarting,
            !isVoiceTranscribing,
            voiceSession == nil
        else { return }

        voiceError = nil
        stopVoiceWhenReady = false
        isVoiceStarting = true
        voiceStartTask = Task {
            var startedSession: AgentVoiceCaptureSession?
            do {
                let session = try await voiceCapture.startRecording()
                startedSession = session
                if Task.isCancelled {
                    await session.discard()
                    await MainActor.run { resetVoiceCaptureStartState() }
                    return
                }

                await MainActor.run {
                    guard !Task.isCancelled else {
                        resetVoiceCaptureStartState()
                        Task {
                            await session.discard()
                        }
                        return
                    }

                    isVoiceStarting = false
                    voiceStartTask = nil
                    voiceSession = session

                    if stopVoiceWhenReady {
                        Task { await finishVoiceCaptureIfNeeded() }
                    }
                }
            } catch is CancellationError {
                if let startedSession {
                    await startedSession.discard()
                }
                await MainActor.run {
                    resetVoiceCaptureStartState()
                }
            } catch {
                await MainActor.run {
                    resetVoiceCaptureStartState()
                    voiceError = Self.voiceErrorMessage(for: error)
                }
            }
        }
    }

    @MainActor
    private func finishVoiceCaptureIfNeeded() async {
        guard !isThinking else { return }

        if isVoiceStarting, voiceSession == nil {
            stopVoiceWhenReady = true
            return
        }

        guard let session = voiceSession else { return }
        voiceSession = nil
        stopVoiceWhenReady = false
        isVoiceTranscribing = true
        voiceError = nil

        do {
            let result = try await session.stopAndTranscribe()
            input = Self.appendTranscript(result.text, to: input)
        } catch {
            voiceError = Self.voiceErrorMessage(for: error)
        }

        isVoiceTranscribing = false
    }

    @MainActor
    private func refreshVoiceCaptureAvailability() async {
        guard let voiceCapture else {
            isVoiceCaptureAvailable = false
            return
        }

        isVoiceCaptureAvailable = await voiceCapture.isAvailable()
    }

    @MainActor
    private func refreshImageCaptureAvailability() async {
        guard let imageCaptureAvailability else {
            isImageCaptureAvailable = false
            return
        }

        isImageCaptureAvailable = await imageCaptureAvailability()
    }

    @MainActor
    private func refreshImageAttachmentDeferralReason() async {
        guard let imageAttachmentDeferralReasonProvider else {
            imageAttachmentDeferralReason = nil
            return
        }

        imageAttachmentDeferralReason = await imageAttachmentDeferralReasonProvider()
    }

    @MainActor
    private func clearImageDropTargetingIfNeeded(isEnabled: Bool) {
        if Self.shouldClearImageDropTargeting(
            isTargeted: isImageDropTargeted,
            isImageDropTargetingEnabled: isEnabled
        ) {
            isImageDropTargeted = false
        }
    }

    private func imageUnavailableMessage() -> String {
        if let imageAttachmentDeferralReason {
            return Self.localizedImageDeferralMessage(reason: imageAttachmentDeferralReason)
        }

        return Self.localizedImageDeferralMessage(reason: .pendingLocalAIPhase)
    }

    @MainActor
    private func cleanupVoiceCapture() {
        voiceStartTask?.cancel()
        voiceStartTask = nil

        let session = voiceSession
        voiceSession = nil
        stopVoiceWhenReady = false
        isVoiceStarting = false
        isVoiceTranscribing = false

        if let session {
            Task {
                await session.discard()
            }
        }
    }

    @MainActor
    private func resetVoiceCaptureStartState() {
        isVoiceStarting = false
        voiceStartTask = nil
        stopVoiceWhenReady = false
    }

    nonisolated private static func voiceErrorMessage(for error: Error) -> String {
        if let captureError = error as? AgentVoiceCaptureError, captureError == .microphonePermissionDenied {
            return "Microphone permission is required."
        }

        return "Voice capture failed."
    }
}
