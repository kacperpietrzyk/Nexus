# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres
to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.4.2] - 2026-06-29

### Added
- **Record a meeting without picking a window.** Manual **Record Meeting…** now captures
  system audio through a global tap (excluding Nexus' own output), so you no longer get a
  screen/window picker before recording starts.
- **Tasks can carry a real event date.** A task can now record when something actually
  happened, separate from when it was created — so back-dating an item no longer distorts
  its creation time. Ordering and listing fall back to the creation date when no event
  date is set.

### Changed
- **More capable assistant access to your projects and tasks (MCP).** New read tools give
  the assistant a full project overview and surface archived projects and orphaned tasks,
  a merge tool folds a duplicate task into another (carrying over its links, subtasks and
  dates), and notes/meetings can be linked to a project with a dedicated relationship.

### Fixed
- **Assistant reliability.** Concurrent assistant sessions no longer block each other, the
  tool list recovers when the helper starts before its tools are ready, write bursts no
  longer trigger redundant refreshes, and duplicate "ghost" rows from sync are filtered
  out of meeting and link results.

## [0.4.1] - 2026-06-22

### Fixed
- **Meeting recording works again.** The background helper that detects meetings and
  records them was crashing the instant it launched on release builds, which silently
  broke both automatic detection (no prompt when a Teams/Zoom meeting started) and the
  manual **Record Meeting…** command. The helper now opens its shared local store without
  standing up a second iCloud sync engine it isn't entitled to use; your data still syncs
  through the main app as before.

## [0.4.0] - 2026-06-20
A sweeping interface pass across every module — Today, Calendar, Meetings, Projects,
Tasks, Notes and navigation — plus a new knowledge graph, an activity feed in place of
the old Inbox, and system-wide bulk actions. Most of the visual rework lands on the Mac
app first.

### Added
- **Knowledge graph.** A reusable, interactive constellation graph that draws the
  relationships between your notes, meetings, people and projects. Meetings and Notes
  both render it — an ego-graph around the item you're viewing (concentric rings around a
  focused center) and a force-directed view for the wider picture.
- **Activity Feed.** The Inbox is reborn as an activity feed: AI/agent proposals and
  meeting captures land here as a single chronological stream, with a one-tap bridge to
  turn unscheduled items into tasks.
- **Bulk actions, context menus, copy and undo** across Tasks, Inbox, Notes, People and
  Meetings — multi-select, right-click menus, copy-to-clipboard, and undo for destructive
  edits.

### Changed
- **An interface pass across every module** (most visible on the Mac app):
  - **Today** — the Daily Brief now shows the canonical, synced note instead of an
    in-memory regeneration, and the toolbar is decluttered.
  - **Calendar** — multi-day events render as spanning bars, a single unified panel
    replaces the old multi-column layout, the Month view is informative, and you can drag
    a task onto a slot to schedule it.
  - **Meetings** — the five-column layout collapses into one panel that hides what's
    empty, with first-class speaker assignment and in-place rename, related notes and a
    collision-safe mini-graph, and cleaner topic extraction.
  - **Projects** — the picker, roadmap and pipeline surfaces are fed real data: key dates
    become roadmap spans with markers, id-derived shapes, drag-to-stage in the pipeline,
    header quick-edit, and Overview empty states.
  - **Tasks** — a project pill on each row, a Group-by switch (project / date / priority),
    a Classification card for tags and labels, and Pin-to-Today.
  - **Notes** — a two-pane navigator with a document-style editor: focus-to-edit blocks,
    a Notion-style drag gutter, inline note properties, and pinned/recent entry points.
  - **Navigation** — a single clickable breadcrumb replaces seven inconsistent back
    behaviors, with deep links, ⌘[ / ⌘] history, and a command palette.

### Fixed
- **Navigating the app no longer lags as data grows.** Today, Inbox and Tasks stopped
  re-materializing their entire dataset on every navigation, and the longest lists are
  now windowed, so moving around stays smooth on large libraries.

## [0.3.3] - 2026-06-16
Adds on-device meeting summaries with manual recording, a local Obsidian vault
importer, and back-datable MCP task creation; fixes device-tier model selection on
8 GB iPhones and unblocks the CI lint gate.

### Added
- **On-device meeting summaries with manual recording.** Meetings now summarize on
  device first: the helper transcribes and hands the transcript to the app, where the
  resident Gemma assistant model writes the summary and action items, falling back to
  Apple Intelligence if the model can't produce one within ~25 s. A manual record
  button lets you start a recording from the system picker without granting
  Accessibility, and the app now actively prompts for Accessibility permission (once)
  when automatic meeting detection needs it.
- **Import an Obsidian vault.** A new importer (Settings → Advanced, next to Export
  on macOS) reads `.md` files straight from disk and creates Nexus notes locally —
  no network, no LLM. It strips leading YAML frontmatter, preserves the vault's
  folder layout, maps `90 - Templates` to the template role, and skips hidden
  entries (`.obsidian`) and non-markdown files. A two-phase flow scans and shows a
  create-vs-skip preview before any write; the import is idempotent and resume-safe,
  so re-running only adds what's missing. Because the note body never passes through
  a model, content the usage-policy classifier blocks during MCP/agent writes
  imports cleanly.
- **Back-dated task creation over MCP.** The MCP task-creation tools now accept an
  explicit `created_at`, so an agent importing historical items can preserve their
  original chronology instead of stamping everything with the import time.

### Fixed
- **8 GB iPhones were missing the Assistant model.** Device tiering floored the
  reported RAM (iOS reports ~7.98 GiB, which truncated to 7 and failed the `>= 8`
  check), so 8 GB iPhones only offered the Search model. Memory is now rounded to the
  nearest gigabyte, and the iOS RAM floor was lowered to 7 GB so selection no longer
  depends on the under-report.
- **CI lint gate was stuck red.** A multi-line `if` condition in `TierDetector`
  deadlocked swift-format (which wanted the brace on its own line) against SwiftLint
  (which wanted it on the same line), keeping the Lint job red since 0.3.1.
  Collapsing the condition to a single line satisfies both with no behavior change.

## [0.3.2] - 2026-06-16
Stability fixes for heavy and automated use of the MCP server, plus a more honest
daily brief.

### Fixed
- **The app could be terminated during a burst of writes.** Rapid back-to-back
  changes — for example an MCP/agent bulk import — re-ran the Today reload, and with
  it the on-device AI brief, on *every single save*. That dirtied gigabytes of memory
  until macOS resource-killed the app ("Nexus quit unexpectedly"). Store-change
  reloads are now coalesced, so a burst of writes triggers a single refresh once the
  writes settle.
- **The daily brief could invent tasks.** The offline brief sometimes regurgitated a
  hard-coded example ("review Sam's PR") or hallucinated unrelated work. It is now
  grounded strictly on your real tasks and told not to invent any.
- **Tasks were listed twice over MCP.** The MCP task list now collapses CloudKit
  "ghost" duplicate rows by id, matching what the app's own task views already showed.

## [0.3.1] - 2026-06-16
A focused fix for the on-device assistant: 0.3.0 shipped a chat-model entry that
could neither download nor load, so the assistant silently never updated.

### Fixed
- **On-device chat model wouldn't download or load.** The macOS catalog pointed at a
  non-existent Hugging Face repo (HTTP 401), and every Gemma-4 12B build uses an
  architecture (`gemma4_unified`) the bundled MLX runtime can't load. Replaced with
  loadable, RAM-tiered Gemma 4 models: a 26B/A4B mixture-of-experts on Macs with
  ≥24 GB RAM and the compact E4B below that (and on iPhone/iPad).
- **Misleading model status.** A leftover older model no longer makes a genuinely
  missing model read as "Updating…", and the readiness summary no longer shows a
  false-green "Assistant ready" when required models are absent.

### Added
- **Settings → Models** now has per-model Download / Retry / Update actions with live
  progress — including on iPhone/iPad, which previously had no in-app way to fetch the
  assistant model.

## [0.3.0] - 2026-06-15
The big redesign-and-intelligence release (PR #78). A new design system across every platform,
the on-device AI assistant, and an expanded MCP server. The AI is experimental.

### Added
- **On-device AI assistant** (experimental) — daily brief, task assist, a tool-using agent
  chat, and insights, running on local Gemma-class models via MLX with a propose-confirm
  flow; cloud calls remain opt-in and quota-gated.
- **MCP server** expanded to 100+ tools across tasks, notes, meetings, projects, calendar
  and people (links, reorder, complete modes, duplicate suggestions, restore/trash,
  meetings CRUD, attachments, recurrence anchors).
- **Projects** universal types — sections, cycles, stages, and key dates.
- **Notes** — `[[wiki-links]]`, tables, and trash/restore.

### Changed
- New **Liquid** design system across Mac, iPhone, iPad and Watch.
- iPhone, iPad and Watch brought up to feature parity with macOS.

### Fixed
- Release-only export crash, MLX idle recovery, and model-catalog IDs (#58).
- MCP sidecar sandbox launch and agent-tools socket transport (#64, #67).
- Production APNs entitlements for Release builds on Mac and Watch (#41, #43, #44).

## [0.2.0] - 2026-06-09
Nexus grows beyond Tasks: the Calendar, Meetings, Notes, Projects and People modules join
the app, alongside a Linear-inspired redesign and a broad correctness pass.

### Added
- **Calendar** — events with recurrence and alarms, day planning, and a deadline-risk
  signal surfaced in Today and the task inspector.
- **Meetings** — capture, transcription, summaries, and action items, with guided
  permissions and a model healthcheck (#74).
- **Notes** — Markdown notes with task round-trip and daily-brief notes.
- **Projects** — promote tasks into projects.
- **People** — a lightweight personal CRM.
- **Tasks** — Todoist write parity.

### Changed
- Linear-inspired redesign (#49); the app is pinned to dark mode across Mac and iOS.

### Fixed
- Broad correctness pass across calendar (recurrence, alarms, overlapping events, span
  choices on edit/delete), the scheduler (capped backoff, only rolling genuinely overdue
  tasks), the agent (no duplicate brief tasks, graph-edge validation), meetings (speaker
  selection, diacritic-insensitive search), notes/export Markdown round-trips, search
  indexing of notes/labels/people, and recurring-task occurrences.

## [0.1.0] - 2026-05-21
### Added
- First TestFlight beta: tasks (quick capture ⌘N, Today, Inbox), Mac/iPhone/iPad/Watch,
  CloudKit sync, on-device AI assist, MCP external access (Mac).

[Unreleased]: https://github.com/kacperpietrzyk/Nexus/compare/v0.4.2...HEAD
[0.4.2]: https://github.com/kacperpietrzyk/Nexus/compare/v0.4.1...v0.4.2
[0.4.1]: https://github.com/kacperpietrzyk/Nexus/compare/v0.4.0...v0.4.1
[0.4.0]: https://github.com/kacperpietrzyk/Nexus/compare/v0.3.3...v0.4.0
[0.3.3]: https://github.com/kacperpietrzyk/Nexus/compare/v0.3.2...v0.3.3
[0.3.2]: https://github.com/kacperpietrzyk/Nexus/compare/v0.3.1...v0.3.2
[0.3.1]: https://github.com/kacperpietrzyk/Nexus/compare/v0.3.0...v0.3.1
[0.3.0]: https://github.com/kacperpietrzyk/Nexus/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/kacperpietrzyk/Nexus/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/kacperpietrzyk/Nexus/releases/tag/v0.1.0
