# Circleback MCP-dump procedure

Circleback ships no user-facing meeting export (scout 2026-05-15). To bring
historical meetings into Nexus we run a **one-shot MCP-dump session** that
calls the Circleback MCP tools and writes a Nexus-format export bundle to
disk. The bundle is then fed to `Settings → Meetings → Import from Circleback…`
on the Mac app.

This README is the procedure document referenced by
`docs/superpowers/plans/2026-05-14-nexus-phase-1j-meetings-import.md`,
Task 0.

## When to run

- Once, when bringing your historical Circleback meetings into a fresh
  Nexus install.
- Again whenever you want to re-sync with new meetings since the last dump
  (the importer is idempotent — re-imports skip records whose
  `externalSourceID` already exists, identified by the canonical
  `circleback:meeting:<id>` / `circleback:actionItem:<id>` string).

## Prerequisites

- A separate Claude Code session with the **Circleback MCP server** enabled.
  Do NOT run this in the same session as the Nexus importer development —
  the importer TDD must run against the sanitized fixtures committed under
  `Packages/NexusMeetings/Tests/NexusMeetingsTests/Import/Fixtures/`, not
  against live data.
- A logged-in Circleback account whose meetings should be exported. The
  `SearchActionItems` tool defaults to `assigneeProfileId = user`; that
  default is preserved (third-party action items are out of scope).

## Output layout

```
~/Nexus-Circleback-Export/<YYYY-MM-DD>/
├── manifest.json
├── meetings/
│   └── <numeric-id>.json (one per meeting)
├── transcripts/
│   └── <linkId>.json (one per meeting that has a transcript)
└── action-items.json
```

The folder is the user's live data — **NOT committed to the repo**. Only
sanitized fixtures land in `Tests/`.

## Procedure (run in the MCP-enabled Claude Code session)

1. **Create the target folder tree** at
   `~/Nexus-Circleback-Export/<today>/` with empty `meetings/` and
   `transcripts/` subdirectories.

2. **Enumerate meetings.** Loop
   `SearchMeetings(pageIndex: 0, 1, 2, …)` until a page returns fewer
   than 20 items. Collect `{ id, linkId, title, createdAt }` from every
   result into the in-progress manifest. Persist the running list to
   disk after each page so the dump survives interruption.

3. **Hydrate each meeting.** For every collected `id`, call
   `ReadMeetings(meetingIds: [id, …])` in batches of up to 50. Write each
   per-meeting object to `meetings/<numeric-id>.json`, **fusing in the
   `linkId`** carried over from step 2 (because `ReadMeetings` itself does
   not return `linkId`).

4. **Pull transcripts.** For every `linkId`, call
   `GetTranscriptsForMeetings(meetingIds: [linkId, …])` in batches of up
   to 50. Write each transcript verbatim to
   `transcripts/<linkId>.json`. Skip meetings whose transcript call
   returns an empty payload (e.g., meetings still processing).

5. **Pull action items.** Loop
   `SearchActionItems(pageIndex: 0, 1, …, status: "PENDING")`, then again
   with `status: "DONE"`, until both pageIndices are exhausted. Merge both
   lists into `action-items.json` with the envelope
   `{ "schemaVersion": 1, "exportedAt": "<now ISO 8601>", "items": [ … ] }`.

6. **Write the manifest.** Top-level keys: `schemaVersion: 1`,
   `source: "circleback-mcp"`, `exportedAt: "<now ISO 8601>"`,
   `counts: { meetings, transcripts, actionItems }`, and the meeting
   index from step 2.

7. **Validate counts before handing the bundle to the importer:**
   - `len(manifest.meetings) == len(meetings/*.json)`
   - `len(transcripts/*.json) ≤ len(manifest.meetings)` (some meetings may
     be empty)
   - For each `actionItem.meeting.id`, that meeting MUST exist in
     `manifest.meetings`, or the orphan MUST be logged.

## Sanitization checklist (when creating test fixtures)

Pick a small subset (2 meetings + their transcripts + ~5 action items) and
sanitize before committing to
`Packages/NexusMeetings/Tests/NexusMeetingsTests/Import/Fixtures/nexus-export/`:

- Replace every real attendee name with `Participant N` (keep speaker
  continuity across the transcript).
- Replace every customer / company name with neutral placeholders
  (`CustomerCo`, `VendorA-N`).
- Replace any email with `pN@example.com`; phone numbers normalised.
- Trim each transcript to ≤30 segments to keep fixtures small.
- Keep at least one `DONE` and one `PENDING` action item to drive
  status-mapping tests.
- Keep at least one meeting whose nested action items are NOT in the
  global `action-items.json` list, to drive the importer's fallback-path
  test (Task 3).

## Schema-drift guardrail

If Circleback MCP tooling changes shape (renames a field, adds a new
required field), the dump output will diverge from
`Packages/NexusMeetings/Sources/NexusMeetings/Import/NexusExportFormat.swift`
and the importer will skip the unrecognized records with a logged reason.
**Update the parser first, then re-run the dump.** Do not edit the bundle
by hand to make it parse — the parser is the source of truth for the
bundle shape, and the bundle itself is throwaway data.

## What this dump deliberately does NOT do

- It does **not** download audio. The Circleback MCP server has no audio
  endpoint; audio is permanently absent from imported meetings, and that
  is by design (spec §9.3).
- It does **not** re-run AI extraction on transcripts. Action items come
  verbatim from Circleback. If you want a re-extraction, trigger it
  manually from the Meeting detail "Re-process" button after the import.
- It does **not** import other users' action items. The MCP default
  (`assigneeProfileId = user`) is preserved.
- It is **not** a Swift CLI — building one would require an MCP client
  SDK in Swift, which Nexus does not have. The dump is a one-shot Claude
  Code session that drives the MCP tools and writes files. If a
  reproducible local CLI is ever wanted, it lands as a separate spec.
