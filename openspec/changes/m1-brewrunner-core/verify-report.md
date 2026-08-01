```yaml
schema: gentle-ai.verify-result/v1
evidence_revision: sha256:e5be994c2662b604c9e35841725a2cf5e1c2d306b0e5b0d83fbc439d309f723f
verdict: pass
blockers: 0
critical_findings: 0
requirements: 11/11
scenarios: 24/24
test_command: swift test --package-path Packages/CellarCore
test_exit_code: 0
test_output_hash: sha256:8d4d03ceea80aae4f2540692b105abf22b7670772cab041a7ff7e150a68b0f64
build_command: xcodebuild test -project cellar.xcodeproj -scheme cellar -destination 'platform=macOS,arch=arm64'
build_exit_code: 0
build_output_hash: sha256:4b5bb405737fd6d7fed509427c5cb4f754d5463564d16afe15f2820035f4534b
```

## Verification Report

**Change**: m1-brewrunner-core
**Version**: N/A (two NEW capabilities, ADDED-only deltas)
**Mode**: Strict TDD
**Branch**: `feature/m1-brewrunner-core` @ `9e79e85` (6 commits, `2cb317c..9e79e85`), working tree clean
**Artifact store**: hybrid (OpenSpec file + Engram)

### Completeness

| Metric | Value |
|--------|-------|
| Tasks total | 53 |
| Tasks complete | 53 |
| Tasks incomplete | 0 |

Every task in `openspec/changes/m1-brewrunner-core/tasks.md` is checked, and each maps to code
present on the branch. Spot-checked bindings: 0.1–0.3 → `project.pbxproj`; 1.1 → `Package.swift`;
2.14 → `SystemProcess.swift`; 2.24 → `BrewRunner.enqueueMutation`; 3.10 → `DefaultBrewLocator.swift`;
3.12 → `BrewDetectionStore.swift`; 4.1–4.3 → `project.pbxproj`, `cellarApp.swift`, `ContentView.swift`.

### Build & Tests Execution

**Build (clean package rebuild)**: PASS
```text
$ rm -rf Packages/CellarCore/.build
$ swift build --package-path Packages/CellarCore --build-tests
Build complete! (5.99s)
warnings: 0
```

**Build + tests (app scheme)**: PASS
```text
$ xcodebuild test -project cellar.xcodeproj -scheme cellar -destination 'platform=macOS,arch=arm64'
Executed 4 tests, with 0 failures (0 unexpected) in 19.436 seconds
** TEST SUCCEEDED **   exit 0   warnings: 0
```

**Tests (package)**: PASS — 86 passed / 0 failed / 0 skipped
```text
$ swift test --package-path Packages/CellarCore
Test run with 86 tests in 15 suites passed after 0.676 seconds.   exit 0
```

Both counts match the apply-progress claim exactly (86 package + 4 app). The 4 brew-gated
integration tests ran (not skipped) because `/opt/homebrew/bin/brew` is executable on this machine.

**Coverage**: 98.27% lines / 93.07% regions across the package → above any reasonable threshold.

### Spec Compliance Matrix

Capability `brew-execution` (6 requirements / 12 scenarios):

| Requirement | Scenario | Test | Result |
|---|---|---|---|
| Normalized brew environment | Environment applied to every invocation | `EnvironmentTests > Every launched command carries the normalized environment`, `> Pinned values win over a parent environment that sets them differently`, `> HOMEBREW_NO_INSTALL_FROM_API is never set, even if the parent sets it` | COMPLIANT |
| Verbatim line-oriented output streaming | Line content is preserved exactly | `StreamingTests > Leading whitespace, emoji, and ANSI bytes survive untouched` | COMPLIANT |
| Verbatim line-oriented output streaming | stdout/stderr distinguishable, interleaved in read order | `StreamingTests > stdout and stderr stay distinguishable and keep read order` | COMPLIANT |
| Verbatim line-oriented output streaming | Stream finishes after process termination | `StreamingTests > The stream finishes once after termination and yields nothing more` | COMPLIANT |
| Terminal result and exit handling | Non-zero exit reports failure with its code | `ExitTests > A non-zero exit is a result carrying its code, not a thrown error` + `> Every emitted line is observable before the exit resolves` + `SystemProcessTests > A real non-zero exit is reported as a result, not an error` | COMPLIANT (see W2 — code is carried on `BrewExit`, not on a thrown error, per approved design D3) |
| Terminal result and exit handling | Unlaunchable binary reports spawn failure | `ExitTests > A missing executable is reported as executableUnavailable`, `> A failed spawn leaves no operation behind`, `SerializationTests > A queued mutation whose spawn fails reports the fault and frees the gate` | COMPLIANT (see W3 — `.mutate` surfaces it via `fault()`) |
| Cancellation escalates SIGINT then SIGTERM | Cooperative process stops at SIGINT | `CancellationTests > A cooperative process stops at SIGINT and reports cancelled` + `SystemProcessTests > Cancelling a real /bin/sleep delivers SIGINT and reports cancelled` | COMPLIANT |
| Cancellation escalates SIGINT then SIGTERM | Unresponsive process escalated to SIGTERM | `CancellationTests > A process that ignores SIGINT is escalated to SIGTERM after the grace`, `> SIGTERM is only sent after the interrupt grace has actually elapsed`, `> A process ignoring both signals is reported unresponsive, never killed` | COMPLIANT |
| Cancellation escalates SIGINT then SIGTERM | (requirement clause) consuming-task cancellation triggers the same path | `CancellationTests > Cancelling the consuming Swift task escalates the same way` | COMPLIANT |
| Serialized mutations with concurrent reads | Two mutations never overlap | `SerializationTests > Three mutations run one at a time, in submission order` | COMPLIANT |
| Serialized mutations with concurrent reads | Reads proceed during a mutation | `SerializationTests > A read starts and completes while a mutation is still running` | COMPLIANT |
| Serialized mutations with concurrent reads | Cancelling a queued mutation spawns nothing | `SerializationTests > Cancelling a queued mutation spawns nothing and reports cancelled` + `> A cancelled mutation releases the gate for the one behind it` | COMPLIANT |
| Swift 6 concurrency and platform baseline | Package builds and tests headlessly under Swift 6 | Executed: clean `swift build --build-tests` (0 warnings) + `swift test` (86/86), no Xcode, no GUI | COMPLIANT |

Capability `brew-detection` (5 requirements / 12 scenarios):

| Requirement | Scenario | Test | Result |
|---|---|---|---|
| Prefix classification and precedence | Native prefix preferred when both exist | `DetectionTests > The native prefix wins when both prefixes exist` | COMPLIANT |
| Prefix classification and precedence | Only the Rosetta prefix exists | `DetectionTests > Only the Intel prefix present resolves as a carry-over installation` | COMPLIANT |
| Rosetta prefix fully supported, advisory only | Advisory flag does not restrict capability | `DetectionTests > A carry-over installation is advisory only, never degraded` | COMPLIANT |
| Absent brew is a soft signal | No brew anywhere | `DetectionTests > No brew anywhere resolves to absent with install guidance` + `BrewDetectionStoreTests > The state before any evaluation is the soft absent signal` | COMPLIANT |
| Strict custom path validation | Path is not executable | `DetectionTests > A configured path that is not executable is invalid, not absent` | COMPLIANT |
| Strict custom path validation | Path is executable but is not Homebrew | `DetectionTests > An executable that is not Homebrew is invalid with its output` + `BrewIntegrationTests > A configured path pointing at a non-Homebrew binary is rejected` | COMPLIANT |
| Strict custom path validation | Homebrew below the 4.x floor | `DetectionTests > Homebrew below the 4.0.0 floor is invalid with both versions` | COMPLIANT |
| Strict custom path validation | Valid custom path wins over auto-discovery | `DetectionTests > A valid configured path wins over an existing native prefix` | COMPLIANT |
| Strict custom path validation | Invalid custom path does not fall back | `DetectionTests > An invalid configured path never falls back to a working prefix` (asserts the native prefix is never even probed) | COMPLIANT |
| Strict custom path validation | (requirement clause) no mutating brew command | `DetectionTests > Detection only ever runs --version, never a mutating command` | COMPLIANT |
| Detection is observable, re-evaluated state | Evaluated at launch | `BrewDetectionStoreTests > The launch evaluation publishes exactly one state` | COMPLIANT |
| Detection is observable, re-evaluated state | Focus re-evaluation observes a newly installed brew | `BrewDetectionStoreTests > Brew appearing after an absent result publishes the transition` | COMPLIANT (store level; the AppKit focus wiring itself is untested — W5) |
| Detection is observable, re-evaluated state | Disappearing configured path transitions away | `BrewDetectionStoreTests > A configured path that vanishes transitions off detected` | PARTIAL (W1 — resolves to `.configuredPathMissing`, a third state not enumerated by the scenario) |

**Compliance summary**: 24/24 scenarios have a passing covering test; 23 COMPLIANT, 1 PARTIAL, 0 UNTESTED, 0 FAILING.

### Correctness (Static Evidence)

| Requirement | Status | Notes |
|---|---|---|
| Normalized brew environment | Implemented | `BrewEnvironment.pinned` merges last; `inheritedKeys = ["PATH", "HOME"]` only; `HOMEBREW_NO_INSTALL_FROM_API` never written. |
| Verbatim streaming | Implemented | `LineSplitter` removes only the `\n` / `\r\n` terminator; no trim, case-fold, ANSI strip, or dedup anywhere in `Sources/`. A bare `\r` stays content. |
| Terminal result and exit handling | Implemented | `BrewRunner.drive` awaits the pump before reading `waitForTermination()`, so lines are observable before the result resolves. |
| Cancellation SIGINT → SIGTERM | Implemented | `ProcessSignal` has exactly two cases mapping to `SIGINT`/`SIGTERM`; no `SIGKILL` outside comments; escalation stops after `.terminate` and reports `.cancelledUnresponsive`. |
| Serialized mutations, concurrent reads | Implemented | `.mutate` joins the tail chain; `.read` spawns directly in `start` and never touches `mutationTail`. |
| Swift 6 / platform baseline | Implemented | `Package.swift`: tools 6.0, `platforms: [.macOS("26.0")]`, `.swiftLanguageMode(.v6)` on both targets. No `#available` in `Sources/`. |
| Prefix precedence | Implemented | `DefaultBrewLocator.standardCandidates` is ordered `/opt/homebrew` then `/usr/local`; configured path short-circuits before probing. |
| Rosetta advisory only | Implemented | `Advisory.rosettaPrefix` is metadata on a `.detected` installation; nothing branches on it in the core. |
| Absent is a soft signal | Implemented | `BrewDetectionState.absent` + `installGuidance`; `detect` is non-throwing; store initialises to `.absent`. |
| Strict custom path validation | Implemented | `validate` runs executable → parses-as-Homebrew → `>= 4.0.0` in order, returning exactly one reason; configured branch never falls through. |
| Observable, re-evaluated state | Implemented | `@MainActor @Observable BrewDetectionStore` with single-flight `refresh()`; app refreshes at launch and on `NSApplication.didBecomeActiveNotification`. |

### Coherence (Design)

| Decision | Followed? | Notes |
|---|---|---|
| D1 — `SystemProcess` confined by `Mutex`, zero `@unchecked` | Yes | `final class SystemProcess: LaunchedProcess, Sendable`; stored state is `Mutex<State>` + one `let` continuation + one `let` stream. Repo-wide grep: **zero** `@unchecked`, `nonisolated(unsafe)`, or `@preconcurrency` in `Packages/CellarCore/` and `cellar/` (the only hit is the word inside a doc comment). |
| D1 / I1 — one continuation, one `finish()` after both EOFs *and* reap | Yes | `completeIfDone()` guards on `!completed && stdoutAtEOF && stderrAtEOF && reaped != nil` inside a single `withLock`, then finishes and resumes waiters outside the lock. |
| D2 — two-layer streaming, splitting in tested actor code | Yes | `LineSplitter` is a pure `struct` (per-pipe buffers) driven by `BrewRunner.startPump`; nothing splits in the readability handler. |
| D3 — exit is not an error | Yes | Non-zero returns `BrewExit(status:reason:.exited)`; only launch faults and `cancelledUnresponsive` are `BrewProcessError`. |
| D4 — escalation stops at SIGTERM | Yes | No `SIGKILL` in any code path; `ProcessSignal` cannot express it. |
| D5 / I2 — gate tail assigned synchronously before first `await` | Yes | `enqueueMutation` is non-`async` and never suspends: it reads `mutationTail`, creates the gate `Task`, and assigns `mutationTail = gate` in straight-line code, so actor reentrancy cannot reorder the queue. |
| D6 — configured path never falls through | Yes | `detectConfigured` returns `.invalid`/`.configuredPathMissing` directly; `detectStandard` is unreachable from that branch. |
| D7 — verbatim core | Yes | See correctness row; `HOMEBREW_COLOR=0` / `NO_EMOJI=1` pinned at the source instead of stripping downstream. |
| D8 — app sandbox off, hardened runtime unchanged | Yes | `ENABLE_APP_SANDBOX YES→NO` in app Debug+Release only; `ENABLE_HARDENED_RUNTIME = YES` present in both and **absent from the diff** (untouched). |
| I3 — pump owned by the operation record | Yes | `OperationRecord.pump` with a documented comment; cancelled on the unresponsive path. |
| I4 — `sequence` monotonic within a stream | Yes | Documented on `LogLine.sequence`; asserted by `StreamingTests > Sequence numbers are globally monotonic across both streams`. |
| Injected `Clock` in escalation | Yes | `BrewRunner.completes` uses `clock.sleep(for:)`; the **only** `sleep` call in `Sources/`. Tests drive a `TestClock` (`clock.advance(by:)`), so no wall-clock waits in cancellation logic. |
| Documented deviation 1 — `BrewOperation.fault()` | Accepted | `exit()` stays non-throwing (D3-consistent); `fault()` is the channel for `.cancelledUnresponsive` and gated-mutation launch failure. Spec-conformant: the spec never prescribes the delivery channel, only that spawn failure is distinct and cancellation is reported as cancelled. |
| Documented deviation 2 — `.mutate` spawns lazily inside the gate | Accepted | Required by the spec scenario "Cancelling a queued mutation spawns nothing", which needs a handle before the spawn. Verified by `SerializationTests`: `launchCount == 1` after cancelling B, and B still reports `.cancelled(signal: SIGINT)`. See W3 for the caller-facing consequence. |
| Documented deviation 3 — `ExecutableProbing.exists/resolvingSymlinks` | Accepted | Needed to distinguish `.configuredPathMissing` from `.notExecutable` and to satisfy the design's "symlinks resolved before probing" threat response. Tested by `DetectionTests > A symlinked configured path is resolved before it is probed`. |

### Build-Settings Facts (verified in `cellar.xcodeproj/project.pbxproj`)

| Fact | Expected | Observed |
|---|---|---|
| `SWIFT_VERSION` | `6.0` in all 6 config blocks | 6 occurrences, all `6.0`; diff shows 6× `5.0 → 6.0` |
| `MACOSX_DEPLOYMENT_TARGET` | `26.0` in all 4 blocks | 4 occurrences, all `26.0`; diff shows 4× `26.5 → 26.0` |
| `ENABLE_APP_SANDBOX` | `NO` on app Debug + Release only | 2 occurrences, both `NO`; diff shows 2× `YES → NO` |
| `ENABLE_HARDENED_RUNTIME` | unchanged (`YES`) | 2 occurrences, both `YES`, and no diff hunk touches it |
| `ENABLE_USER_SELECTED_FILES` | unchanged | `readonly` in both app configs, untouched |
| CellarCore linked | local package ref + product dep | `XCLocalSwiftPackageReference "Packages/CellarCore"` + `XCSwiftPackageProductDependency BrewProcess` in `packageProductDependencies` and `Frameworks` phase of target `cellar` |

### TDD Compliance

| Check | Result | Details |
|---|---|---|
| TDD Evidence reported | Yes | 17-row "TDD Cycle Evidence" table in `sdd/m1-brewrunner-core/apply-progress` |
| All tasks have tests | Yes | 53/53; the 8 non-behavioral tasks (settings, scheme, package manifest, app wiring) are covered by BUILD + FULL gates rather than unit tests, as the table declares |
| RED confirmed (test files exist) | Yes | 15/15 declared test files exist on disk and are the ones executed |
| GREEN confirmed (tests pass) | Yes | 86/86 pass on re-execution from a clean `.build` |
| Triangulation adequate | Yes | Every behavioral row reports 3–14 cases; `BrewVersionTests` is a parameterized `@Test` over 9 fixtures |
| Safety net for modified files | Yes | Each row after the first records the prior green count (4 → 26 → 31 → 34 → 42 → 46 → 53 → 58 → 59 → 61 → 75 → 82 → 86) |
| RED honestly reported | Partial | Tasks 2.9–2.10 disclose "no observable RED" — argv passthrough was already satisfied by 2.6's minimal GREEN, so the 3 threat tests are regression guards, not driving tests (W4) |

**TDD Compliance**: 6/7 checks fully passed, 1 partial (self-disclosed).

### Test Layer Distribution

| Layer | Tests | Files | Tools |
|---|---|---|---|
| Unit (pure + fakes) | 77 | 13 | swift-testing |
| Integration (real process, never skipped) | 5 | 1 (`SystemProcessTests`) | `/bin/echo`, `/usr/bin/false`, `/bin/sleep`, missing binary |
| Integration (real brew, gated) | 4 | 1 (`BrewIntegrationTests`) | `.enabled(if: FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/brew"))` — skip, never fail |
| UI (app scheme) | 4 | `cellarUITests` | XCTest |
| **Total** | **90** | **15 + UI** | |

Gating verified: the brew-gated suite uses `.enabled(if:)` at the `@Suite` level (skip-not-fail), and
the real-signal test is `SystemProcessTests > Cancelling a real /bin/sleep delivers SIGINT and reports
cancelled` on `/bin/sleep 30` with `.timeLimit(.minutes(1))` and no gating trait — it always runs.

### Changed File Coverage

| File | Line % | Region % | Rating |
|---|---|---|---|
| `Sources/BrewProcess/BrewCommand.swift` | 100% | 100% | Excellent |
| `Sources/BrewProcess/BrewDetectionStore.swift` | 100% | 100% | Excellent |
| `Sources/BrewProcess/BrewEnvironment.swift` | 90.91% | 80.00% | Excellent (uncovered: `current()`, which reads the real process env) |
| `Sources/BrewProcess/BrewExit.swift` | 100% | 100% | Excellent |
| `Sources/BrewProcess/BrewLocation.swift` | 100% | 92.31% | Excellent |
| `Sources/BrewProcess/BrewRunner.swift` | 97.76% | 91.76% | Excellent |
| `Sources/BrewProcess/BrewVersion.swift` | 100% | 73.33% | Excellent |
| `Sources/BrewProcess/CancellationPolicy.swift` | 100% | 100% | Excellent |
| `Sources/BrewProcess/DefaultBrewLocator.swift` | 100% | 100% | Excellent |
| `Sources/BrewProcess/LineSplitter.swift` | 95.00% | 96.43% | Excellent |
| `Sources/BrewProcess/LogLine.swift` | 100% | 100% | Excellent |
| `Sources/BrewProcess/ProcessLaunching.swift` | 100% | 100% | Excellent |
| `Sources/BrewProcess/SystemProcess.swift` | 97.37% | 89.09% | Excellent |

**Average changed-file coverage**: 98.27% lines / 93.07% regions (whole package, `llvm-cov report`).

### Assertion Quality

Audited all 15 test files (202 `#expect`, 5 `#require`). No tautologies, no assertions that skip
production code, no ghost loops, no smoke-only tests, no mock-heavy files (fakes are hand-written
protocol doubles, not mocking-framework stubs, and every file asserts far more than it fakes).

Every empty-collection assertion has a companion non-empty assertion in the same test or suite:

| File | Line | Assertion | Companion evidence | Verdict |
|---|---|---|---|---|
| `StreamingTests.swift` | 114 | `#expect(afterFinish.isEmpty)` | Same test first asserts `lines.map(\.text) == ["only line"]` | Valid |
| `DetectionTests.swift` | 185 | `#expect(launcher.recordedSpecs.isEmpty)` | `> Detection only ever runs --version` asserts `recordedArguments == [["--version"]]` | Valid |
| `SerializationTests.swift` | 141 | `#expect(lines.isEmpty)` | Same test asserts `fault == .executableUnavailable(...)` | Valid |
| `CancellationTests.swift` | 140 | `#expect(process.deliveredSignals.isEmpty)` | Sibling tests assert `deliveredSignals == [.interrupt]` / `[.interrupt, .terminate]` | Valid |
| `BrewDetectionStoreTests.swift` | 72 | `#expect(store.state.installGuidance != nil)` | `DetectionTests > No brew anywhere` asserts website and command content | Valid |

**Assertion quality**: All assertions verify real behavior — 0 CRITICAL, 0 WARNING.

### Quality Metrics

**Linter**: Not available — no SwiftLint/SwiftFormat configuration in the repo (not a failure).
**Type checker / compiler**: 0 errors, 0 warnings on a clean package rebuild and on the app scheme build.

### Scope Check

No scope creep found in product code. Nothing beyond the approved surface: no catalog, no search, no
install/uninstall UI, no onboarding, no settings screen. `BrewDetectionSummary` in `ContentView.swift`
is text-only, as task 4.3 specifies. No CI configuration files exist anywhere in the repo.

Two files land outside the design's file table, both benign and outside the product surface:
`.gitignore` (new; ignores `.build/`, `xcuserdata/`, `.codegraph/`, `.atl/`) and `PRD.md` (the
pre-existing product brief, previously untracked, now committed). Neither affects behavior.

### Issues Found

**CRITICAL**: None.

**WARNING**:

- **W1 — `.configuredPathMissing` is not one of the scenario's enumerated outcomes.** The
  brew-detection scenario "Disappearing configured path transitions away" says the state becomes
  `invalid(notExecutable)` **or** `absent`. The implementation (and design, and task 3.9) introduce a
  third state, `.configuredPathMissing(URL)`, and `BrewDetectionStoreTests > A configured path that
  vanishes transitions off detected` asserts exactly that. The *requirement* is satisfied — the
  transition off `custom` is published and observers see it — but the scenario's literal `THEN` is
  not. `.configuredPathMissing` is arguably the better model (it distinguishes "you deleted it" from
  "it is not executable"). Recommend amending the scenario text during archive so spec and code agree.
- **W2 — non-zero exit is a result, not an error.** The brew-execution requirement says failure is a
  terminal outcome with the "non-zero exit code, exposed on the error", and the scenario says the
  operation "fails with an error carrying exit code 1". Design D3 (approved) deliberately rejects
  this: the code is carried on `BrewExit.status` with `reason: .exited`, and nothing throws. The
  intent — exactly one terminal outcome with the code exposed — holds. Same recommendation: align the
  spec wording at archive.
- **W3 — asymmetric spawn-failure channel between `.read` and `.mutate`.** A `.read` reports launch
  failure through `start`'s typed `throws(BrewProcessError)`; a queued `.mutate` cannot, so it
  reports through `await operation.fault()` and resolves `BrewExit(status: 127, reason: .exited)`.
  This is the documented deviation 2 and it is spec-conformant, but a caller that only inspects
  `exit()` will read a gated mutation's spawn failure as an ordinary exit 127. Worth a doc note on
  `BrewRunner.start` (it is currently only explained in the apply artifact) before M2 consumes it.
- **W4 — one TDD row without an observable RED.** Tasks 2.9–2.10 (argv passthrough) had no failing
  state, because task 2.6's minimal GREEN already satisfied it. The apply phase disclosed this
  honestly and the 3 threat tests remain valuable regression guards; no fabricated RED was claimed.
- **W5 — the AppKit focus wiring has no automated test.** `cellarApp.swift` re-refreshes on
  `NSApplication.didBecomeActiveNotification` via an `AsyncSequence` of notifications. The *store*
  behavior it depends on is well covered, and the 4 UI tests only prove the app launches; the
  notification plumbing itself was verified once by a temporary accessibility-tree harness that was
  not committed. A regression here would be silent.
- **W6 — reviewer load.** The authored diff is 3473 lines (3456 add / 17 del) across 30 non-OpenSpec
  files, roughly 4.3× the cached 800-line budget. `size:exception` was explicitly accepted before
  apply, so this is not a gate failure, but the 6 commits map 1:1 onto the planned PR slices if the
  reviewer prefers a chain.

**SUGGESTION**:

- **S1 — spec vs. code vocabulary.** The spec says `native` / `rosettaCarryOver`; the code says
  `BrewPrefix.appleSilicon` / `.intelCarryOver`. Semantically identical, but the mismatch makes the
  spec harder to grep against the source. Pick one vocabulary at archive.
- **S2 — operation records are never evicted.** `BrewRunner.operations` grows one entry per command
  for the runner's lifetime. Harmless for M1 (one detection plus a handful of commands); needs
  eviction on terminal resolution before M2's continuous usage.
- **S3 — inherited environment is `PATH` + `HOME` only.** If a real brew command turns out to need
  `LANG`, `TMPDIR`, or `USER`, the whitelist has to grow. Deliberate per the design's threat
  response; flagged so the first failure is recognised for what it is.
- **S4 — `BrewVersion.parse` region coverage is 73%.** Line coverage is 100%; the uncovered regions
  are short-circuit branches inside the guards. Adding a fixture with a non-numeric component
  (`Homebrew 4.x.0`) would close them.

### Verdict

**PASS WITH WARNINGS** — all 53 tasks complete, both test gates re-executed green (86 package + 4 app,
0 failures, 0 warnings), all 24 spec scenarios covered by a passing test (23 compliant, 1 partial),
and every design invariant (D1–D8, I1–I4) verified in code. The six warnings are documentation and
follow-up items, not defects: none blocks archive, and W1/W2 should be resolved by amending the spec
text to match the approved design rather than by changing code.
