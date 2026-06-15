import NexusCore
import NexusUI
import SwiftUI

/// One custom property row in the editor's properties panel (Tranche 2 Plan E):
/// editable key (64-pt label column, matching `NoteEditorView.propertyRow`), a
/// typed value editor, a type menu, and a remove button.
struct NotePropertyRowView: View {
    let property: NoteProperty
    let canEdit: Bool
    let onRenameKey: (String) -> Void
    let onSetValue: (NotePropertyValue) -> Void
    let onRemove: () -> Void

    @State private var keyText: String = ""

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.m) {
            NexusTextField("Key", text: $keyText, isEnabled: canEdit)
                .frame(width: 64, alignment: .leading)
                .onSubmit { onRenameKey(keyText) }

            NotePropertyValueEditor(value: property.value, canEdit: canEdit, onCommit: onSetValue)

            Spacer(minLength: 0)

            if canEdit {
                typeMenu
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(DS.ColorToken.textTertiary)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Remove property \(property.key)")
            }
        }
        .onAppear { keyText = property.key }
    }

    private var typeMenu: some View {
        NexusSelect(
            selection: Binding(
                get: { NotePropertyEditing.PropertyType(of: property.value) },
                set: { onSetValue(NotePropertyEditing.convert(property.value, to: $0)) }
            ),
            options: NotePropertyEditing.PropertyType.allCases,
            label: { $0.label },
            isEnabled: canEdit,
            accessibilityLabel: "Property type"
        )
        .fixedSize()
    }
}

/// Typed value editor for one property: text field for text/number/list (commit
/// on submit), toggle for booleans, date picker for dates. Each case is its own
/// view identity, so the text buffer re-seeds on type change.
struct NotePropertyValueEditor: View {
    let value: NotePropertyValue
    let canEdit: Bool
    let onCommit: (NotePropertyValue) -> Void

    var body: some View {
        switch value {
        case .string(let text):
            CommitTextField(initial: text, canEdit: canEdit) { onCommit(.string($0)) }
        case .number(let number):
            CommitTextField(
                initial: NotePropertyEditing.numberText(number),
                canEdit: canEdit
            ) { onCommit(.number(Double($0) ?? number)) }
        case .bool(let flag):
            Toggle(
                "",
                isOn: Binding(get: { flag }, set: { onCommit(.bool($0)) })
            )
            .labelsHidden()
            .disabled(!canEdit)
        case .date(let date):
            NexusDateField(
                date: Binding(get: { date }, set: { onCommit(.date($0)) }),
                components: [.date],
                isEnabled: canEdit,
                accessibilityLabel: "Property date value"
            )
        case .list(let items):
            CommitTextField(
                initial: items.joined(separator: ", "),
                canEdit: canEdit
            ) { onCommit(.list(NotePropertyEditing.listItems(from: $0))) }
        }
    }
}

/// A plain text field that seeds from `initial` and commits on submit only —
/// no live writes while typing (one save per commit, the repo's save-boundary
/// discipline).
private struct CommitTextField: View {
    let initial: String
    let canEdit: Bool
    let commit: (String) -> Void

    @State private var text = ""

    var body: some View {
        NexusTextField("Value", text: $text, isEnabled: canEdit)
            .onSubmit { commit(text) }
            .onAppear { text = initial }
    }
}
