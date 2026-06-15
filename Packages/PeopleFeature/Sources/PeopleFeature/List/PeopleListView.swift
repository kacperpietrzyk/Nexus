import NexusCore
import NexusUI
import SwiftData
import SwiftUI

/// Row hover wash — same value as the Liquid kit's dense-list rows
/// (`LiquidListKit.taskRowHoverFill`, private there): no scale in dense lists,
/// just a subtle fill.
private let personRowHoverFill = Color.white.opacity(0.04)

/// The People surface (spec §6): a searchable list of all live `Person` contact
/// records with a "New Person" affordance and navigation into the profile. Mac +
/// iOS; the Watch projection is out of scope (slim Watch).
///
/// The list is grouped into alphabetical sections; the junk auto-created
/// "Participant N" / "Speaker N" placeholder rows are suppressed from the main
/// list and revealed only via a collapsible "From meetings" section at the bottom
/// (view-layer cleanup — the root cause of placeholder creation is fixed
/// elsewhere). Each row carries a trailing meeting-count label, resolved once in a
/// single batched fetch rather than per-row.
///
/// macOS renders the Liquid idiom: an in-panel search field + New Person action
/// (never window-toolbar items — the Liquid shell owns the window chrome) above a
/// hover-responsive row list. iOS keeps the native `List` + `.searchable` +
/// navigation-bar toolbar.
///
/// Mounts inside the existing app navigation, so it inherits the scene's
/// `.modelContainer` (where `Person` is already registered via `NexusSchemaV12`) —
/// no separate container registration is needed.
public struct PeopleListView: View {
    @Environment(\.personRepository) private var personRepository
    @Environment(\.modelContext) private var modelContext

    @Query(
        filter: #Predicate<Person> { $0.deletedAt == nil },
        sort: \Person.displayName,
        order: .forward
    )
    private var people: [Person]

    @State private var path: [UUID] = []
    @State private var searchText = ""
    @State private var newPersonError: String?
    @State private var meetingCounts: [UUID: Int] = [:]
    @State private var fromMeetingsExpanded = false

    public init() {}

    private var model: PeopleListModel {
        PeopleListFiltering.sectionedModel(people, query: searchText)
    }

    public var body: some View {
        NavigationStack(path: $path) {
            platformContent
                .navigationDestination(for: UUID.self) { id in
                    PersonProfileView(personID: id)
                }
                .alert(
                    "Couldn't add person",
                    isPresented: Binding(
                        get: { newPersonError != nil },
                        set: { if !$0 { newPersonError = nil } }
                    )
                ) {
                    Button("OK", role: .cancel) { newPersonError = nil }
                } message: {
                    Text(newPersonError ?? "")
                }
                .task(id: people.count) { reloadMeetingCounts() }
        }
    }

    // MARK: - macOS (Liquid)

    #if os(macOS)
    private var platformContent: some View {
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

    /// The directory sits in one contained glass pane — the same idiom as the
    /// Liquid Meetings list pane (`.liquidGlass(.sidebar)`) — centered to a
    /// readable measure on the wide content panel rather than floating row by
    /// row on the bare substrate. `Person` records are sparse (avatar · name ·
    /// meeting count), so a full-width row band would expose dead space
    /// mid-row; a bounded, contained column reads as deliberate.
    private var directoryPanel: some View {
        VStack(spacing: DS.Space.m) {
            header
            macList
        }
        .padding(DS.Space.m)
        .liquidGlass(.sidebar, radius: DS.Radius.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// In-panel header: live search + New Person. Window-toolbar items are
    /// deliberately absent on macOS — the Liquid shell owns the window chrome.
    private var header: some View {
        HStack(spacing: DS.Space.s) {
            searchField
            LiquidIconButton(
                systemImage: "person.badge.plus",
                accessibilityLabel: "New Person"
            ) {
                createPerson()
            }
            .disabled(personRepository == nil)
        }
    }

    /// Same live-search idiom as the Liquid Meetings list pane.
    private var searchField: some View {
        HStack(spacing: DS.Space.xs) {
            Image(systemName: "magnifyingglass")
                // 11 pt magnifier sits optically level with the 13 pt body text
                // in the 30 pt field (Meetings list idiom); no icon-size token.
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
                // macOS: a light translucent inset so the field reads as glass,
                // not a near-black slab on the light pane. iOS keeps the sunken fill.
                #if os(macOS)
                .fill(Color.white.opacity(0.06))
                #else
                .fill(DS.ColorToken.backgroundSunken.opacity(0.6))
                #endif
        }
        .overlay {
            RoundedRectangle(cornerRadius: DS.Radius.s, style: .continuous)
                .stroke(DS.ColorToken.strokeHairline, lineWidth: 1)
        }
    }

    private var macList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 1) {
                ForEach(model.sections) { section in
                    sectionHeader(section.title)
                    ForEach(section.people) { person in
                        personButton(person)
                    }
                }

                macFromMeetingsSection
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.never)
    }

    private func personButton(_ person: Person) -> some View {
        Button {
            path.append(person.id)
        } label: {
            PersonListRow(person: person, meetingCount: meetingCounts[person.id] ?? 0)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Delete", role: .destructive) { delete(person) }
        }
    }

    @ViewBuilder
    private var macFromMeetingsSection: some View {
        let placeholders = model.fromMeetings
        if !placeholders.isEmpty {
            Button {
                withAnimation(DS.Motion.panelReveal) { fromMeetingsExpanded.toggle() }
            } label: {
                HStack(spacing: DS.Space.xs) {
                    Image(systemName: fromMeetingsExpanded ? "chevron.down" : "chevron.right")
                        // 9 pt disclosure chevron rides the 10 pt caption — carried
                        // over from the pre-Liquid header; no icon-size token.
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

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(DS.FontToken.caption)
            .kerning(0.6)
            .foregroundStyle(DS.ColorToken.textMuted)
            .padding(.horizontal, DS.Space.xs)
            .padding(.top, DS.Space.xs)
            .padding(.bottom, DS.Space.xxs)
    }

    private func delete(_ person: Person) {
        guard let personRepository else { return }
        try? personRepository.softDelete(person)
    }

    // MARK: - iOS (native list)

    #else
    private var platformContent: some View {
        Group {
            if people.isEmpty {
                LiquidEmptyState(
                    systemImage: "person.crop.circle",
                    message: "No people yet. Add a contact, or they appear automatically from meetings."
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                list
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
    }

    private var list: some View {
        List {
            ForEach(model.sections) { section in
                Section {
                    ForEach(section.people) { person in
                        NavigationLink(value: person.id) {
                            PersonListRow(person: person, meetingCount: meetingCounts[person.id] ?? 0)
                        }
                        .listRowBackground(Color.clear)
                    }
                    .onDelete { offsets in delete(from: section.people, at: offsets) }
                } header: {
                    sectionHeader(section.title)
                }
            }

            fromMeetingsSection
        }
        .listStyle(.plain)
        // Liquid: transparent so the shell aurora reads behind the directory.
        .scrollContentBackground(.hidden)
        .searchable(text: $searchText, prompt: "Search people")
    }

    @ViewBuilder
    private var fromMeetingsSection: some View {
        let placeholders = model.fromMeetings
        if !placeholders.isEmpty {
            Section {
                if fromMeetingsExpanded {
                    ForEach(placeholders) { person in
                        NavigationLink(value: person.id) {
                            PersonListRow(person: person, meetingCount: meetingCounts[person.id] ?? 0)
                        }
                    }
                    .onDelete { offsets in delete(from: placeholders, at: offsets) }
                }
            } header: {
                Button {
                    withAnimation(DS.Motion.panelReveal) { fromMeetingsExpanded.toggle() }
                } label: {
                    HStack(spacing: DS.Space.xs) {
                        Image(systemName: fromMeetingsExpanded ? "chevron.down" : "chevron.right")
                            // 9 pt disclosure chevron rides the 10 pt caption.
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

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(DS.FontToken.caption)
            .kerning(0.6)
            .foregroundStyle(DS.ColorToken.textMuted)
    }

    private func delete(from rows: [Person], at offsets: IndexSet) {
        guard let personRepository else { return }
        for index in offsets where rows.indices.contains(index) {
            try? personRepository.softDelete(rows[index])
        }
    }
    #endif

    // MARK: - Shared

    private func createPerson() {
        guard let personRepository else { return }
        do {
            let person = try personRepository.create(displayName: "")
            path.append(person.id)
        } catch {
            newPersonError = error.localizedDescription
        }
    }

    /// One batched pass over the `Link` table to count attended meetings per person
    /// (powers the row's trailing label). Re-run when the population changes;
    /// failures degrade to no labels rather than surfacing an error.
    private func reloadMeetingCounts() {
        meetingCounts = (try? PersonAggregateResolver.meetingCounts(in: modelContext)) ?? [:]
    }
}

/// A single row in the people list: glass avatar pill + display name + a dense
/// secondary line (company · email) + a trailing meeting-count label. Liquid
/// language: DS type scale, hover wash on macOS, no chip chrome.
struct PersonListRow: View {
    let person: Person
    /// Attended-meeting count for the trailing label; resolved once via a batched
    /// fetch by the list. Defaults to 0 (no label) for reuse sites — e.g. the merge
    /// picker — that have no count to show.
    var meetingCount: Int = 0

    @State private var hovering = false

    var body: some View {
        HStack(spacing: DS.Space.s) {
            LiquidAvatar(name: displayName, size: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(displayName)
                    .font(DS.FontToken.body)
                    .foregroundStyle(DS.ColorToken.textPrimary)
                    .lineLimit(1)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(DS.FontToken.metadata)
                        .foregroundStyle(DS.ColorToken.textTertiary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: DS.Space.s)
            if meetingCount > 0 {
                Text(meetingLabel)
                    .font(DS.FontToken.metadata)
                    .monospacedDigit()
                    .foregroundStyle(DS.ColorToken.textTertiary)
                    .accessibilityLabel("\(meetingCount) \(meetingCount == 1 ? "meeting" : "meetings")")
            }
        }
        .padding(.horizontal, DS.Space.s)
        .padding(.vertical, DS.Space.xs)
        .background {
            RoundedRectangle(cornerRadius: DS.Radius.s, style: .continuous)
                .fill(hovering ? personRowHoverFill : .clear)
        }
        .contentShape(Rectangle())
        #if os(macOS)
        .onHover { value in
            withAnimation(DS.Motion.hover) { hovering = value }
        }
        #endif
    }

    private var displayName: String {
        person.displayName.isEmpty ? "Unnamed" : person.displayName
    }

    /// Secondary line: company/role joined with the first contact detail by a
    /// middot. Drops empty parts so a company-only or email-only person reads
    /// cleanly.
    private var subtitle: String {
        let company = person.company?.trimmingCharacters(in: .whitespacesAndNewlines)
        let contact = [person.email, person.phone]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
        return [company, contact]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    private var meetingLabel: String {
        meetingCount == 1 ? "1 meeting" : "\(meetingCount) meetings"
    }
}
