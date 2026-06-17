import NexusCore
import NexusUI
import SwiftUI

extension TodayDashboard {
    @ViewBuilder
    func scheduleTimeline(
        slots: [(Date, [ScheduleItem])],
        unscheduled: [TaskItem],
        now: Date
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            scheduleHeader

            if slots.isEmpty, unscheduled.isEmpty {
                emptyScheduleCard
            } else {
                scheduleSlotList(slots: slots, now: now)
                unscheduledSection(unscheduled, now: now)
            }

            eveningShutdownCard(now: now)
        }
    }

    /// Evening shutdown (spec §10): after 17:00 local, a glance card summarising
    /// what got done today vs what is still open. Reuses the NexusCore
    /// `EveningShutdownSummary` (no CalendarFeature import).
    @ViewBuilder
    func eveningShutdownCard(now: Date) -> some View {
        let hour = Calendar.current.component(.hour, from: now)
        if hour >= 17 {
            let summary = EveningShutdownSummary.make(
                from: Self.shutdownTasks(now: now, modelContext: modelContext),
                now: now,
                calendar: .current
            )
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: "moon.stars")
                        .foregroundStyle(NexusColor.Text.secondary)
                    Text("Evening shutdown")
                        .font(NexusType.bodySmall.weight(.semibold))
                        .foregroundStyle(NexusColor.Text.primary)
                    Spacer()
                }
                Text(
                    summary.isClear
                        ? "\(summary.completedCount) done today · all caught up"
                        : "\(summary.completedCount) done · \(summary.remainingCount) still open"
                )
                .font(NexusType.caption)
                .foregroundStyle(NexusColor.Text.tertiary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(NexusColor.Background.raised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(NexusColor.Line.hairline, lineWidth: 1)
            }
            .padding(.top, 12)
        }
    }

    private var scheduleHeader: some View {
        HStack(spacing: 8) {
            Text("Schedule")
                .font(NexusType.h3)
                .foregroundStyle(NexusColor.Text.primary)

            NexusBadge("Today", tone: .muted)

            Spacer()

            Button {
                planMyDay()
            } label: {
                Label("Plan my day", systemImage: "sparkles")
                    .font(NexusType.caption.weight(.semibold))
                    .foregroundStyle(NexusColor.Accent.limeInk)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(NexusColor.Accent.lime, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Plan my day")
        }
        .padding(.bottom, 10)
    }

    private var emptyScheduleCard: some View {
        NexusCard(.elev1, padding: 14) {
            Text("No scheduled blocks yet")
                .nexusType(.bodySmall)
                .foregroundStyle(NexusColor.Text.tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func scheduleSlotList(slots: [(Date, [ScheduleItem])], now: Date) -> some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(NexusColor.Line.hairline)
                .frame(width: 1)
                .padding(.leading, 53)

            VStack(alignment: .leading, spacing: 0) {
                ForEach(slots, id: \.0) { slot, items in
                    let isCurrent = items.contains { ScheduleGrouping.isCurrent(item: $0, now: now) }

                    NexusTimeRow(Self.scheduleTimeFormatter.string(from: slot), isCurrent: isCurrent) {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(items) { item in
                                scheduleCard(for: item, now: now)
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func unscheduledSection(_ tasks: [TaskItem], now: Date) -> some View {
        if !tasks.isEmpty {
            Divider()
                .padding(.vertical, 12)

            Text("Unscheduled")
                .font(NexusType.eyebrow)
                .foregroundStyle(NexusColor.Text.muted)
                .padding(.bottom, 6)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(tasks, id: \.id) { task in
                    compactTaskCard(task: task, now: now)
                }
            }
        }
    }

    @ViewBuilder
    private func scheduleCard(for item: ScheduleItem, now: Date) -> some View {
        switch item {
        case .task(let task):
            compactTaskCard(task: task, now: now)
        case .meeting(let event):
            MeetingCard(event: event, isCurrent: ScheduleGrouping.isCurrent(item: item, now: now))
        case .block(let block):
            scheduledBlockCard(block: block)
        }
    }

    /// Renders a Calendar/Motion-AI `ScheduledBlock` on the Today rail (spec §7).
    /// Proposed blocks carry accept (✓) / reject (✗) controls; accepted blocks
    /// read as a solid lime-edged surface. Mutations go through the NexusCore
    /// `ScheduledBlockRepository` + `CalendarSyncReconciler` (no CalendarFeature
    /// import).
    private func scheduledBlockCard(block: ScheduledBlock) -> some View {
        let isProposed = block.status == .proposed
        return HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(isProposed ? NexusColor.Text.tertiary : NexusColor.Accent.lime)
                .frame(width: 3)
                .padding(.vertical, 1)

            VStack(alignment: .leading, spacing: 4) {
                Text(block.title.isEmpty ? "Scheduled" : block.title)
                    .nexusType(.bodySmall)
                    .foregroundStyle(NexusColor.Text.primary)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    NexusBadge(blockTimeRange(block), tone: .muted)
                    NexusBadge(isProposed ? "Proposed" : "Scheduled", tone: isProposed ? .muted : .acc)
                }
            }

            Spacer(minLength: 8)

            if isProposed {
                HStack(spacing: 6) {
                    Button {
                        acceptBlock(block)
                    } label: {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(NexusColor.Accent.limeInk)
                            .frame(width: 22, height: 22)
                            .background(NexusColor.Accent.lime, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Accept block \(block.title)")

                    Button {
                        rejectBlock(block)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(NexusColor.Text.secondary)
                            .frame(width: 22, height: 22)
                            .background(NexusColor.Background.control, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Reject block \(block.title)")
                }
            }
        }
        .padding(12)
        .background(
            (isProposed ? NexusColor.Background.panel.opacity(0.7) : NexusColor.Background.control),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay {
            if isProposed {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(NexusColor.Line.strong, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            } else {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(NexusColor.Accent.lime.opacity(0.5), lineWidth: 1)
            }
        }
    }

    private func blockTimeRange(_ block: ScheduledBlock) -> String {
        "\(Self.scheduleTimeFormatter.string(from: block.start))–\(Self.scheduleTimeFormatter.string(from: block.end))"
    }

    // MARK: - Block actions (spec §7)

    func acceptBlock(_ block: ScheduledBlock) {
        guard let writer = calendarWriter else { return }
        let context = modelContext
        _Concurrency.Task { @MainActor in
            let reconciler = CalendarSyncReconciler(context: context, writer: writer)
            _ = try? await reconciler.accept(block)
            deadlineRiskModel.markDirty()
            await reloadScheduleData()
        }
    }

    func rejectBlock(_ block: ScheduledBlock) {
        let repository = ScheduledBlockRepository(context: modelContext)
        // Tear down the mirror event for an accepted block first, so rejecting it
        // never orphans an event in the "Nexus" calendar — mirrors
        // `ScheduleRejectBlockTool` and the accept path above. Best-effort.
        let eventID = block.externalEventID
        let writer = calendarWriter
        try? repository.softDelete(block)
        _Concurrency.Task { @MainActor in
            if let eventID, let writer {
                try? await writer.deleteEvent(id: eventID)
            }
            deadlineRiskModel.markDirty()
            await reloadScheduleData()
        }
    }

    /// Morning "Plan my day" (spec §10): run the shared NexusCore `DayPlanner`
    /// over today's candidates + calendar obstacles, persist proposals, and reload.
    func planMyDay() {
        let context = modelContext
        let provider = calendarProvider
        let enabled = calendarEventsEnabled
        _Concurrency.Task { @MainActor in
            let now = Date.now
            let events = await Self.calendarEvents(now: now, enabled: enabled, provider: provider)
            let prefs = UserDefaultsCalendarPreferencesStore().load()
            let planner = DayPlanner(context: context)
            _ = try? planner.planDay(events: events, prefs: prefs, now: now, calendar: .current)
            deadlineRiskModel.markDirty()
            await reloadScheduleData()
        }
    }

    private func compactTaskCard(task: TaskItem, now: Date) -> some View {
        Button {
            onOpenTask?(task)
        } label: {
            HStack(alignment: .top, spacing: 10) {
                NexusStatusGlyph(taskNexusStatus(for: task.status))
                    .padding(.top, 3)  // .top-aligned HStack: nudge 12pt glyph to bodySmall cap-height

                VStack(alignment: .leading, spacing: 4) {
                    Text(task.title)
                        .nexusType(.bodySmall)
                        .foregroundStyle(NexusColor.Text.primary)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        if let startAt = task.startAt {
                            NexusBadge(Self.scheduleTimeFormatter.string(from: startAt), tone: .muted)
                        }

                        if task.priority != .none {
                            NexusBadge("P\(task.priority.rawValue)", tone: .acc)
                        }
                    }
                }

                Spacer(minLength: 8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(NexusColor.Background.raised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(NexusColor.Line.hairline, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open task \(task.title)")
    }

    private static let scheduleTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}
