#if os(macOS)
import NexusCore
import NexusUI
import SwiftUI

// MARK: - macOS platform views (extracted from PeopleListView for file_length compliance)

extension PeopleListView {
    var platformContent: some View {
        Group {
            if people.isEmpty {
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    LiquidEmptyState(
                        systemImage: "person.crop.circle",
                        message: "No people yet. Add a contact, or they appear automatically from meetings."
                    ) {
                        LiquidPrimaryButton("New Person", systemImage: "person.badge.plus") {
                            createPerson()
                        }
                    }
                    Spacer(minLength: 0)
                }
            } else {
                directoryPanel
            }
        }
        .padding(DS.Space.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    var directoryPanel: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: DS.Space.m) {
                macHeader
                macList
            }
            .padding(DS.Space.m)
            .liquidGlass(.sidebar, radius: DS.Radius.l)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            BulkActionBar(
                model: selection,
                allIDs: people.map(\.id),
                actions: bulkActions
            )
            .padding(.horizontal, DS.Space.m)
            .padding(.bottom, DS.Space.s)
        }
    }

    var macHeader: some View {
        HStack(spacing: DS.Space.s) {
            macSearchField
            LiquidIconButton(
                systemImage: selection.isSelecting ? "xmark.circle" : "checkmark.circle",
                accessibilityLabel: selection.isSelecting ? "Cancel selection" : "Select people"
            ) {
                withAnimation(DS.Motion.selection) {
                    if selection.isSelecting { selection.exitSelection() } else { selection.enterSelection() }
                }
            }
            LiquidIconButton(
                systemImage: "person.badge.plus",
                accessibilityLabel: "New Person"
            ) {
                createPerson()
            }
            .disabled(personRepository == nil)
        }
    }

    var macSearchField: some View {
        HStack(spacing: DS.Space.xs) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(DS.ColorToken.textMuted)
            TextField("Search people…", text: $searchText)
                .textFieldStyle(.plain)
                .font(DS.FontToken.body)
                .foregroundStyle(DS.ColorToken.textPrimary)
        }
        .padding(.horizontal, DS.Space.s)
        .frame(height: 30)
        .background {
            RoundedRectangle(cornerRadius: DS.Radius.s, style: .continuous)
                .fill(Color.white.opacity(0.06))
        }
        .overlay {
            RoundedRectangle(cornerRadius: DS.Radius.s, style: .continuous)
                .stroke(DS.ColorToken.strokeHairline, lineWidth: 1)
        }
    }

    var macList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 1) {
                ForEach(model.sections) { section in
                    macSectionHeader(section.title)
                    ForEach(section.people) { person in
                        personButton(person)
                    }
                }
                macFromMeetingsSection
            }
            .padding(.bottom, selection.isSelecting ? 56 + DS.Space.m : 0)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.never)
    }

    func personButton(_ person: Person) -> some View {
        Button {
            if selection.isSelecting {
                withAnimation(DS.Motion.selection) { selection.toggle(id: person.id) }
            } else {
                path.append(person.id)
            }
        } label: {
            PersonListRow(person: person, meetingCount: meetingCounts[person.id] ?? 0)
        }
        .buttonStyle(.plain)
        .selectable(
            isSelecting: selection.isSelecting,
            isSelected: selection.isSelected(id: person.id),
            onToggle: { selection.toggle(id: person.id) }
        )
        .contextMenu {
            personContextMenu(person)
        }
    }

    @ViewBuilder
    var macFromMeetingsSection: some View {
        let placeholders = model.fromMeetings
        if !placeholders.isEmpty {
            Button {
                withAnimation(DS.Motion.panelReveal) { fromMeetingsExpanded.toggle() }
            } label: {
                HStack(spacing: DS.Space.xs) {
                    Image(systemName: fromMeetingsExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                    Text("FROM MEETINGS")
                        .font(DS.FontToken.caption)
                        .kerning(0.6)
                    Text("\(placeholders.count)")
                        .font(DS.FontToken.caption)
                        .monospacedDigit()
                    Spacer(minLength: 0)
                }
                .foregroundStyle(DS.ColorToken.textMuted)
                .padding(.horizontal, DS.Space.xs)
                .padding(.top, DS.Space.l)
                .padding(.bottom, DS.Space.xxs)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("From meetings, \(placeholders.count) hidden")
            .accessibilityHint(fromMeetingsExpanded ? "Hides auto-created people." : "Shows auto-created people.")

            if fromMeetingsExpanded {
                ForEach(placeholders) { person in
                    personButton(person)
                }
            }
        }
    }

    func macSectionHeader(_ title: String) -> some View {
        Text(title)
            .font(DS.FontToken.caption)
            .kerning(0.6)
            .foregroundStyle(DS.ColorToken.textMuted)
            .padding(.horizontal, DS.Space.xs)
            .padding(.top, DS.Space.xs)
            .padding(.bottom, DS.Space.xxs)
    }
}
#endif
