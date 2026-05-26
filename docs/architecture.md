# Nexus Architecture

Nexus is an all-in-one personal productivity app for the Apple ecosystem
(Mac · iPhone · iPad · Watch). It is **single-user**, **local-first**
(SwiftData + CloudKit private database), and **AI-augmented** (on-device first,
cloud opt-in). It's a native Swift/SwiftUI modular monolith built from feature
packages.

## Design principles

- **Single-user by design.** No sharing, accounts, auth, or permissions. If a
  feature seems to need multi-user, it's out of scope.
- **Local-first.** Data lives on-device in SwiftData and syncs through the
  user's own CloudKit private database. There is no app-operated backend.
- **AI on-device first.** AI features run locally by default; any cloud call
  requires explicit user consent and a quota preflight.
- **Anti-lock-in.** Every item can be exported to Markdown.

## The five layers (top → bottom)

```
Apps            NexusMac · NexusiOS · NexusWatch  (thin shells)
Feature modules TasksFeature · … (independent; talk only via the Link graph)
Core            NexusCore  (pure domain: Link, repos, search, scheduler, export)
Persistence     NexusSync  (SwiftData + CloudKit mirror, schema, migrations)
Adapters        NexusAI · NexusUI · NexusSearch  (providers behind protocols)
```

1. **Apps** (`Apps/NexusMac`, `Apps/NexusiOS`, `Apps/NexusWatch`) — thin shells:
   a composition root that wires dependencies plus platform glue (menu bar,
   App Intents, widgets, complications, share extension). No business logic.
2. **Feature modules** (`Packages/TasksFeature`, and siblings) — self-contained
   feature packages. They are **independent**: they do not import each other and
   communicate only through the `Link` graph in core.
3. **Core** (`Packages/NexusCore`) — the pure-Swift domain: the `Link` graph,
   `Linkable`/`Searchable` protocols, repositories, the search index, the
   scheduler, the Markdown exporter, tombstone purging. No UIKit/AppKit;
   fully unit-testable.
4. **Persistence & Sync** (`Packages/NexusSync`) — SwiftData models, the CloudKit
   mirror and conflict handling. Owns the versioned schema, the migration plan,
   and the model-container factory.
5. **Adapters** (`Packages/NexusAI`, `Packages/NexusUI`, `Packages/NexusSearch`)
   — capabilities behind protocols. `NexusAI` owns the AI router, the provider
   stack, and persistent consent/quota/secret stores. `NexusUI` depends on
   `NexusAI` in one direction only.

## Data model: typed entities + a uniform Link graph

Domain objects (tasks, notes, meetings, projects, …) are **typed entities**.
Relationships between them are **not** modeled with SwiftData `@Relationship`.
Instead, a single polymorphic `Link` entity stores raw fields:

```
Link(fromKind, fromID, toKind, toID, linkKind)
```

This deliberate choice lets any entity link to any other entity uniformly,
without a web of typed relationships. Treat it as load-bearing — don't
"upgrade" it to `@Relationship`.

## Persistence & sync

- **SwiftData** is the on-device store.
- **CloudKit private database** mirrors it across the user's devices. There is
  no shared or public CloudKit database and no third-party backend.
- The schema is **versioned** with an explicit migration plan; new entities are
  added additively. `NexusSync` owns the model-container factory (including the
  App Group container path used by extensions and the Watch).

## AI

- A central **AI router** sits behind a protocol and selects a provider.
- **On-device** (Apple Intelligence / local models) is the default path; no data
  leaves the device.
- **Cloud providers are opt-in**: a call only happens after explicit user
  consent in the UI, with a quota preflight. Secrets are kept in the keychain;
  consent and quota are persisted.

## Build & layout

- The Xcode project is **generated from `project.yml`** by
  [XcodeGen](https://github.com/yonaskolb/XcodeGen); `Nexus.xcodeproj/` is
  gitignored. Edit `project.yml`, never the generated project.
- The Swift packages under `Packages/` build and test with `swift test` and
  need no Apple account.
- App targets need a signing identity only for device/release builds — see
  [CONTRIBUTING.md](../CONTRIBUTING.md) for the local signing setup.

```bash
xcodegen generate
open Nexus.xcworkspace
cd Packages/NexusCore && swift test      # any package, no account needed
```

## Testing & quality

- New tests use **Swift Testing** (`@Test` / `#expect`); XCTest only where a
  framework requires it.
- **SwiftLint** and **Apple swift-format** must pass in `--strict` mode (CI gate).
- CI builds every app for Simulator/macOS with `CODE_SIGNING_ALLOWED=NO` and runs
  the package test suites.
