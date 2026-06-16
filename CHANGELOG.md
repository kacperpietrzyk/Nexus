# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres
to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.3.3] - 2026-06-16
Adds a local Obsidian vault importer and unblocks the CI lint gate.

### Added
- **Import an Obsidian vault.** A new importer (Settings → Advanced, next to Export
  on macOS) reads `.md` files straight from disk and creates Nexus notes locally —
  no network, no LLM. It strips leading YAML frontmatter, preserves the vault's
  folder layout, maps `90 - Templates` to the template role, and skips hidden
  entries (`.obsidian`) and non-markdown files. A two-phase flow scans and shows a
  create-vs-skip preview before any write; the import is idempotent and resume-safe,
  so re-running only adds what's missing. Because the note body never passes through
  a model, content the usage-policy classifier blocks during MCP/agent writes
  imports cleanly.

### Fixed
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

[Unreleased]: https://github.com/kacperpietrzyk/Nexus/compare/v0.3.0...HEAD
[0.3.0]: https://github.com/kacperpietrzyk/Nexus/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/kacperpietrzyk/Nexus/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/kacperpietrzyk/Nexus/releases/tag/v0.1.0
