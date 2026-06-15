import NexusCore
import NexusUI
import SwiftData
import SwiftUI

// MARK: - Key-dates section + persistence helpers

extension ProjectEditorSheet {

    // MARK: - View

    var keyDatesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Key dates")
                .nexusType(.eyebrow)
                .foregroundStyle(NexusColor.Text.muted)

            ForEach(keyDates, id: \.anchorKey) { draft in
                HStack {
                    Text(draft.anchorKey)
                        .nexusType(.body)
                        .foregroundStyle(NexusColor.Text.muted)
                        .frame(minWidth: 40, alignment: .leading)
                    Text(draft.label)
                        .nexusType(.body)
                        .foregroundStyle(NexusColor.Text.primary)
                    Spacer()
                    Text(draft.date, style: .date)
                        .nexusType(.body)
                        .foregroundStyle(NexusColor.Text.secondary)
                    if draft.isContractual {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(NexusColor.Text.tertiary)
                            .accessibilityLabel("Contractual")
                    }
                    Button {
                        keyDates.removeAll { $0.anchorKey == draft.anchorKey }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(NexusColor.Text.tertiary)
                }
            }

            // Compact add row: key | label | date | contractual | plus
            HStack {
                TextField("key", text: $newAnchorKey, prompt: Text("e.g. PO, T0"))
                    .textFieldStyle(.plain)
                    .nexusType(.body)
                    .foregroundStyle(NexusColor.Text.primary)
                    .padding(.horizontal, 8)
                    .frame(height: 30, alignment: .leading)
                    .frame(maxWidth: 80)
                    .background(NexusColor.Background.control, in: RoundedRectangle(cornerRadius: NexusRadius.r2))
                    .overlay {
                        RoundedRectangle(cornerRadius: NexusRadius.r2)
                            .strokeBorder(NexusColor.Line.regular, lineWidth: 1)
                    }

                TextField("label", text: $newKeyDateLabel)
                    .textFieldStyle(.plain)
                    .nexusType(.body)
                    .foregroundStyle(NexusColor.Text.primary)
                    .padding(.horizontal, 8)
                    .frame(height: 30)
                    .background(NexusColor.Background.control, in: RoundedRectangle(cornerRadius: NexusRadius.r2))
                    .overlay {
                        RoundedRectangle(cornerRadius: NexusRadius.r2)
                            .strokeBorder(NexusColor.Line.regular, lineWidth: 1)
                    }

                NexusDateField(
                    date: $newKeyDate,
                    components: [.date],
                    accessibilityLabel: "Key date"
                )

                NexusCheckbox(
                    isChecked: $newKeyDateContractual,
                    accessibilityLabel: "Contractual"
                )
                .help("Contractual")

                Button {
                    let key = newAnchorKey.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !key.isEmpty else { return }
                    let draft = ProjectExecutionModel.KeyDateDraft(
                        anchorKey: key,
                        label: newKeyDateLabel.trimmingCharacters(in: .whitespacesAndNewlines),
                        date: newKeyDate,
                        isContractual: newKeyDateContractual
                    )
                    if let index = keyDates.firstIndex(where: { $0.anchorKey == key }) {
                        keyDates[index] = draft
                    } else {
                        keyDates.append(draft)
                    }
                    newAnchorKey = ""
                    newKeyDateLabel = ""
                    newKeyDate = .now
                    newKeyDateContractual = false
                } label: {
                    Image(systemName: "plus.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(NexusColor.Text.primary)
                .disabled(newAnchorKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    // MARK: - Load

    @MainActor
    func loadKeyDates(context: ModelContext, projectID: UUID) {
        let repo = ProjectKeyDateRepository(context: context)
        keyDates =
            (try? repo.list(projectID: projectID))?.map {
                ProjectExecutionModel.KeyDateDraft(
                    anchorKey: $0.anchorKey,
                    label: $0.label,
                    date: $0.date,
                    isContractual: $0.isContractual
                )
            } ?? []
    }

    // MARK: - Persistence diff

    @MainActor
    func applyKeyDateDiff(projectID: UUID, context: ModelContext) throws {
        let keyDateRepo = ProjectKeyDateRepository(context: context)
        let persistedDrafts = (try keyDateRepo.list(projectID: projectID)).map {
            ProjectExecutionModel.KeyDateDraft(
                anchorKey: $0.anchorKey,
                label: $0.label,
                date: $0.date,
                isContractual: $0.isContractual
            )
        }
        let diff = ProjectExecutionModel.keyDateDiff(current: persistedDrafts, desired: keyDates)
        for draft in diff.upserts {
            try keyDateRepo.setKeyDate(
                projectID: projectID,
                anchorKey: draft.anchorKey,
                label: draft.label,
                date: draft.date,
                isContractual: draft.isContractual
            )
        }
        for key in diff.deletions {
            try keyDateRepo.delete(projectID: projectID, anchorKey: key)
        }
    }
}
