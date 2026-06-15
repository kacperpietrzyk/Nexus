# Nexus

One native, local-first productivity app for the Apple ecosystem — **Mac · iPhone · iPad · Watch**.
Tasks, notes, meetings, projects, calendar and people in a single app, with an on-device AI
assistant and a full MCP server so you can drive it all from Claude or any agent.

[![CI](https://github.com/kacperpietrzyk/Nexus/actions/workflows/ci.yml/badge.svg)](https://github.com/kacperpietrzyk/Nexus/actions/workflows/ci.yml)
[![License: Apache-2.0](https://img.shields.io/github/license/kacperpietrzyk/Nexus)](LICENSE)
![Platforms](https://img.shields.io/badge/platforms-macOS·iOS·iPadOS·watchOS-blue)
[![Stars](https://img.shields.io/github/stars/kacperpietrzyk/Nexus?style=social)](https://github.com/kacperpietrzyk/Nexus/stargazers)

> 🚧 **Beta (0.3.0).** All the modules below are in the app today and on TestFlight. It's still
> early — the on-device AI is experimental and polish varies module to module. **Single-user by
> design**: your data lives in **your own iCloud**, and there are no app servers.

## Why Nexus

Most of us juggle a notes app, a to-do app, a meeting recorder, an issue tracker and a calendar —
four or five subscriptions, four or five silos that don't talk to each other. Nexus folds them into
**one native, private, local-first app** for the Apple ecosystem. Everything lives in a single
graph, so a task can link to the note it came from, the meeting that spawned it, and the person who
asked for it.

The long-term goal is to make a dedicated Obsidian / Notion / Todoist / Linear / Circleback
unnecessary for personal use. That's the destination — it's being built in the open, and you can
try where it is today.

## What's in the app today

Everything below ships in the current beta. Maturity varies; the AI assistant is explicitly
experimental.

- **Tasks** — fast capture (`⌘N` on Mac), Today view, Inbox, recurring tasks, reminders, and
  natural-language dates in English & Polish ("tomorrow 5pm", "jutro 17:00").
- **Notes** — Markdown editing with `[[wiki-links]]`, tables, and a trash/restore flow.
- **Meetings** — capture, transcription, summaries, and extracted action items.
- **Projects** — lightweight project & issue tracking: sections, cycles, stages and key dates.
- **Calendar** — events and day planning that schedules around your existing commitments.
- **People & Organizations** — a lightweight personal CRM that links people to the work they touch.
- **Sync** — across your devices via **CloudKit (private database)**. No shared database, no
  third-party backend.
- **Markdown export** — every item exports to Markdown, so there's no lock-in.

### 🤖 Drive it from any MCP client

Nexus ships a built-in **Model Context Protocol server** that exposes its data model as **100+
tools** across tasks, notes, meetings, projects, calendar and people. Point Claude (or any MCP
client) at it and your assistant can read, create, link and reorganize your work directly — search
your notes, file action items from a meeting, plan your day. This is the integration surface:
instead of bolting on point integrations, Nexus exposes itself and lets agents do the rest.

### 🧠 On-device AI assistant (experimental)

A local-first assistant built on small on-device models (Gemma-class via MLX), with a
**propose-confirm** flow — it never writes to your data without you accepting the change. It powers
a daily brief, task assist, an agent chat that can use the tools above, and lightweight insights.
On-device is the default; any cloud call is opt-in, gated by explicit consent and a quota check.

## Roadmap

| Area | Status |
|---|---|
| **Tasks** — capture, Today, Inbox, recurring, NL dates, reminders | ✅ Beta |
| **Notes** — Markdown, wiki-links, tables, trash | ✅ Beta |
| **Meetings** — capture, transcription, summaries, action items | ✅ Beta |
| **Projects** — sections, cycles, stages, key dates | ✅ Beta |
| **Calendar** — events, day planning | ✅ Beta |
| **People & Organizations** — personal CRM | ✅ Beta |
| **Sync** — CloudKit private database, cross-device | ✅ Beta |
| **MCP server** — drive the app from Claude / any agent | ✅ Beta |
| **On-device AI** — assistant, daily brief, agent chat, insights | 🧪 Experimental |

Want to help shape direction? Open a
[Discussion](https://github.com/kacperpietrzyk/Nexus/discussions) or an issue.

## Try the beta

TestFlight (Apple ID required; iOS 26 / macOS 26):

- **iOS / iPadOS:** https://testflight.apple.com/join/cQ97NSzW
- **macOS:** https://testflight.apple.com/join/YBxhZ7SQ *(new builds clear Apple review before installable, so this may lag)*

See [TESTING.md](TESTING.md) for how to give feedback.

## Build from source

Prerequisites: macOS 26+, Xcode 26+ (Swift 6.2 toolchain), [Homebrew](https://brew.sh).

```bash
brew install xcodegen swiftlint
git clone https://github.com/kacperpietrzyk/Nexus.git && cd Nexus
xcodegen generate          # generates Nexus.xcodeproj (gitignored) from project.yml
open Nexus.xcworkspace
```

The pure-Swift packages build and test with no Apple account at all:

```bash
cd Packages/NexusCore && swift test
```

For signed/device builds, copy `Config/Signing.local.xcconfig.example` to
`Config/Signing.local.xcconfig` and set your Team ID — see [CONTRIBUTING.md](CONTRIBUTING.md).

## Architecture

A native Swift/SwiftUI **modular monolith** in five layers (apps → feature modules → core →
persistence/sync → adapters). Domain objects are typed entities wired together by a single
polymorphic **Link graph** rather than typed relationships, so anything can link to anything.
Persistence is SwiftData mirrored to the CloudKit private database; AI sits behind protocols,
on-device first. See [`docs/architecture.md`](docs/architecture.md).

## Contributing

PRs welcome — read [CONTRIBUTING.md](CONTRIBUTING.md) and the [Code of Conduct](CODE_OF_CONDUCT.md).
Good first issues are [labeled](https://github.com/kacperpietrzyk/Nexus/labels/good%20first%20issue).
Security issue? See [SECURITY.md](SECURITY.md).

## License

[Apache License 2.0](LICENSE) © 2026 Kacper Pietrzyk.
