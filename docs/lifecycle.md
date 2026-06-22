# Lifecycle source-of-truth reference

This document is the canonical answer to "which field wins?" for Projects, Tasks, and Cycles.
Read it when choosing between `projects.set_stage` vs `projects.set_status`, between
`tasks.set_workflow_state` vs `tasks.complete`/`reopen`, or when querying status in code.

---

## Projects

**Two overlapping lifecycle fields on `Project`:**

| Field | Type | Role |
|---|---|---|
| `stageRaw` (`Project.stage`) | `String?` | Granular pipeline position; `nil` when not placed on a typed pipeline |
| `statusRaw` (`Project.status`) | `String` | Coarse 5-state lifecycle (`backlog / planned / active / completed / cancelled`) |

### Which field is canonical?

- **Typed projects** (`type != .generic`): `stageRaw` is canonical. `statusRaw` is **derived** from it
  via `ProjectStage.coarseStatus` (`ProjectStage.swift:51–64`). The repository keeps the two in sync
  when a stage is set (`Project.swift:87–91`). Do **not** set `statusRaw` directly on a typed project
  — set the stage and let the sync handle it.
- **Generic projects** (`type == .generic`): No pipeline exists (`ProjectType.stages` returns `[]`),
  so `stageRaw` is always `nil`. `statusRaw` is the only lifecycle field and IS the source of truth.

### MCP tools

| Tool | What it touches |
|---|---|
| `projects.set_stage` | Sets `stageRaw`; derives and syncs `statusRaw` via `coarseStatus`. Use for typed projects. |
| `projects.set_status` | Sets `statusRaw` directly (coarse 5-state). Use for generic projects, or for multi-project bulk moves where you do not care about the granular stage. |

### `ProjectStage.coarseStatus` mapping (`ProjectStage.swift:51–64`)

| Stage | → `ProjectStatus` |
|---|---|
| `lead`, `qualifying`, `auditPlan`, `planning` | `planned` |
| `proposal`, `tender`, `kickoff`, `deliveryDocs`, `softwareDelivery`, `installation`, `asBuiltDocs`, `auditExecution`, `building`, `reviewing`, `support`, `training`, `acceptance` | `active` |
| `won`, `auditReport`, `shipped`, `closed` | `completed` |
| `lost` | `cancelled` |

---

## Tasks

**Two overlapping lifecycle fields on `TaskItem`:**

| Field | Type | Role |
|---|---|---|
| `workflowStateRaw` (`TaskItem.workflowState`) | `String?` | Tracker machine state (`backlog / todo / inProgress / inReview / done / canceled / duplicate`); `nil` for plain GTD tasks |
| `statusRaw` (`TaskItem.status`) | `String` | GTD coarse state (`open / done / snoozed`) |

### Which field is canonical?

- **Project tasks** (`workflowStateRaw != nil`): `workflowStateRaw` is canonical. `statusRaw` is
  **derived** from it via `WorkflowState.forcedStatus` (`WorkflowState.swift:38–45`). The repository
  reconciles the two in `TaskItemRepository` (see `reopen`, `markDone`, `completeTask`): setting a
  workflow state always writes the matching `statusRaw`. Do **not** set `statusRaw` independently on
  a project task.
- **GTD tasks** (`workflowStateRaw == nil`): No tracker machine. `statusRaw` is the only lifecycle
  field and IS the source of truth (invariant I7 in `WorkflowState.swift`).

### `WorkflowState.forcedStatus` mapping (`WorkflowState.swift:38–45`)

| `WorkflowState` | → `TaskStatus` |
|---|---|
| `backlog`, `todo`, `inProgress`, `inReview` | `open` |
| `done`, `canceled`, `duplicate` | `done` |

Note: `canceled` and `duplicate` are terminal non-completions — they force `status = .done` but
never set `lastCompletedAt`, so completion stats exclude them (`WorkflowState.isTerminalNonCompletion`).

### MCP tools

| Tool | What it touches |
|---|---|
| `tasks.set_workflow_state` | Sets `workflowStateRaw` and syncs `statusRaw`. Use for project tasks. |
| `tasks.complete` | Sets `statusRaw = .done` (and `workflowStateRaw = .done` if non-nil). Operates on `statusRaw`. |
| `tasks.reopen` | Sets `statusRaw = .open` (and `workflowStateRaw = .todo` if non-nil). Operates on `statusRaw`. |

---

## Cycles

**`Cycle` has a single independent lifecycle field:**

| Field | Type | Role |
|---|---|---|
| `statusRaw` (`Cycle.status`) | `String` | `upcoming / active / completed` — manual only, no derivation |

Cycles are **not** linked to projects or notes via `LinkKind`. Tasks belong to a cycle via the
raw FK `TaskItem.cycleID` (same pattern as `TaskItem.projectID` — no SwiftData `@Relationship`).
A dangling `cycleID` after a cycle soft-delete reads as "no cycle" at read time (invariant I-C1
in `Cycle.swift`).

### MCP tools

| Tool | What it touches |
|---|---|
| `cycles.set_status` | Sets `statusRaw` directly. |
| `cycles.assign_task` | Writes `TaskItem.cycleID` (the FK pointer). |

---

## Quick-decision flowchart

```
Want to advance a project?
  ├── project.type != .generic  →  projects.set_stage   (stageRaw drives statusRaw)
  └── project.type == .generic  →  projects.set_status  (statusRaw is the only field)

Want to close/advance a task?
  ├── task.workflowState != nil  →  tasks.set_workflow_state  (drives statusRaw)
  └── task.workflowState == nil  →  tasks.complete / tasks.reopen  (pure GTD)

Want to advance a cycle?  →  cycles.set_status  (independent, manual)
```
