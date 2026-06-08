import NexusUI
import SwiftUI

/// Inline tag editor used by the task inspector header: a removable chip per tag
/// plus an add field. Extracted from `TaskDetailInspector` to keep that file
/// under the file-length budget. `internal` (not file-private) so the inspector
/// extension can reference it across files.
struct TagsEditor: View {
    @Binding var tags: [String]
    let onChange: () -> Void

    @State private var draft: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                ForEach(tags, id: \.self) { tag in
                    NexusChip("#\(tag)", systemImage: "xmark.circle.fill")
                        .onTapGesture {
                            tags.removeAll { $0 == tag }
                            onChange()
                        }
                }
            }
            HStack {
                tagDraftField
                Button("Add") {
                    let cleaned = draft.trimmingCharacters(in: .whitespaces).lowercased()
                    guard !cleaned.isEmpty, !tags.contains(cleaned) else { return }
                    tags.append(cleaned)
                    draft = ""
                    onChange()
                }
                .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    @ViewBuilder
    private var tagDraftField: some View {
        #if os(iOS)
        TextField("New tag", text: $draft)
            .textInputAutocapitalization(.never)
        #else
        TextField("New tag", text: $draft)
        #endif
    }
}
