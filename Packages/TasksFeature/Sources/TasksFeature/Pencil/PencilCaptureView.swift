#if os(iOS)
import NexusCore
import NexusUI
import PencilKit
import SwiftUI
import Vision

public struct PencilCaptureView: View {
    @Environment(\.taskParser) private var parser
    @Environment(\.taskRepository) private var repository
    @Environment(\.dismiss) private var dismiss

    @State private var canvas = PKCanvasView()
    @State private var state: PencilCaptureState?

    public init() {}

    public var body: some View {
        VStack(spacing: 12) {
            PencilCanvas(canvas: canvas)
                .frame(minHeight: 260)
                .background(NexusColor.Background.panel)
                .clipShape(RoundedRectangle(cornerRadius: NexusRadius.r5, style: .continuous))

            TextField("Recognized task...", text: bindingForText)
                .textFieldStyle(.roundedBorder)

            if let errorMessage = state?.error {
                // §2 value-identical zero-pixel rename: Semantic.negative ≡
                // Text.primary (both 0xF2F2F4), following the canonical §5
                // error-row anchor (TaskListView.errorRow / AgentChatView
                // inline-error row): error legibility via contrast/weight.
                Text(errorMessage)
                    .foregroundStyle(NexusColor.Text.primary)
                    .font(.caption)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                Button("Recognize") {
                    ensureState()
                    Task { await state?.recognizeDrawing() }
                }
                .disabled(state?.isRecognizing == true)
                Spacer()
                Button("Save") { save() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .onAppear { ensureState() }
    }

    private var bindingForText: Binding<String> {
        Binding(
            get: { state?.text ?? "" },
            set: { newValue in
                ensureState()
                state?.text = newValue
            }
        )
    }

    private func ensureState() {
        guard state == nil else { return }
        state = PencilCaptureState {
            try recognizeText(from: canvas.drawing)
        }
    }

    private func save() {
        guard let parser, let repository, let text = state?.text, !text.isEmpty else { return }
        Task {
            let parsed = await parser.parse(text, locale: .current, now: .now)
            let task = TaskItem(
                title: parsed.title,
                dueAt: parsed.dueAt,
                startAt: parsed.startAt,
                endAt: parsed.endAt,
                deadlineAt: parsed.deadlineAt,
                priority: parsed.priority ?? .none,
                tags: parsed.tags,
                recurrenceRule: parsed.recurrence
            )
            try? repository.insert(task)
            dismiss()
        }
    }

    private func recognizeText(from drawing: PKDrawing) throws -> String {
        let image = drawing.image(from: drawing.bounds, scale: 2)
        guard let cgImage = image.cgImage else { return "" }
        let request = VNRecognizeTextRequest()
        request.recognitionLanguages = PencilRecognitionLanguages.make()
        request.recognitionLevel = .accurate
        let handler = VNImageRequestHandler(cgImage: cgImage)
        try handler.perform([request])
        return request.results?
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: " ") ?? ""
    }

}

private struct PencilCanvas: UIViewRepresentable {
    let canvas: PKCanvasView

    func makeUIView(context: Context) -> PKCanvasView {
        // Allow finger input too (not just Apple Pencil) so the capture works on
        // devices without a Pencil and for users who prefer touch.
        canvas.drawingPolicy = .anyInput
        return canvas
    }

    func updateUIView(_ uiView: PKCanvasView, context: Context) {}
}
#endif
