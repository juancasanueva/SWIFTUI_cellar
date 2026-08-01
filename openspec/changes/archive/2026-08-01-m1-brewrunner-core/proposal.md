# Proposal: M1 — CellarCore foundation, BrewRunner actor, brew detection

**PRD milestone**: M1 — Core & Catalog (first slice; catalog/Browse deferred).

## Intent

Cellar! is a GUI over the local `brew` binary, but the repo is still an unmodified Xcode template: no core package, no way to execute or stream a `brew` command, no way to know whether `brew` exists. Every later milestone sits on that substrate. It must land under the PRD's isolation rules (Swift 6, strict concurrency) from the start — retrofitting isolation onto a written actor and its tests costs far more.

## Scope

### In Scope

- Swift 6 language mode + strict concurrency (`SWIFT_VERSION 5.0 → 6.0`); fix template diagnostics.
- `MACOSX_DEPLOYMENT_TARGET 26.5 → 26.0` (PRD macOS 26 floor).
- `Packages/CellarCore` local SPM package (tools 6.x, `.swiftLanguageMode(.v6)`), wired into the app target. Only the `BrewProcess` module — no placeholder modules.
- `actor BrewRunner`: `Foundation.Process` behind protocol boundaries; env `HOMEBREW_NO_AUTO_UPDATE=1`, `HOMEBREW_COLOR=0`, `HOMEBREW_NO_EMOJI=1`; stdout+stderr as `AsyncStream<LogLine>`; cancellation SIGINT → SIGTERM; one mutating operation at a time, concurrent read-only queries.
- brew detection: `/opt/homebrew/bin/brew` (native), `/usr/local/bin/brew` (supported, flagged Rosetta carry-over), validated custom path, absent → explicit consumable state.
- Minimal app-target surface exposing detection state. No onboarding UI.

### Out of Scope

Catalog sync and search; Browse UI; typed `BrewClient`; onboarding/empty-state UI; SwiftData models; CI signing/notarization; SwiftLint config; M2–M6.

## Capabilities

### New Capabilities

- `brew-execution`: subprocess execution — env normalization, line-oriented stdout/stderr streaming, exit handling, cancellation escalation, serialized-mutation / concurrent-read queue.
- `brew-detection`: locating and validating the `brew` binary, classifying the prefix, reporting absent/invalid.

### Modified Capabilities

None — `openspec/specs/` is empty; this change establishes the first two.

## Approach

1. **Language mode first.** Flip both build settings, build green, before any product code exists — so isolation and `Sendable` design happen once.
2. **Package before code.** A local SPM dependency gives a `swift test` loop with no Xcode, GUI, or app launch, enforcing "testable without GUI" structurally.
3. **Protocol-first, TDD.** Process spawning and filesystem probing sit behind small `Sendable` protocols with production defaults and injectable fakes. Strict TDD: stream ordering, interleaved stderr, non-zero exit, cancellation escalation, queue serialization, and each detection outcome start as failing tests against fakes (deterministic, offline). A thin integration set exercises real `brew`.
4. **Thin app seam.** The app resolves and surfaces detection state; nothing is built on it yet.

## Affected Areas

| Area | Impact | Description |
|------|--------|-------------|
| `cellar.xcodeproj/project.pbxproj` | Modified | Swift 6 mode, strict concurrency, target 26.0, package reference + link |
| `Packages/CellarCore/Package.swift` | New | Manifest, `BrewProcess` target + tests |
| `Packages/CellarCore/Sources/BrewProcess/` | New | `BrewRunner`, `LogLine`, protocol boundaries, detection |
| `Packages/CellarCore/Tests/BrewProcessTests/` | New | Swift Testing suites (fakes + real-brew integration) |
| `cellar/` (app target) | Modified | Swift 6 template fixes; minimal detection wiring |
| `openspec/config.yaml` | Modified | Record new language mode and deployment target |

## Risks

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| Swift 6 migration surfaces template diagnostics | Med | ~4 tiny files; `MainActor` is already the default isolation. Build green before product code |
| `Process`/`readabilityHandler` callbacks fight strict concurrency | High | Confine handler state in the actor; bridge to `AsyncStream` via one continuation with a documented invariant — no scattered `@unchecked Sendable` |
| Signal escalation is timing-dependent → flaky | Med | Test policy against a fake process-control protocol; one real-signal integration case with a generous deadline |
| Integration tests need real Homebrew | Med | Detection-gated skip, not failure, when `brew` is absent |
| pbxproj edits hard to review | Low | Settings-only, one commit, single-file revert |
| Scope creep into onboarding UI or `BrewClient` | Med | Out of scope above; detection exposes state only |

## Rollback Plan

Single PR: `git revert` of the merge commit restores the template. Partial: `Packages/CellarCore/` is additive — delete the directory plus the package reference. Build-setting changes revert independently via `git checkout f77d94c -- cellar.xcodeproj/project.pbxproj`. No data, migrations, or user-visible behaviour to unwind.

## Dependencies

- Xcode 26.6 / Swift 6.3.3 toolchain (verified).
- Homebrew 6.0.14 at `/opt/homebrew/bin/brew` for integration tests (verified).
- A `CellarCore` scheme for `xcodebuild`-driven package verification.

## Success Criteria

- [ ] Builds clean in Swift 6 mode with strict concurrency, no warnings.
- [ ] Deployment target 26.0; app launches on the macOS 26 floor.
- [ ] `swift test --package-path Packages/CellarCore` passes without Xcode or a GUI.
- [ ] `BrewRunner` streams real `brew --version` output as ordered `LogLine`s, stdout and stderr distinguishable.
- [ ] A cancelled long operation terminates via SIGINT → SIGTERM and reports cancellation, not failure.
- [ ] Concurrent mutating operations run strictly sequentially; read-only queries are not blocked by an in-flight mutation.
- [ ] Detection classifies native, Rosetta-prefix, valid custom, invalid custom, and absent correctly.
- [ ] Every behaviour above was written test-first.
