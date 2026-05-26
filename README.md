# Nexus

All-in-one personal productivity app for the Apple ecosystem (Mac · iPhone · iPad · Watch).
Local-first (SwiftData + CloudKit private database), AI-augmented (on-device first, cloud opt-in).
Replaces Obsidian/Notion · Todoist · Linear · Circleback.

> **Status:** Active development, pre-1.0. In closed TestFlight beta. Single-user by design.

## Highlights
- Fast task capture (⌘N), Today view, Inbox, recurring tasks, natural-language dates (PL/EN)
- Native SwiftUI on macOS, iOS/iPadOS, watchOS; CloudKit sync across your devices
- On-device AI assist; optional cloud providers behind explicit consent
- Markdown export (anti-lock-in)

## Build from source

Prerequisites: macOS 26+, Xcode 26+ (Swift 6.2 toolchain), [Homebrew](https://brew.sh).

```bash
brew install xcodegen swiftlint
git clone https://github.com/kacperpietrzyk/Nexus.git && cd Nexus
xcodegen generate          # generates Nexus.xcodeproj (gitignored) from project.yml
open Nexus.xcworkspace
```

Run the pure-Swift packages with no Apple account at all:

```bash
cd Packages/NexusCore && swift test
```

To build/run the apps signed on a device, set your own Team ID — copy
`Config/Signing.local.xcconfig.example` to `Config/Signing.local.xcconfig` and fill it in.
See [CONTRIBUTING.md](CONTRIBUTING.md).

## Architecture
Modular monolith in five layers (apps → feature modules → core → persistence/sync → adapters).
See [`docs/architecture.md`](docs/architecture.md).

## Try the beta
TestFlight (Apple ID required; iOS 26 / macOS 26):
- macOS: https://testflight.apple.com/join/YBxhZ7SQ
- iOS: https://testflight.apple.com/join/cQ97NSzW

See [TESTING.md](TESTING.md) for how to give feedback.

## Contributing
PRs welcome — read [CONTRIBUTING.md](CONTRIBUTING.md) and [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md).
Found a security issue? See [SECURITY.md](SECURITY.md).

## License
[Apache License 2.0](LICENSE) © 2026 Kacper Pietrzyk.
