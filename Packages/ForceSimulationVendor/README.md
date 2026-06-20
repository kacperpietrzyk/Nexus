# ForceSimulationVendor

Vendored copy of the `ForceSimulation` module from [Grape](https://github.com/li3zhen1/Grape) (MIT © 2023 Zhen Li).

## Why vendored?

`Kinetics.position` is `package`-scoped in Grape, which means it is not
readable from NexusUI across package boundaries. Rather than using `Mirror`
reflection (fragile), we vendor this single self-contained module and add a
one-line public accessor we own.

## Provenance

- Source: `github.com/li3zhen1/Grape` tag `v1.1.0`
- Module vendored: `Sources/ForceSimulation/` (~25 files; Simulation/Kinetics/ForceProtocol + KDTree/ Forces/ Utils/)
- Grape's `Grape` module (SwiftUI chart layer) is NOT included — only the physics engine.

## Local patch

`Sources/ForceSimulation/Kinetics.swift` — after `package var position`:

```swift
/// Nexus vendor patch: public read accessor for settled node positions.
public var positions: [Vector] { position.asArray() }
```

`asArray()` was already `public` on `UnsafeArray`.

## Lint exclusion

This is unmodified third-party code (except the one-line patch above) and does
NOT pass our `--strict` linters. It is excluded from both:
- `swiftlint` via `excluded: [Packages/ForceSimulationVendor]` in `.swiftlint.yml`
- `swift format lint` (this path is not passed to the formatter)

Do NOT reformat or lint-fix vendored files — keep provenance clean for future
upstream comparisons.

## License

See `LICENSE` (MIT, © 2023 Zhen Li).
