# Releasing

Versioning is [SemVer](https://semver.org). Pre-1.0: breaking changes may land in minor bumps.

## Steps
1. Move `CHANGELOG.md` `[Unreleased]` entries under a new `## [X.Y.Z] - YYYY-MM-DD` heading; update the compare links.
2. `git tag vX.Y.Z && git push origin vX.Y.Z`.
3. `gh release create vX.Y.Z --notes-from-tag` (or paste the changelog section).
4. For TestFlight: bump `CFBundleVersion` across the iOS-tree plists + Mac target atomically,
   archive, export, upload (see the maintainer runbook in the private archive).

## Build numbers
`CFBundleShortVersionString` = the SemVer (e.g. `0.1.0`); `CFBundleVersion` = a monotonic build
counter, bumped on every TestFlight upload.
