import NexusCore
import NexusUI
import SwiftData
import SwiftUI

#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

/// Renders + edits a single `Block`. Every block kind has its own render path
/// (spec §5: native, no WebView except `html(raw)`). Text-bearing blocks are
/// edited as staged plain text (spec §5 staging — inline-span mark editing is a
/// later stage); display is always full-fidelity through `InlineRunRendering`.
struct BlockView: View {
    let block: Block
    let model: NoteEditorModel
    let onOpenRef: (UUID) -> Void

    var body: some View {
        switch block.kind {
        case .paragraph(let runs):
            TextBlockEditor(
                block: block, model: model, runs: runs, font: .body, role: .paragraph)
        case .heading(let level, let runs):
            TextBlockEditor(
                block: block, model: model, runs: runs, font: headingFont(level), role: .heading)
        case .todo(let taskRef, let runs):
            TodoBlockView(block: block, taskRef: taskRef, runs: runs, model: model)
        case .bulleted(let runs):
            ListBlockEditor(block: block, model: model, runs: runs, marker: "•")
        case .numbered(let runs):
            ListBlockEditor(block: block, model: model, runs: runs, marker: "1.")
        case .quote(let runs):
            QuoteBlockView(block: block, model: model, runs: runs)
        case .code(let language, let text):
            CodeBlockView(block: block, model: model, language: language, text: text)
        case .divider:
            Divider().overlay(DS.ColorToken.strokeDefault)
        case .image(let ref, let asset):
            ImageBlockView(ref: ref, asset: asset)
        case .embed(let ref, let kind):
            EmbedBlockView(ref: ref, kind: kind, model: model, onOpen: onOpenRef)
        case .table(let rows):
            TableBlockView(block: block, model: model, rows: rows.map(\.cells))
        case .html(let raw):
            HTMLBlockView(block: block, model: model, raw: raw)
        }
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: return NexusType.h1
        case 2: return NexusType.h2
        default: return NexusType.h3
        }
    }
}

// MARK: - Text-bearing blocks

private enum TextRole {
    case paragraph
    case heading
}

private struct TextBlockEditor: View {
    let block: Block
    let model: NoteEditorModel
    let runs: [InlineRun]
    let font: Font
    let role: TextRole
    @State private var draft: String = ""
    @State private var trigger: InlineLinkInsertion.Trigger?

    var body: some View {
        Group {
            if model.canEdit {
                editor
            } else {
                Text(InlineRunRendering.attributed(runs))
                    .font(font)
                    .foregroundStyle(NexusColor.Text.primary)
            }
        }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField(placeholder, text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(font)
                .foregroundStyle(NexusColor.Text.primary)
                .onAppear { draft = InlineRunRendering.plainText(runs) }
                .onChange(of: block.id) { _, _ in
                    draft = InlineRunRendering.plainText(runs)
                    trigger = nil
                }
                .onChange(of: draft) { _, newValue in
                    // Detect a typed `[[query` trigger (spec §9, GAP #6).
                    trigger = InlineLinkInsertion.detectTrigger(in: newValue)
                }
                .onSubmit { commit() }
                .submitLabel(.return)
            if let trigger {
                InlineLinkAutocomplete(query: trigger.query, excludingNoteID: model.noteID) { candidate in
                    pickLink(candidate, trigger: trigger)
                }
            }
        }
    }

    private var placeholder: String { role == .heading ? "Heading" : "Write…" }

    private func commit() {
        guard draft != InlineRunRendering.plainText(runs) else { return }
        model.setPlainText(draft, forBlock: block.id)
    }

    /// On pick: splice the `.link` run through the model AND sync the local draft to
    /// the flattened plain text. The model write keeps the run (so it persists +
    /// mirrors a `mentions` edge); the local `draft` sync keeps the TextField from
    /// re-showing the now-replaced `[[query` token (same block id → no reset fires).
    private func pickLink(_ candidate: LinkCandidate, trigger: InlineLinkInsertion.Trigger) {
        model.insertInlineLink(to: candidate, trigger: trigger, draft: draft, forBlock: block.id)
        let spliced = InlineLinkInsertion.splice(draft: draft, trigger: trigger, candidate: candidate)
        draft = InlineRunRendering.plainText(spliced)
        self.trigger = nil
    }
}

private struct ListBlockEditor: View {
    let block: Block
    let model: NoteEditorModel
    let runs: [InlineRun]
    let marker: String
    @State private var draft: String = ""

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(marker)
                .nexusType(.body)
                .foregroundStyle(NexusColor.Text.tertiary)
            if model.canEdit {
                TextField("List item", text: $draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .nexusType(.body)
                    .foregroundStyle(NexusColor.Text.primary)
                    .onAppear { draft = InlineRunRendering.plainText(runs) }
                    .onChange(of: block.id) { _, _ in draft = InlineRunRendering.plainText(runs) }
                    .onSubmit {
                        if draft != InlineRunRendering.plainText(runs) {
                            model.setPlainText(draft, forBlock: block.id)
                        }
                    }
            } else {
                Text(InlineRunRendering.attributed(runs))
                    .nexusType(.body)
                    .foregroundStyle(NexusColor.Text.primary)
            }
        }
    }
}

private struct QuoteBlockView: View {
    let block: Block
    let model: NoteEditorModel
    let runs: [InlineRun]
    @State private var draft: String = ""

    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 1)
                .fill(NexusColor.Line.strong)
                .frame(width: 3)
            if model.canEdit {
                TextField("Quote", text: $draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .nexusType(.body)
                    .italic()
                    .foregroundStyle(NexusColor.Text.secondary)
                    .onAppear { draft = InlineRunRendering.plainText(runs) }
                    .onSubmit {
                        if draft != InlineRunRendering.plainText(runs) {
                            model.setPlainText(draft, forBlock: block.id)
                        }
                    }
            } else {
                Text(InlineRunRendering.attributed(runs))
                    .nexusType(.body)
                    .italic()
                    .foregroundStyle(NexusColor.Text.secondary)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Todo (checkbox ↔ Task seam, §7)

private struct TodoBlockView: View {
    let block: Block
    let taskRef: UUID
    let runs: [InlineRun]
    let model: NoteEditorModel
    @State private var draft: String = ""

    // §7: the `TaskItem` is the single source of truth. Holding it via `@Query`
    // (not an imperative fetch) means a `toggleTodo`/`editTodoText` write — or any
    // edit to the same task elsewhere (Tasks list, agent) — invalidates this row,
    // so the checkbox + label refresh live with no manual reload.
    @Query private var tasks: [TaskItem]

    init(block: Block, taskRef: UUID, runs: [InlineRun], model: NoteEditorModel) {
        self.block = block
        self.taskRef = taskRef
        self.runs = runs
        self.model = model
        _tasks = Query(filter: #Predicate<TaskItem> { $0.id == taskRef && $0.deletedAt == nil })
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Button {
                model.toggleTodo(blockID: block.id)
            } label: {
                Image(systemName: isDone ? "checkmark.square.fill" : "square")
                    .foregroundStyle(isDone ? NexusColor.Accent.lime : NexusColor.Text.tertiary)
            }
            .buttonStyle(.plain)
            .disabled(!model.canEdit)

            if model.canEdit {
                TextField("To-do", text: $draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .nexusType(.body)
                    .strikethrough(isDone)
                    .foregroundStyle(isDone ? NexusColor.Text.muted : NexusColor.Text.primary)
                    .onAppear { draft = liveTitle }
                    .onChange(of: block.id) { _, _ in draft = liveTitle }
                    .onSubmit {
                        if draft != liveTitle { model.editTodoText(draft, blockID: block.id) }
                    }
            } else {
                Text(liveTitle)
                    .nexusType(.body)
                    .strikethrough(isDone)
                    .foregroundStyle(isDone ? NexusColor.Text.muted : NexusColor.Text.primary)
            }
        }
    }

    private var task: TaskItem? { tasks.first }
    private var isDone: Bool { task?.status == .done }
    // Live title from the TaskItem (truth); falls back to the cached run label.
    private var liveTitle: String { task?.title ?? InlineRunRendering.plainText(runs) }
}

// MARK: - Code

private struct CodeBlockView: View {
    let block: Block
    let model: NoteEditorModel
    let language: String?
    let text: String
    @State private var draft: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let language, !language.isEmpty {
                Text(language)
                    .nexusType(.eyebrow)
                    .foregroundStyle(NexusColor.Text.tertiary)
            }
            if model.canEdit {
                NexusTextEditor(text: $draft, minHeight: 100, isMonospaced: true)
                    .onAppear { draft = text }
                    .onChange(of: draft) { _, newValue in
                        if newValue != text { model.setCode(newValue, forBlock: block.id) }
                    }
            } else {
                Text(text)
                    .font(NexusType.mono)
                    .foregroundStyle(NexusColor.Text.primary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NexusColor.Background.control, in: RoundedRectangle(cornerRadius: NexusRadius.r1))
    }
}

// MARK: - Image

private struct ImageBlockView: View {
    let ref: UUID?
    let asset: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let image = localImage {
                image
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 260)
                    .clipShape(RoundedRectangle(cornerRadius: NexusRadius.r1))
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "photo")
                        .foregroundStyle(NexusColor.Text.tertiary)
                    Text(asset ?? ref?.uuidString ?? "Image")
                        .nexusType(.bodySmall)
                        .foregroundStyle(NexusColor.Text.muted)
                        .lineLimit(1)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NexusColor.Background.control, in: RoundedRectangle(cornerRadius: NexusRadius.r1))
    }

    private var localImage: Image? {
        guard let asset, let root = try? NoteAttachmentRoot.url(create: false) else { return nil }
        let url = root.appendingPathComponent(asset, isDirectory: false)
        #if os(macOS)
        guard let image = NSImage(contentsOf: url) else { return nil }
        return Image(nsImage: image)
        #elseif os(iOS)
        guard let image = UIImage(contentsOfFile: url.path) else { return nil }
        return Image(uiImage: image)
        #else
        return nil
        #endif
    }
}

// MARK: - Table (render + edit, GAP #5)

private struct TableBlockView: View {
    let block: Block
    let model: NoteEditorModel
    /// Each row is a list of cells; each cell a list of inline runs. Passed as
    /// nested arrays (not `NexusCore.TableRow`) to avoid the SwiftUI `TableRow`
    /// name collision at this call site. Structural edits route back through `model`
    /// by `block.id` + indices.
    let rows: [[[InlineRun]]]

    private var columnCount: Int { rows.first?.count ?? 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            grid
            if model.canEdit {
                controls
            }
        }
    }

    private var grid: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
                HStack(spacing: 0) {
                    ForEach(Array(row.enumerated()), id: \.offset) { columnIndex, cell in
                        cellView(cell, row: rowIndex, column: columnIndex)
                    }
                }
            }
        }
        .background(NexusColor.Background.control, in: RoundedRectangle(cornerRadius: NexusRadius.r1))
    }

    @ViewBuilder private func cellView(_ cell: [InlineRun], row: Int, column: Int) -> some View {
        Group {
            if model.canEdit {
                TableCellEditor(
                    block: block,
                    model: model,
                    runs: cell,
                    row: row,
                    column: column,
                    isHeader: row == 0
                )
            } else {
                Text(InlineRunRendering.attributed(cell))
                    .nexusType(.bodySmall)
                    .foregroundStyle(NexusColor.Text.primary)
                    .fontWeight(row == 0 ? .semibold : .regular)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6)
            }
        }
        .overlay(Rectangle().stroke(NexusColor.Line.strong, lineWidth: 0.5))
    }

    /// Add/remove row + column. Removal floors at one row / one column (kept in
    /// `BlockListOps`); the buttons disable at that floor to make the limit legible.
    private var controls: some View {
        HStack(spacing: 14) {
            tableButton("Add row", systemImage: "plus.rectangle.portrait") {
                model.addTableRow(forBlock: block.id)
            }
            tableButton("Remove row", systemImage: "minus.rectangle.portrait") {
                model.removeTableRow(forBlock: block.id)
            }
            .disabled(rows.count <= 1)

            Divider().frame(height: 14)

            tableButton("Add column", systemImage: "plus.rectangle") {
                model.addTableColumn(forBlock: block.id)
            }
            tableButton("Remove column", systemImage: "minus.rectangle") {
                model.removeTableColumn(forBlock: block.id)
            }
            .disabled(columnCount <= 1)
            Spacer(minLength: 0)
        }
    }

    private func tableButton(
        _ label: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(label, systemImage: systemImage)
                .labelStyle(.iconOnly)
                .font(.system(size: 13))
                .foregroundStyle(NexusColor.Text.tertiary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
    }
}

/// A single editable table cell. Staged plain-text editing (mirrors the other
/// text-bearing block editors): the draft binds to the cell's flattened text and
/// commits a single unmarked run back through the model on submit.
private struct TableCellEditor: View {
    let block: Block
    let model: NoteEditorModel
    let runs: [InlineRun]
    let row: Int
    let column: Int
    let isHeader: Bool
    @State private var draft: String = ""

    var body: some View {
        TextField(isHeader ? "Header" : "Cell", text: $draft, axis: .vertical)
            .textFieldStyle(.plain)
            .nexusType(.bodySmall)
            .fontWeight(isHeader ? .semibold : .regular)
            .foregroundStyle(NexusColor.Text.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(6)
            .onAppear { draft = InlineRunRendering.plainText(runs) }
            .onChange(of: block.id) { _, _ in draft = InlineRunRendering.plainText(runs) }
            .onSubmit { commit() }
    }

    private func commit() {
        guard draft != InlineRunRendering.plainText(runs) else { return }
        model.setTableCell(draft, row: row, column: column, forBlock: block.id)
    }
}
