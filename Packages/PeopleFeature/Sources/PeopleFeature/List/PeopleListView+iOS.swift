#if os(iOS)
import NexusCore
import NexusUI
import SwiftUI

// MARK: - iOS platform views (extracted from PeopleListView for file_length compliance)

extension PeopleListView {
    var platformContent: some View {
        ZStack(alignment: .bottom) {
            Group {
                if people.isEmpty {
                    LiquidEmptyState(
                        systemImage: "person.crop.circle",
                        message: "No people yet. Add a contact, or they appear automatically from meetings."
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    iosList
                }
            }
            .navigationTitle("People")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        createPerson()
                    } label: {
                        Label("New Person", systemImage: "person.badge.plus")
                    }
                    .disabled(personRepository == nil)
                }
            }

            BulkActionBar(
                model: selection,
                allIDs: people.map(\.id),
                actions: bulkActions
            )
            .padding(.horizontal, DS.Space.s)
            .padding(.bottom, DS.Space.xs)
        }
    }

    var iosList: some View {
        List {
            ForEach(model.sections) { section in
                Section {
                    ForEach(section.people) { person in
                        NavigationLink(value: person.id) {
                            PersonListRow(person: person, meetingCount: meetingCounts[person.id] ?? 0)
                        }
                        .listRowBackground(Color.clear)
                        .selectable(
                            isSelecting: selection.isSelecting,
                            isSelected: selection.isSelected(id: person.id),
                            onToggle: { selection.toggle(id: person.id) }
                        )
                        .onLongPressGesture {
                            selection.enterSelection()
                            selection.toggle(id: person.id)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                softDeleteWithUndo(person)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .contextMenu {
                            personContextMenu(person)
                        }
                    }
                    .onDelete { offsets in iosDelete(from: section.people, at: offsets) }
                } header: {
                    iosSectionHeader(section.title)
                }
            }

            iosFromMeetingsSection
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .searchable(text: $searchText, prompt: "Search people")
    }

    @ViewBuilder
    var iosFromMeetingsSection: some View {
        let placeholders = model.fromMeetings
        if !placeholders.isEmpty {
            Section {
                if fromMeetingsExpanded {
                    ForEach(placeholders) { person in
                        NavigationLink(value: person.id) {
                            PersonListRow(person: person, meetingCount: meetingCounts[person.id] ?? 0)
                        }
                        .contextMenu {
                            personContextMenu(person)
                        }
                    }
                    .onDelete { offsets in iosDelete(from: placeholders, at: offsets) }
                }
            } header: {
                Button {
                    withAnimation(DS.Motion.panelReveal) { fromMeetingsExpanded.toggle() }
                } label: {
                    HStack(spacing: DS.Space.xs) {
                        Image(systemName: fromMeetingsExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                        Text("From meetings")
                        Spacer(minLength: DS.Space.s)
                        Text("\(placeholders.count)")
                            .monospacedDigit()
                    }
                    .font(DS.FontToken.caption)
                    .foregroundStyle(DS.ColorToken.textTertiary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("From meetings, \(placeholders.count) hidden")
                .accessibilityHint(fromMeetingsExpanded ? "Hides auto-created people." : "Shows auto-created people.")
            }
        }
    }

    func iosSectionHeader(_ title: String) -> some View {
        Text(title)
            .font(DS.FontToken.caption)
            .kerning(0.6)
            .foregroundStyle(DS.ColorToken.textMuted)
    }

    func iosDelete(from rows: [Person], at offsets: IndexSet) {
        guard let personRepository else { return }
        for index in offsets where rows.indices.contains(index) {
            try? personRepository.softDelete(rows[index])
        }
    }
}
#endif
