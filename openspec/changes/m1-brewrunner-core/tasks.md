# Tasks: M1 — CellarCore foundation, BrewRunner actor, brew detection

**Artifact store**: hybrid — Engram `sdd/m1-brewrunner-core/tasks`.
**Command shorthand**: `FAST` = `swift test --package-path Packages/CellarCore` ·
`FULL` = `xcodebuild test -project cellar.xcodeproj -scheme cellar -destination 'platform=macOS,arch=arm64'` ·
`BUILD` = `xcodebuild build -project cellar.xcodeproj -scheme cellar -destination 'platform=macOS,arch=arm64'`
**Strict TDD**: every behavioral task is RED (failing test) before GREEN (implementation).

## Review Workload Forecast

| Field | Value |
|-------|-------|
| Estimated changed lines | 1500–2000 (≈750 sources, ≈850 tests, ≈60 pbxproj/scheme, ≈70 app) |
| 400-line budget risk | High |
| 800-line budget risk | High |
| Chained PRs recommended | Yes |
| Suggested split | PR 1 (P0) → PR 2 (P1) → PR 3 (P2a) → PR 4 (P2b) → PR 5 (P3) → PR 6 (P4) |
| Delivery strategy | single-pr |
| Chain strategy | size-exception |

Decision needed before apply: Yes
Chained PRs recommended: Yes
Chain strategy: size-exception
400-line budget risk: High

Cached strategy is `single-pr` at an 800-line budget; the forecast is ~2x that, so `sdd-apply` MUST
obtain an explicit `size:exception` before starting, or the orchestrator must re-decide on chaining.

### Suggested Work Units

| Unit | Goal | Likely PR | Focused test command | Runtime harness | Rollback boundary |
|------|------|-----------|----------------------|-----------------|-------------------|
| 1 | Swift 6 / macOS 26.0 / sandbox-off settings migration, build green, no product code | PR 1 | `BUILD` | Launch `cellar.app`, confirm window renders | `git checkout f77d94c -- cellar.xcodeproj/project.pbxproj` |
| 2 | `Packages/CellarCore` package + `CellarCore` shared scheme, value types compile | PR 2 | `FAST` | N/A — no runtime surface yet (library only) | Delete `Packages/` + `CellarCore.xcscheme` |
| 3 | Process seam, `SystemProcess`, verbatim streaming, env, exit semantics | PR 3 | `FAST --filter Streaming` | `swift test` integration: `/bin/echo` through `SystemProcessLauncher` | Delete `ProcessLaunching/SystemProcess/BrewEnvironment` + their tests |
| 4 | Cancellation escalation + FIFO mutation gate | PR 4 | `FAST --filter Cancellation` | Real SIGINT on `/bin/sleep 30` via `SystemProcessLauncher` | Revert `BrewRunner` gate/escalation sections + tests |
| 5 | Detection: version parse, locator, strict validation, observable store | PR 5 | `FAST --filter Detection` | Real `brew --version` (detection-gated skip) | Delete `BrewLocation/DefaultBrewLocator/BrewVersion/BrewDetectionStore` + tests |
| 6 | App-target package link + detection surface | PR 6 | `FULL` | Launch app, confirm detected state text | Revert `cellarApp.swift`/`ContentView.swift` + pbxproj package ref |

## Phase 0: Build-settings migration (settings-only, no product code)

- [x] 0.1 In `cellar.xcodeproj/project.pbxproj` set `SWIFT_VERSION = 6.0` in all 6 build-config blocks.
- [x] 0.2 Set `MACOSX_DEPLOYMENT_TARGET = 26.0` in all 4 blocks.
- [x] 0.3 Set `ENABLE_APP_SANDBOX = NO` in the app Debug + Release blocks; leave hardened runtime ON (D8).
- [x] 0.4 Fix any Swift 6 diagnostic in `cellar/cellarApp.swift`, `ContentView.swift`, `Item.swift`. Verify: `BUILD` green, zero warnings; `FULL` still passes.
- [x] 0.5 Update `openspec/config.yaml` context: Swift 6 language mode, target 26.0, sandbox off.

## Phase 1: CellarCore package scaffold

- [x] 1.1 Create `Packages/CellarCore/Package.swift`: tools 6.0, `platforms: [.macOS("26.0")]`, target `BrewProcess` + test target `BrewProcessTests`, `swiftSettings: [.swiftLanguageMode(.v6)]`. Verify: `swift package dump-package --package-path Packages/CellarCore` emits valid JSON.
- [x] 1.2 RED: add `Tests/BrewProcessTests/LogLineTests.swift` asserting `LogLine(stream:text:sequence:)` equality and `Sendable` value semantics. Verify: `FAST` fails to compile (type missing).
- [x] 1.3 GREEN: create `Sources/BrewProcess/LogLine.swift`, `BrewCommand.swift`, `BrewExit.swift` (value types per design). Verify: `FAST` passes.
- [x] 1.4 Create `Sources/BrewProcess/BrewErrors.swift` with `BrewProcessError` + `BrewValidationError` cases from the design taxonomy.
- [x] 1.5 Create `cellar.xcodeproj/xcshareddata/xcschemes/CellarCore.xcscheme`.

## Phase 2a: Process seam, streaming, environment, exit

- [x] 2.1 Create `Sources/BrewProcess/ProcessLaunching.swift`: `ProcessSpec`, `OutputChunk`, `ProcessSignal`, `ProcessLaunching`, `LaunchedProcess`.
- [x] 2.2 Create `Tests/BrewProcessTests/Fakes/FakeProcessLauncher.swift` + `FakeProcess.swift`: scripted chunks, recorded `ProcessSpec`s, recorded `(signal, Instant)` pairs, controllable termination.
- [x] 2.3 RED (spec: verbatim streaming) `StreamingTests.swift` — line with leading whitespace, emoji, ANSI bytes round-trips byte-identical; a line split across two chunks reassembles; CRLF and missing trailing newline handled.
- [x] 2.4 RED (spec: stdout/stderr interleaving) stdout "a", stderr "b", stdout "c" arrive tagged in that exact order; `sequence` is monotonic (I4).
- [x] 2.5 RED (spec: stream finishes) after termination the `AsyncStream<LogLine>` finishes exactly once and yields nothing further.
- [x] 2.6 GREEN: `Sources/BrewProcess/BrewRunner.swift` — actor skeleton, `start(_:)`, pump `Task` (buffer → split → tag → sequence), operation record owning the pump (I3). Verify: `FAST`.
- [x] 2.7 RED (threat: environment inheritance) `EnvironmentTests.swift` — recorded spec contains `HOMEBREW_NO_AUTO_UPDATE=1`, `HOMEBREW_COLOR=0`, `HOMEBREW_NO_EMOJI=1` even when the parent env sets them differently; no `HOMEBREW_NO_INSTALL_FROM_API` key; `PATH`/`HOME` inherited.
- [x] 2.8 GREEN: `Sources/BrewProcess/BrewEnvironment.swift` building the explicit env; wire into `BrewRunner.start`.
- [x] 2.9 RED (threat: argument composition) an argument containing a space, `;`, and `$(id)` reaches the fake as ONE literal argv element; no `/bin/sh -c` anywhere in the recorded spec.
- [x] 2.10 GREEN: pass `BrewCommand.arguments` straight to `ProcessSpec.arguments`. Verify: `FAST`.
- [x] 2.11 RED (spec: terminal result) one stdout line then exit 1 ⇒ `BrewExit(status: 1, reason: .exited)` and the line was observable before the exit resolves (D3 — non-zero is not a throw).
- [x] 2.12 RED (spec: spawn failure) a launcher that throws ⇒ `BrewProcessError.executableUnavailable` / `.launchFailed`, no crash, no partial operation leaked.
- [x] 2.13 GREEN: `BrewOperation.exit()` + launch-failure mapping in `BrewRunner`. Verify: `FAST`.
- [x] 2.14 GREEN: `Sources/BrewProcess/SystemProcess.swift` — `Foundation.Process` + `Mutex<State>`, two readability handlers into ONE continuation, single `finish()` after both EOFs and reap (D1, I1); `SystemProcessLauncher`.
- [x] 2.15 Integration test `SystemProcessTests.swift`: `/bin/echo` through `SystemProcessLauncher` yields the expected `LogLine` and exit 0. Verify: `FAST`.

## Phase 2b: Cancellation escalation and FIFO gate

- [ ] 2.16 RED (spec: cooperative cancel) fake exits during `interruptGrace` ⇒ recorded signals == `[.interrupt]`, outcome `.cancelled(SIGINT)`, never a failure. Use an injected test `Clock` — no wall-clock sleeps.
- [ ] 2.17 RED (spec: escalation) fake ignores SIGINT ⇒ signals == `[.interrupt, .terminate]` after the grace advance, outcome cancelled.
- [ ] 2.18 RED (design D4) fake ignores both ⇒ `BrewProcessError.cancelledUnresponsive(after:)`; no SIGKILL is ever sent.
- [ ] 2.19 RED cancelling the CONSUMING Swift task triggers the identical escalation path.
- [ ] 2.20 GREEN: `CancellationPolicy` (.default 3s/2s) + escalation in `BrewRunner.cancel(_:)` with the injected clock. Verify: `FAST`.
- [ ] 2.21 RED (spec: FIFO) 3 `.mutate` commands never overlap and start in submission order (fakes gated on continuations).
- [ ] 2.22 RED (spec: concurrent reads) a `.read` starts and completes while a mutation is in flight.
- [ ] 2.23 RED (spec: queued cancel) cancelling queued mutation B spawns no process and B reports cancelled.
- [ ] 2.24 GREEN: FIFO gate in `BrewRunner` — tail assigned synchronously before the first `await` (D5, I2); document I1–I4 as code comments. Verify: `FAST`.
- [ ] 2.25 Integration: launch `/bin/sleep 30` via `SystemProcessLauncher`, cancel, assert `.cancelled(SIGINT)` within a generous deadline (never skipped).

## Phase 3: Brew detection

- [ ] 3.1 RED `BrewVersionTests.swift` — parameterized `@Test` over `Homebrew 6.0.14-38-g1f3abf4`, `Homebrew 4.0.0`, `Homebrew 3.6.21`, `/bin/echo` noise, empty string; plus `Comparable` ordering.
- [ ] 3.2 GREEN: `Sources/BrewProcess/BrewVersion.swift` with pure `parse(_:)`. Verify: `FAST`.
- [ ] 3.3 Create `Sources/BrewProcess/BrewLocation.swift` (`BrewPrefix`, `BrewInstallation`, `Advisory`, `BrewDetectionState`, `BrewLocating`, `ExecutableProbing`) and `Tests/.../Fakes/FakeExecutableProbe.swift`.
- [ ] 3.4 RED (spec: precedence) both prefixes exist ⇒ `.detected` at `/opt/homebrew/bin/brew` with `.appleSilicon`; only `/usr/local` ⇒ `.intelCarryOver`.
- [ ] 3.5 RED (spec: Rosetta advisory) `.intelCarryOver` carries `advisories.contains(.rosettaPrefix)` and nothing is disabled or degraded.
- [ ] 3.6 RED (spec: absent) nothing found, no configured path ⇒ `.absent` with install guidance; resolves without throwing.
- [ ] 3.7 RED (threat: executable classification) one test per `BrewValidationError`: non-executable ⇒ `.notExecutable`; `/bin/echo` printing `git version 2.4.0` ⇒ `.notHomebrew`; `Homebrew 3.6.21` ⇒ `.versionTooOld(found:minimum: 4.0.0)`; symlink resolved before probing.
- [ ] 3.8 RED (spec: custom precedence + no fallback) valid custom `Homebrew 4.2.0` wins over an existing native prefix; invalid custom ⇒ `.invalid`, NEVER `.detected` at a probed prefix (D6). Also: detection runs no mutating brew command.
- [ ] 3.9 RED configured path that no longer exists ⇒ `.configuredPathMissing(URL)`.
- [ ] 3.10 GREEN: `Sources/BrewProcess/DefaultBrewLocator.swift` + `DefaultExecutableProbe`. Verify: `FAST`.
- [ ] 3.11 RED `BrewDetectionStoreTests.swift` — launch evaluation publishes exactly one state; `absent` → brew appears → refresh publishes a transition to detected; single-flight `refresh()` collapses concurrent calls.
- [ ] 3.12 GREEN: `Sources/BrewProcess/BrewDetectionStore.swift` (`@MainActor @Observable`, single-flight). Verify: `FAST`.
- [ ] 3.13 Integration (detection-gated `.enabled(if:)`): real `brew --version` streams ≥1 ordered `LogLine` and exits 0; a bad subcommand yields non-zero exit AND stderr lines. Skip, never fail, when brew is absent.

## Phase 4: App wiring and verification

- [ ] 4.1 Add `XCLocalSwiftPackageReference "Packages/CellarCore"` + `BrewProcess` product dependency to target `cellar` in `project.pbxproj`. Verify: `BUILD`.
- [ ] 4.2 `cellar/cellarApp.swift`: own a `BrewDetectionStore`; `.task { await store.refresh() }` and refresh on `NSApplication.didBecomeActiveNotification`.
- [ ] 4.3 `cellar/ContentView.swift`: render `BrewDetectionState` as text only (path, prefix, version, advisory, invalid reason, absent guidance). No onboarding UI.
- [ ] 4.4 Verify the full gate: `FAST` (zero concurrency warnings) then `BUILD` then `FULL`, all green.
- [ ] 4.5 Launch the app and confirm the detected brew state renders (runtime harness for Unit 6); record the result.
