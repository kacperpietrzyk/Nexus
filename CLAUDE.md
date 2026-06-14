# Working in this repo (humans & AI assistants)

Nexus is a native Swift/SwiftUI productivity app for the Apple ecosystem
(Mac/iPhone/iPad/Watch). Local-first (SwiftData + CloudKit private DB),
AI-augmented (on-device first, cloud opt-in). Single-user by design.

## Architecture (5 layers, top→bottom)
1. **Apps** (`Apps/` — main shells `NexusMac|NexusiOS|NexusWatch` plus helper/extension targets: MCPSidecar, MeetingsHelper, Widgets, Share, DigestExtension, WatchComplications) — thin shells: composition root + platform glue. No logic.
2. **Feature modules** (`Packages/TasksFeature`, …) — independent; communicate only via the `Link` graph in core. No cross-module imports.
3. **Core** (`Packages/NexusCore`) — pure domain: `Link`, repos, search index, scheduler, exporter. Zero UIKit/AppKit, fully testable.
4. **Persistence + Sync** (`Packages/NexusSync`) — SwiftData + CloudKit mirror; owns the schema + migration plan + model container.
5. **Adapters** (`Packages/NexusAI|NexusUI|NexusSearch|NexusAgentTools`, …) — providers behind protocols.

See `docs/architecture.md` for the full picture.

## Hard constraints
- Single-user; no sharing/auth/multi-user UI.
- Sync is CloudKit private DB only.
- AI: on-device first; cloud calls require explicit user consent + quota preflight.
- Data model: typed entities + a uniform polymorphic `Link` graph (raw id/kind fields, not SwiftData `@Relationship`).
- Markdown export must always be possible (anti-lock-in).

## Tooling & daily commands
```bash
brew install xcodegen swiftlint
xcodegen generate                 # regenerate Nexus.xcodeproj from project.yml
open Nexus.xcworkspace
swift test                        # run from Packages/<name>/
swiftlint lint --strict
swift format lint --recursive --strict Apps Packages
```
`Nexus.xcodeproj/` is generated and gitignored — never edit it; edit `project.yml`.

## Tests & style
- Swift Testing (`@Test`/`#expect`) for new tests; XCTest only where required.
- SwiftLint + swift-format must pass `--strict` (CI gate).
- Conventional Commits. See `CONTRIBUTING.md` and `CODE_OF_CONDUCT.md`.
