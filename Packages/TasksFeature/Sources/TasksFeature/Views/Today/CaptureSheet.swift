import NexusAI
import NexusCore
import NexusUI
import SwiftData
import SwiftUI

enum CaptureSheetIdiom {
    case desktop
    case touch
}

enum CaptureSheetChrome {
    static func keyboardHint(_ hint: String, idiom: CaptureSheetIdiom) -> String? {
        idiom == .desktop ? hint : nil
    }

    static func showsTopConfirmationAction(idiom: CaptureSheetIdiom) -> Bool {
        idiom == .desktop
    }

    static func showsTopCancellationAction(idiom: CaptureSheetIdiom) -> Bool {
        idiom == .touch
    }
}

public struct CaptureSheet: View {
    @Environment(\.aiRouter) private var aiRouter
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    private let onSaved: (() -> Void)?
    private let onCancelled: (() -> Void)?

    @State private var selectedMode: CapturePane.Mode
    @State private var digestText: String = ""
    @State private var digestTimestamp: Date = .now

    public init(
        initialMode: CapturePane.Mode = .task,
        onSaved: (() -> Void)? = nil,
        onCancelled: (() -> Void)? = nil
    ) {
        _selectedMode = State(initialValue: initialMode)
        self.onSaved = onSaved
        self.onCancelled = onCancelled
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    captureSection

                    CapturePane(
                        mode: selectedMode,
                        onSaved: handleSaved,
                        onCancelled: handleCancelled,
                        showsCancelAction: false
                    )

                    Divider()
                        .overlay(NexusColor.Line.hairline)

                    digestCard
                }
                .padding(.horizontal, contentPadding)
                .padding(.vertical, 16)
                .frame(maxWidth: contentMaxWidth, alignment: .topLeading)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle("Capture")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                if CaptureSheetChrome.showsTopCancellationAction(idiom: Self.currentIdiom) {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { handleCancelled() }
                    }
                }
                if CaptureSheetChrome.showsTopConfirmationAction(idiom: Self.currentIdiom) {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
            }
            .background(NexusWallpaper())
        }
        .task { await loadDigest() }
    }

    private var captureSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                // §3 value-changing de-hue: 0xF2F2F4 -> 0x8C8D96. The leading glyph is
                // part of the Text.tertiary eyebrow lockup (icon-eyebrow parity); a
                // decorative glyph must not carry Text.primary emphasis
                // (identity-glyph-is-not-Emphasis lock). Not a value-identical rename.
                Image(systemName: "bolt.fill")
                    .foregroundStyle(NexusColor.Text.tertiary)
                Text("CAPTURE")
                    .font(NexusType.eyebrow)
                    .foregroundStyle(NexusColor.Text.tertiary)
            }

            CapturePill(
                systemImage: "checkmark.square",
                label: "New task",
                kbdHint: CaptureSheetChrome.keyboardHint("T", idiom: Self.currentIdiom)
            ) {
                selectedMode = .task
            }
            CapturePill(
                systemImage: "mic",
                label: "Voice memo",
                kbdHint: CaptureSheetChrome.keyboardHint("V", idiom: Self.currentIdiom)
            ) {
                selectedMode = .voiceMemo
            }
        }
    }

    private func handleSaved() {
        onSaved?()
        dismiss()
    }

    private func handleCancelled() {
        onCancelled?()
        dismiss()
    }

    private var digestCard: some View {
        NexusCard(.elev1, padding: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    // §3 value-changing de-hue: 0xF2F2F4 -> 0x8C8D96. The leading glyph is
                    // part of the Text.tertiary eyebrow lockup (icon-eyebrow parity); a
                    // decorative glyph must not carry Text.primary emphasis
                    // (identity-glyph-is-not-Emphasis lock). Not a value-identical rename.
                    Image(systemName: "sparkles")
                        .foregroundStyle(NexusColor.Text.tertiary)
                    Text("MORNING DIGEST")
                        .font(NexusType.eyebrow)
                        .foregroundStyle(NexusColor.Text.tertiary)
                    Spacer()
                    Text(Self.timeFormatter.string(from: digestTimestamp))
                        .font(NexusType.mono)
                        .foregroundStyle(NexusColor.Text.muted)
                }

                DigestRenderer.render(digestText.isEmpty ? "Loading..." : digestText)
                    .font(NexusType.body)
                    .foregroundStyle(NexusColor.Text.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
        }
    }

    @MainActor
    private func loadDigest() async {
        let now = Date.now
        digestTimestamp = now
        guard let aiRouter, let input = try? Self.digestInput(now: now, modelContext: modelContext) else {
            digestText = ""
            return
        }
        let service = HeroBriefService(router: aiRouter)
        digestText = await service.brief(
            for: input.counts,
            firstTitles: input.firstTitles,
            now: now
        )
    }

    @MainActor
    private static func digestInput(now: Date, modelContext: ModelContext) throws -> DigestInput {
        let query = TodayQuery()
        let linkRepository = LinkRepository(context: modelContext)
        let archivedProjectIDs =
            (try? ProjectRepository(context: modelContext).archivedProjectIDs()) ?? []
        let overdue = try query.overdue(now: now, excludingProjectIDs: archivedProjectIDs)
            .apply(in: modelContext)
        let today = try query.today(now: now, excludingProjectIDs: archivedProjectIDs)
            .apply(in: modelContext)
        let noDate = try query.noDate(excludingProjectIDs: archivedProjectIDs)
            .apply(in: modelContext)
        let awaiting = try query.awaiting(
            now: now,
            modelContext: modelContext,
            linkRepository: linkRepository
        )
        return DigestInput(
            counts: HeroBriefService.Counts(
                overdue: overdue.count,
                today: today.count,
                noDate: noDate.count,
                awaiting: awaiting.count
            ),
            firstTitles: Array(today.prefix(3).map(\.title))
        )
    }

    private struct DigestInput {
        let counts: HeroBriefService.Counts
        let firstTitles: [String]
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private static var currentIdiom: CaptureSheetIdiom {
        #if os(iOS)
        .touch
        #else
        .desktop
        #endif
    }

    private var contentMaxWidth: CGFloat? {
        #if os(iOS)
        horizontalSizeClass == .regular ? 640 : nil
        #else
        nil
        #endif
    }

    private var contentPadding: CGFloat {
        #if os(iOS)
        horizontalSizeClass == .regular ? 24 : 16
        #else
        16
        #endif
    }
}
