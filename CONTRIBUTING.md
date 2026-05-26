# Contributing to Nexus

Thanks for your interest! Nexus is a single-user productivity app; contributions
should fit that scope (see [`docs/architecture.md`](docs/architecture.md) for hard constraints).

## Development setup
```bash
brew install xcodegen swiftlint
xcodegen generate
open Nexus.xcworkspace
```
- Edit **`project.yml`**, never the generated `Nexus.xcodeproj`.
- The Swift packages under `Packages/` build and test with `swift test` and need **no Apple account**.
- To build/run the apps **on a device**, copy `Config/Signing.local.xcconfig.example` to
  `Config/Signing.local.xcconfig` and set your `DEVELOPMENT_TEAM`. Note: the app's bundle IDs
  (`com.kacperpietrzyk.Nexus.*`) belong to the maintainer; for a personal device install you
  must also change the bundle prefix. Simulator builds (`CODE_SIGNING_ALLOWED=NO`) need none of this.

## Before you open a PR
All of these are CI-gated:
```bash
swift test                                            # in each Packages/<name> you touched
swiftlint lint --strict
swift format lint --recursive --strict Apps Packages
```
- New tests use **Swift Testing** (`@Test` / `#expect`).
- Keep changes focused; one logical change per PR.

## Commit messages — Conventional Commits
Format: `type(scope): summary`, e.g. `feat(tasks): add weekly recurrence`.
Types: `feat`, `fix`, `docs`, `refactor`, `test`, `build`, `chore`, `perf`, `ci`.

## Sign-off — Developer Certificate of Origin (DCO)
Every commit must be signed off (certifies you wrote / have the right to submit the change):
```bash
git commit -s -m "feat(tasks): ..."
```
This appends `Signed-off-by: Your Name <you@example.com>`. A CI check enforces it.

## PR flow
1. Fork, branch from `main`.
2. Make changes, add tests, ensure the CI commands above pass locally.
3. Add a `CHANGELOG.md` entry under `[Unreleased]` when user-facing.
4. Open a PR; fill in the template. Maintainer reviews; `main` requires a passing review + green CI.

## License
By contributing you agree your contributions are licensed under the project's
[Apache License 2.0](LICENSE).
