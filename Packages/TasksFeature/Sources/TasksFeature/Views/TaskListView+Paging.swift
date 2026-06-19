import Foundation
import NexusCore
import SwiftData
import SwiftUI

// Windowed-loading helpers for `TaskListView`, split out of TaskListView.swift to
// keep that file under the file-length / type-body budget (the +FilterQueries /
// +Refinement precedent). Only the `.all` flat list and the Today `noDate` bucket
// page; everything else loads fully. Methods are `internal` (same module) so the
// view body and `reload()` can call them.
extension TaskListView {

    /// Whether the current filter pages incrementally. Only the high-volume,
    /// purely DB-sorted filters window — and only when no in-list refinement is
    /// active (an active label/agent refinement shrinks the result to a small set
    /// and post-filters in memory, which would make a fixed-size page undershoot;
    /// the non-windowed full load is correct there).
    @MainActor
    var isWindowing: Bool {
        guard !refinement.isActive else { return false }
        switch filter {
        case .all:
            // `.all` pages by default, but an active group-by must section the
            // FULL result set — a 50-item window would show partial sections.
            // So when grouping, drop windowing and load everything.
            return groupBy.wrappedValue == .none
        case .today:
            return true
        default:
            return false
        }
    }

    /// The Today "No date" section. When windowing it carries the prefetch trigger
    /// + capped stagger; otherwise it's the plain section (refinement active /
    /// non-Today paths never reach here, but the fall-through keeps it honest).
    @ViewBuilder
    var noDateSection: some View {
        if isWindowing {
            if !noDate.isEmpty {
                Section {
                    ForEach(Array(noDate.enumerated()), id: \.element.id) { index, item in
                        windowedRow(for: item, index: index, loadedCount: noDate.count)
                    }
                } header: {
                    sectionHeader("NO DATE")
                }
            }
        } else {
            section("No date", items: noDate)
        }
    }

    /// A row in a windowed stream: capped enter stagger (so appended pages don't
    /// inherit multi-second delays) plus an `.onAppear` prefetch trigger near the
    /// loaded tail.
    @ViewBuilder
    func windowedRow(for item: TaskItem, index: Int, loadedCount: Int) -> some View {
        row(for: item, appearIndex: TaskListPageState.cappedAppearIndex(index))
            .onAppear { loadMoreIfNeeded(appearedIndex: index, loadedCount: loadedCount) }
    }

    /// First windowed page (50) of the `.all` flat list; primes the flat cursor.
    /// Drains forward past any fully-filtered leading raw pages so the first page
    /// shown is never empty while rows still remain (otherwise the empty-state
    /// could show with no row left to fire the scroll trigger).
    @MainActor
    func loadFirstFlatPage() throws -> [TaskItem] {
        var items: [TaskItem] = []
        repeat {
            let page = try Self.allTasksPage(
                rawOffset: pageState.flatCursor,
                rawLimit: TaskListPageState.firstPageSize,
                modelContext: modelContext
            )
            pageState.flatCursor = page.rawCursor
            pageState.flatHasMore = page.hasMore
            items.append(contentsOf: page.items)
        } while items.isEmpty && pageState.flatHasMore
        return items.dedupedByID()
    }

    /// First windowed page (50) of the Today `noDate` bucket; primes its cursor.
    /// `noDate` rows are already roots (predicate-hoisted), so no `rootTasks`
    /// reduction is needed — that keeps the page size honest. Drains past
    /// fully-filtered leading raw pages (see `loadFirstFlatPage`).
    @MainActor
    func loadFirstNoDatePage(archivedProjectIDs: Set<UUID>) throws -> [TaskItem] {
        let bucket = TodayQuery().noDateRoots(excludingProjectIDs: archivedProjectIDs)
        var items: [TaskItem] = []
        repeat {
            let page = try bucket.page(
                in: modelContext,
                rawOffset: pageState.noDateCursor,
                rawLimit: TaskListPageState.firstPageSize
            )
            pageState.noDateCursor = page.rawCursor
            pageState.noDateHasMore = page.hasMore
            items.append(contentsOf: page.items)
        } while items.isEmpty && pageState.noDateHasMore
        return items.dedupedByID()
    }

    /// Scroll-triggered append: when a row within `prefetchMargin` of the loaded
    /// tail appears, fetch the next page (`pageSize`) and append it. Re-entrancy is
    /// guarded by `pageState.isLoadingMore`. No-op when not windowing or exhausted.
    @MainActor
    func loadMoreIfNeeded(appearedIndex index: Int, loadedCount: Int) {
        guard isWindowing, pageState.hasMore, !pageState.isLoadingMore else { return }
        guard index >= loadedCount - TaskListPageState.prefetchMargin else { return }
        pageState.isLoadingMore = true
        defer { pageState.isLoadingMore = false }
        do {
            switch filter {
            case .all:
                try appendFlatPage()
            case .today:
                try appendNoDatePage()
            default:
                break
            }
            // Subtask progress must cover the freshly-appended rows too.
            subtaskProgressByTaskID = try SubtaskTreeDataSource.progress(
                for: visibleRootTasks,
                modelContext: modelContext
            )
        } catch {
            self.error = String(describing: error)
        }
    }

    @MainActor
    private func appendFlatPage() throws {
        guard pageState.flatHasMore else { return }
        let page = try Self.allTasksPage(
            rawOffset: pageState.flatCursor,
            rawLimit: TaskListPageState.pageSize,
            modelContext: modelContext
        )
        pageState.flatCursor = page.rawCursor
        pageState.flatHasMore = page.hasMore
        flatList = (flatList + page.items).dedupedByID()
    }

    @MainActor
    private func appendNoDatePage() throws {
        guard pageState.noDateHasMore else { return }
        let archivedProjectIDs =
            (try? ProjectRepository(context: modelContext).archivedProjectIDs()) ?? []
        let bucket = TodayQuery().noDateRoots(excludingProjectIDs: archivedProjectIDs)
        let page = try bucket.page(
            in: modelContext,
            rawOffset: pageState.noDateCursor,
            rawLimit: TaskListPageState.pageSize
        )
        pageState.noDateCursor = page.rawCursor
        pageState.noDateHasMore = page.hasMore
        noDate = (noDate + page.items).dedupedByID()
    }
}
