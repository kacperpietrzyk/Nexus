# Nexus

A native, local-first productivity app for Apple devices — **Mac · iPhone · iPad · Watch**.

[![CI](https://github.com/kacperpietrzyk/Nexus/actions/workflows/ci.yml/badge.svg)](https://github.com/kacperpietrzyk/Nexus/actions/workflows/ci.yml)
[![License: Apache-2.0](https://img.shields.io/github/license/kacperpietrzyk/Nexus)](LICENSE)
![Platforms](https://img.shields.io/badge/platforms-macOS·iOS·iPadOS·watchOS-blue)
[![Stars](https://img.shields.io/github/stars/kacperpietrzyk/Nexus?style=social)](https://github.com/kacperpietrzyk/Nexus/stargazers)

> 🚧 **Early beta.** The **Tasks** module is usable today via TestFlight. Notes, meetings,
> projects, and an AI agent are on the [roadmap](#roadmap). Single-user by design — your data
> lives in **your own iCloud**; there are no app servers.

## What works today

The Tasks module, in TestFlight beta:

- ⚡ Fast capture (`⌘N` on Mac), Today view, Inbox
- 🔁 Recurring tasks, reminders, natural-language dates (English & Polish — "tomorrow 5pm", "jutro 17:00")
- ☁️ Sync across your devices via CloudKit (private database)
- 🧠 On-device AI task assist (experimental)
- 📤 Markdown export (no lock-in)

## The vision

Most of us juggle a notes app, a to-do app, a meeting recorder, and an issue tracker — four
subscriptions, four silos. Nexus folds those into **one native, private, local-first app** for
the Apple ecosystem: the long-term goal is to make a dedicated Obsidian / Notion / Todoist /
Linear / Circleback unnecessary for personal use.

That's the destination, not today's reality — right now only Tasks is shippable; the rest is
being built in the open.

## Roadmap

| Area | Status |
|---|---|
| **Tasks** — capture, Today, Inbox, recurring, NL dates, reminders | ✅ Beta |
| **Sync** — CloudKit private database, cross-device | ✅ Beta |
| On-device AI assist | 🧪 Experimental |
| **Notes** | 🔜 Planned |
| **Meetings** — transcription + summaries | 🔜 Planned |
| **Projects** — lightweight issue tracking | 🔜 Planned |
| **AI agent** — proactive, tool-using assistant | 🧪 In development |

Want to help shape direction? Open a [Discussion](https://github.com/kacperpietrzyk/Nexus/discussions) or an issue.

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

Modular monolith in five layers (apps → feature modules → core → persistence/sync → adapters),
SwiftData + CloudKit, AI behind protocols. See [`docs/architecture.md`](docs/architecture.md).

## Contributing

PRs welcome — read [CONTRIBUTING.md](CONTRIBUTING.md) and the [Code of Conduct](CODE_OF_CONDUCT.md).
Good first issues are [labeled](https://github.com/kacperpietrzyk/Nexus/labels/good%20first%20issue).
Security issue? See [SECURITY.md](SECURITY.md).

## License

[Apache License 2.0](LICENSE) © 2026 Kacper Pietrzyk.
