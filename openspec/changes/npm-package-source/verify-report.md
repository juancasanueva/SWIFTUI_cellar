```yaml
schema: gentle-ai.verify-result/v1
evidence_revision: sha256:bf4c26ebf3b9109220d10465e574e45f1b5c56e0d8b58d51edc715829af4f356
verdict: pass
blockers: 0
critical_findings: 0
requirements: 24/24
scenarios: 72/72
test_command: swift test --package-path Packages/CellarCore
test_exit_code: 0
test_output_hash: sha256:6479ebb1efb2b481c9b7c9cec7322e08f5c77c8c87ab108fb177d07d97bf3d3a
build_command: xcodebuild test -project cellar.xcodeproj -scheme cellar -destination 'platform=macOS,arch=arm64'
build_exit_code: 0
build_output_hash: sha256:8fafd5ada9b97cb26b3c7b5536674a9e3fde7595f5202cecb722327c6a6fc6b6
```

## Verification Report

**Change**: `npm-package-source`
**Mode**: Strict TDD, interactive, artifact store hybrid (this file is canonical; Engram topic
`sdd/npm-package-source/verify-report` mirrors it). RDD disabled.
**Branch**: `feat/npm-package-source`, staged and uncommitted. `PRD.md` and `cellar/InfoPlist.xcstrings`
are unstaged pre-existing edits outside this change and were ignored.
**Delivery**: `single-pr` with accepted `size:exception`. Per the maintainer's ruling (Engram #7968) the
budget counts **production** lines: 3,742 staged production insertions against 8,000. Recorded, **not** a
finding.
**Scope of this phase**: read-only except this report. No source edited, nothing committed.
**Run**: re-verification after the C1 remediation. The prior report's 71/72 findings are carried forward as
already verified; this run re-executed both suites in full and re-audited the remediated area.

**Verdict**: **PASS WITH WARNINGS** — 0 CRITICAL, 2 WARNING, 3 SUGGESTION. C1 is closed. All 72 specified
scenarios are now proven by tests that passed at runtime. Nothing blocks archive.

---

### C1 remediation — CLOSED

The prior run's single blocker was `brew-detection` BD-A1 **scenario 2** ("The two evaluations do not
couple") with no covering test. It is now covered.

| Check | Result |
|---|---|
| Test exists | `heldNpmEvaluationDoesNotCoupleToBrewDetection` at `Packages/CellarCore/Tests/BrewProcessTests/NpmDetectionStoreTests.swift:207`, display name "A held npm evaluation neither delays a brew transition nor republishes brew when released" |
| Staged blob matches worktree | Yes — both `sha256:87ef1af9605e4531d227cd556e6d6f6429b5566334240fb43b8e604bc74ac607`; `git diff` for the path is empty, so the inversion teeth-check was fully restored |
| Assertions non-inverted | Yes — all four load-bearing expectations are in their asserting form: `brewTransitionsWhileNpmIsHeld == 1` (L229), `npmLocator.callCount == 1` (L233), `npm.state == .disabled` (L234), `brewRepublicationsAfterRelease == 0` (L250) |
| Passed at runtime | Yes — package log line 5431, passed after 2.167s |
| Production untouched | Yes — no production file changed (see "Remediation scope" below) |

**Scenario fidelity — faithful, clause by clause:**

| Spec clause | Implementation in the test |
|---|---|
| GIVEN an npm evaluation that does not answer until released | `FakeNpmLocator(results: [detected], gated: true)`; `detect` records the call, then parks on `TestPoll.until(isOpen)` until `release()`. `async let npmEvaluation = npm.refresh()` + `waitForCalls(atLeast: 1)` proves the probe is genuinely in flight, not merely queued |
| and a brew re-evaluation requested meanwhile | `await brew.refresh()` on a separate `BrewDetectionStore` with its own `FakeBrewLocator`, issued while the npm gate is still shut |
| WHEN the brew evaluation completes | `brew.state == brewDetected` |
| THEN brew observers receive their transition before the npm evaluation is released | `withObservationTracking` counts exactly **1** brew transition; the "before release" half is pinned by asserting, in the same window, that npm has not answered: `npmLocator.callCount == 1` (called, still parked) and `npm.state == .disabled` |
| AND releasing npm republishes no brew state | A **second** tracking closure is registered (`withObservationTracking` is single-shot, so reusing the first would silently observe nothing), then `npmLocator.release()`; afterwards `npm.state == detected` proves npm did transition, while `brewRepublicationsAfterRelease == 0` and `brewLocator.callCount == 1` prove brew neither republished nor re-probed |

Two details make this test honest rather than vacuous. First, `npm.state == .disabled` is a real "npm has
not answered yet" proxy, not a switch artefact: `NpmDetectionStore.state` initialises to `.disabled` and is
only reassigned at the end of `refresh()`, and because `isEnabled` is set through the initialiser (where
`didSet` does not fire) the store performs no probe of its own — the single recorded call is the explicit
`refresh()`. Second, the `brewDetected` fixture is built locally in the suite with a comment explaining
why: sharing it with `BrewDetectionStoreTests` would be the first quiet coupling between the two
detections the requirement forbids.

`tasks.md` task 1.11 was reworded to name BD-A1 scenario 1 **and** scenario 2, closing the task-text gap
that caused the original miss.

---

### Remediation scope — no production file touched

| Area | Staged insertions | Versus prior verify |
|---|---|---|
| `Packages/*/Sources` | 2,874 | unchanged |
| `cellar/` | 868 | unchanged |
| **Production total** | **3,742** | **identical to the prior report's 3,742** |
| `Packages/*/Tests` + `cellarTests/` + `cellarUITests/` | 6,764 | 6,701 + 63 remediation test lines |
| `openspec/` | 1,654 | +74 (task line + artifact prose) |

Staged file count is **127**, the same as the prior run: the remediation modified an existing test file
rather than adding one. Zero `.xcodeproj` paths staged. The production figure matching the prior report
line-for-line is the direct evidence that the remediation was test-only.

---

### Completeness

| Dimension | Result |
|---|---|
| Proposal / design / specs / tasks present | Yes — all four dimensions verified |
| Tasks ticked | **57/57**, zero unchecked |
| Every RED task's named test file exists | **29/29** named files present on disk |
| Spec requirements | 24 across 9 capability files (1 new + 8 deltas) |
| Spec scenarios | 72 |
| Requirements fully covered by passing tests | **24/24** |
| Scenarios covered by a test that passed at runtime | **72/72** |

---

### Test evidence (both suites re-executed in this phase)

| Command | Exit | Result |
|---|---|---|
| `swift test --package-path Packages/CellarCore` | 0 | **2128 tests in 244 suites passed**, 1 known issue (pre-existing) |
| `xcodebuild test -project cellar.xcodeproj -scheme cellar -destination 'platform=macOS,arch=arm64'` | 0 | `** TEST SUCCEEDED **` — cellarTests **365 case executions / 354 unique tests, 0 failed**; cellarUITests **38 tests, 0 failures** |

Both match the expected baselines exactly: 2128/244 (up one from the prior run's 2127, which is the single
added C1 test), and cellarUITests 38. The one known issue is the pre-existing
`OperationCenterCancelTests.swift:195` expectation, unchanged.

**Known flakes did not recur.** Neither load-dependent flake reported in `apply-progress` —
`CatalogFootprintTests` "full-catalog footprint stays within its recorded bound" and
`MutationRefreshReceiptTests` "Every tap terminal refreshes its declared domains exactly once" — failed in
this run, so no isolation re-run was required. Zero failed test cases across both suites.

---

### Spec compliance matrix

Requirement IDs follow the `tasks.md` map (spec headings carry no short IDs). Every row below was proven by
tests that passed at runtime in this phase.

#### npm-source — NEW, 10 requirements / 26 scenarios

| ID | Requirement | Covering tests (all passed) | Status |
|---|---|---|---|
| NS1 | Opt-in, off by default, nothing npm while off | `NpmDetectionStoreTests` "never enabled publishes disabled and probes nothing", "Enabling starts detection without a relaunch", "Disabling clears the detected state and stops probing"; `NpmInstalledStoreTests` "With the npm source never enabled the inventory is byte-identical to brew's" | PASS 2/2 |
| NS2 | One npm by priority; configured path never falls through | `NpmLocatorTests` "Detection stops at the first candidate that validates", "Homebrew's npm outranks every version manager", "The manager order is Volta, then fnm, then nvm, then mise", "The newest installed Node wins under nvm and under mise", "A configured path that is not npm reports notNpm and does not fall back", "A configured path that exists but is not executable is distinct from a missing one", "No npm anywhere is a soft absent signal", "Validation runs exactly two read-only npm invocations and nothing else" | PASS 4/4 |
| NS3 | Detected npm exposes path, version, global prefix | `NpmSettingsCompositionTests` "A detected npm discloses its path, version, prefix and origin"; `BrewIntegrationTests` "Detection finds the real npm and reports its version, prefix and origin" | PASS 1/1 |
| NS4 | Environment prepends bin dir, inherits only PATH+HOME, seven pins | `NpmEnvironmentTests` "The composed keys are exactly PATH, HOME and the seven pins", "The seven pins carry exactly these values, and a hostile parent cannot move them", "No Homebrew key is ever set for an npm invocation", "The selected npm's bin directory is prepended to the inherited PATH", "A parent with no PATH still gets the bin directory"; `BrewIntegrationTests` "npm ls -g … no escape byte" (integration, self-skipping) | PASS 2/2 |
| NS5 | `ls -g --json --depth=0`, incl. exit-1 payload | `NpmPayloadTests` "Exit 0 with a document is accepted", "Exit 1 with a parseable document is accepted — npm's ELSPROBLEMS case", "Exit 1 with unparseable stdout is a failure, never an empty inventory", "A document on stderr only is a failure, not an inventory", "Only stdout enters the document"; `NpmDecodeTests` "Every dependency key becomes one global package", "The prefix's own record is not a package" | PASS 3/3 |
| NS6 | `outdated -g --json`, exit 0/1, tri-state freshness | `NpmDecodeTests` "A package is outdated exactly when current differs from latest", "wanted is preserved but never decides outdatedness", "Not checked, fresh-and-clean, and failed are three distinct states", "Only a fresh state reads as up to date when nothing is outdated"; `NpmPayloadTests` "Outdated accepts exit 0 and exit 1 alike", "Outdated with blank stdout at exit 1 is a failure", "An offline run is a network failure rather than a generic one" | PASS 4/4 |
| NS7 | Cadence independent of brew activation | `NpmRefreshCoordinatorTests` "Five activations re-list npm and never check it; one period later, exactly one check", "Each npm terminal outcome forces exactly one listing and one check", "An explicit refresh reads both, and overlapping ones coalesce into one check", "A failed check is left failed until the next period, never retried in a loop", "The minimum interval between registry checks is one hour"; `NpmInvalidationTests` "An npm terminal produces one ls and one outdated, and no brew probe" | PASS 2/2 |
| NS8 | Two npm commands, fixed argv, validated names | `NpmCommandTests` "Upgrade and uninstall lower to exactly their two fixed vectors", "The latest spec is a single argv element built once in the wrapper", "A scoped name survives into both vectors intact", "Uninstall requires confirmation and upgrade does not", "The npm command file is covered by the shipped structural argv scan", hostile-name rejection case; `MutationSourceProjectionTests` "An npm uninstall confirmation presents the exact npm command" | PASS 5/5 |
| NS9 | npm's own outcome signatures, never brew's | `NpmClassificationTests` "Exit 0 is a success whatever npm printed", "EACCES on a non-zero exit is the typed needs-privileges failure", "EPERM reaches the same typed needs-privileges failure", "The captured offline report classifies as a network failure", "An unrecognised non-zero exit is a generic failure naming npm", "npm's codes never classify a brew run" | PASS 2/2 |
| NS10 | No npm mutation while disabled/absent/invalid | `OperationCenterSourceRoutingTests` "Availability and guidance are evaluated per source", "npm mutations become available the moment npm is attached" | PASS 1/1 |

#### Deltas — 14 requirements / 46 scenarios

| ID | Requirement | Covering tests (all passed) | Status |
|---|---|---|---|
| II-A1 | npm globals enter the one inventory under `(npm, name)` | `NpmInstalledStoreTests` (12 tests incl. "An npm contribution joins the brew snapshot in one inventory", "A failed brew acquisition leaves the npm rows in place", "Turning the npm source off removes exactly the npm rows"); `PackageSourceTests` "An npm identity survives a coding round trip"; `NpmHistoryTests` "The npm kind travels through the existing kindRaw column"; `CatalogTests/NpmKindExhaustivenessTests` (5) | PASS 4/4 |
| II-A2 | Source filter + NPM tag as CellarCore projections | `NpmSourceFilterTests` "The npm source narrows to npm entries…", "The source control is unavailable with a typed reason and filters nothing", "The tag follows kind and nothing else"; `NpmInstalledChromeTests` (9) | PASS 3/3 |
| II-A3 | Per-source updates summary; unchecked npm never up to date | `NpmSourceFilterTests` "Brew clean and npm offline is not up to date", "Both sources fresh and clean is up to date", "npm off omits npm from the summary entirely", "A snoozed npm package leaves the npm count and the outdated set" | PASS 4/4 |
| PM-A1 | Every spine command projects its source; erased form preserves it | `MutationSourceProjectionTests` "Existing families default to Homebrew and npm declares npm", "The erased form equals the unerased one in source and display command" | PASS 1/1 |
| PM-A2 | A brew argv can never name an npm package | `NpmCommandTests` "Every brew package verb is unavailable for an npm identity", "A Homebrew identity can never become an npm target"; `NpmBulkSelectionTests` "A mixed bulk upgrade fans out by source in selection order", "Pin, unpin and reinstall never see an npm identity", "Upgrade all stays a bare brew upgrade with no npm fan-out" | PASS 3/3 |
| PM-A3 | Mutations serialized across sources through one FIFO | `CrossSourceFIFOTests` (7 tests incl. "A brew mutation waits for an in-flight npm mutation", "A read of either source proceeds during an npm mutation") | PASS 2/2 |
| PM7 (MOD) | Availability per source; no-runner submission is a launch failure | `OperationCenterSourceRoutingTests` "Availability and guidance are evaluated per source", "An npm submission with no npm runner settles as one launch failure"; four shipped scenarios remain covered by `OperationCenterProjectionTests`/`OperationCenterTests`, all green in this run | PASS 6/6 |
| BE-A1 | Runner generalised over executable + environment composer | `RunnerGeneralisationTests` (6) incl. "The brew convenience initializer spawns brew under the pinned brew environment", "A brew runner and an npm runner never spawn each other's executable", "The runner reaches the brew environment composer only in its convenience initializer" | PASS 3/3 |
| OA-A1 | Activity items carry source; prefix derives from it | `MutationSourceProjectionTests` "An npm activity item carries npm's source in every state", "A brew activity item is unchanged", "An erased npm command never renders or copies as a brew command", "The idle summary names no source" | PASS 3/3 |
| IH-A1 | npm history rows, namespaced verbs, source-aware presentation | `NpmHistoryTests` (8) incl. "Each npm verb writes one identity-bearing row", "Presentation is source-aware", "npm entries are searchable by source, verb, name and argv", "A row whose kind this build does not know decodes as absent" | PASS 4/4 |
| **BD-A1** | **npm detection is a sibling state model and widens nothing in brew's** | sc1 "Brew's vocabularies are unchanged" → `NpmDetectionStoreTests` "The brew detection store still starts absent and knows nothing of npm". sc2 "The two evaluations do not couple" → `NpmDetectionStoreTests` **"A held npm evaluation neither delays a brew transition nor republishes brew when released"** | **PASS 2/2** |
| MB-A1 | Status item counts both sources, says when npm was not checked | `MenuBarCompositionTests` "Outdated npm packages reach the count and the entries, by delegation", "An offline npm is stated and never rendered as up to date", "The disclosure appears exactly when npm has something outdated", "With the source off the projection is identical to the shipped one" | PASS 3/3 |
| MB1 (MOD) | Pure projection, four inputs, delegates outdated-ness | `MenuBarProjectionTests` (4 shipped scenarios, incl. "The projection has no effectful dependency and is equal composed twice"); `MenuBarCompositionTests` "The projection takes four inputs and none of them is effectful" plus the three-freshness sweep | PASS 5/5 |
| SH-A1 | Outdated row names both sources; score counts Homebrew only | `HealthCompositionTests` "The row announces the merged count and says npm was not checked, naming the network", "Three fresh outdated npm packages change the score in neither direction", "With the source off the row and the score are the shipped ones", "The remediation stays Homebrew's and its copy claims nothing about npm" | PASS 3/3 |

**Unmapped requirements: none. Unmapped scenarios: none.** Coverage is 24/24 and 72/72.

---

### Safety invariants

Carried forward from the prior run and unaffected by a test-only remediation; all re-confirmed green by
this run's suites.

| Invariant | Method | Result |
|---|---|---|
| No interpolation in any `*Command.swift` `arguments` | Shipped structural scan `MutationCommandTests:289` globs `Sources/BrewClient/*Command.swift` and forbids `\(`, `joined(`, `components(separatedBy:`, `split(`, `+ " "`; `NpmCommand.swift` is picked up by the glob, asserted explicitly by `NpmCommandTests` "The npm command file is covered by the shipped structural argv scan" | PASS — `arguments` is two literal vectors plus `target.latestSpec`/`target.name`; `latestSpec` built once in `NpmPackageTarget.init?` |
| `PackageTarget.init?` rejects `.npm` | Source read + `NpmCommandTests`, `NpmKindExhaustivenessTests` | PASS — `guard id.kind.source == .homebrew, MutationName.isSafe(id.name)`; `MutationCommand.vector`'s `.npm` arm is `preconditionFailure`, unreachable |
| `NpmEnvironment` inherits only PATH/HOME + allow-listed pins | Source read + `NpmEnvironmentTests` | PASS — `inheritedKeys = ["PATH","HOME"]`, `pinned` is exactly the seven required keys, merged last so a hostile parent cannot move them; no `HOMEBREW_*` |
| `npm outdated` exit 1 accepted only with parseable JSON | Source read of `NpmPayloadSource` + `NpmPayloadTests` | PASS — `acceptingExitOne: true, blankAtZero: "{}"`; blank stdout at exit 1 is a failure, blank at exit 0 is the empty report |
| Offline never yields "up to date" | Source read + `NpmFreshnessCopyTests`, `NpmStoreTests`, `NpmSourceFilterTests` | PASS — structural, not conditional: `upToDateCopy` is `String?` and absent unless `isUpToDate`, which requires a **completed** check. There is no zero for a view to misread |
| Toggle off leaves brew surfaces unchanged | `PackageKind.allCases` audit across production; byte-identity tests | PASS — **zero** `PackageKind.allCases` iterations exist anywhere in production. Confirmed by `NpmInstalledStoreTests` "byte-identical to brew's", `MenuBarCompositionTests` "identical to the shipped one", `HealthCompositionTests` "the row and the score are the shipped ones" |
| Grouped upgrade-all is bare `brew upgrade` with disclosure | Source read of `MenuBarPopoverView.upgradeRow` + `NpmBulkSelectionTests` | PASS — verb unchanged (`MutationCommand.upgradeAll`, plain `brew upgrade`, no fan-out); the scope note renders as a separate `projection.npmUpgradeDisclosure` line with identifier `menu-bar-npm-disclosure` |
| Brew and npm detection do not couple | **NEW this run** — `NpmDetectionStoreTests` "A held npm evaluation neither delays a brew transition nor republishes brew when released" | PASS — a held npm probe delays no brew transition, and its release republishes no brew state |

---

### Unit-1 defect fix, applied under unit 3

The GUI-launch "npm not detected" defect (symlink resolution feeding the `PATH` prepend) is fixed and
covered:

- `NpmEnvironment.binDirectory` is a **stored** property (design D5 lists it as a member), defaulting to
  the executable's own directory.
- `DefaultNpmLocator.validate(_:binDirectory:origin:)` takes the directory explicitly; **both** call sites
  pass the candidate's own directory, while identity still follows `probe.resolvingSymlinks(at:)`.
- **Symlinked-candidate tests exist and pass**: `NpmLocatorTests` "A symlinked candidate is validated at
  its real path", "A symlinked candidate keeps the directory it was found in on PATH", "A plain
  candidate's launch directory is its own directory".
- NS4 scenario coverage is intact.

Verdict: **confirmed, correct, and covered.** Do not revert.

---

### Design conformance

Eight deviations are recorded (four in Engram `gate-notes` #7973, four in `apply-progress` #7975). All
eight were located in the code and are spec-driven; each is **accepted**. The C1 remediation introduced no
ninth deviation — it changed no production code.

| # | Deviation | Recorded in | Verified |
|---|---|---|---|
| 1 | Namespaced verbs `npmUpgrade`/`npmUninstall` instead of D14's bare names | gate-notes | Yes — `NpmCommand.verb`; required by the `installation-history` delta |
| 2 | New `MutationOutcome.networkUnavailable` case | gate-notes | Yes — `NpmCommand.classify`; NS9 requires a message naming a network reason |
| 3 | `OperationCenterBulk.commands(for:over:)` returns `[AnyBrewMutation]` | gate-notes | Yes — so npm members are never silently dropped |
| 4 | `cellar/History/HistoryRow.swift` touched for source badge + `npm`/`brew` prefix | gate-notes | Yes — required by IH-A1's presentation clause |
| 5 | `HomeAttentionCopy` + `InstalledEmptyState.isNpmEmptiness` app-target extractions | apply-progress | Yes — moves two user-visible claims out of `body` so they are testable; rendering stays in the view |
| 6 | `InstalledBrowse.withNpmSource(_:)` | apply-progress | Yes — keeps the single browse expression MB1's cross-surface test pins |
| 7 | Health score denominator Homebrew-only (not just numerator) | apply-progress | Yes — SH-A1's "ignores npm in both directions" scenario forbids anything else |
| 8 | Sixth `MenuBarProjection` stored member (`updates`) | apply-progress | Yes — MB1's Mirror roster restated, not relaxed; MB1's "four pure inputs" is satisfied |

**Deviations found but NOT recorded: none.** `cellar/Settings/NpmSourcePreference.swift` sits in the app
target but is *not* a deviation: NS1 names the `AutomaticUpdateChecks(defaults:)` precedent by hand and
that type also lives in the app target, so the placement is spec-mandated.

---

### Rules

| Rule | Result |
|---|---|
| Logic in CellarCore; app target views/DI only | PASS — all 7 new `BrewClient` files and 4 new `BrewProcess` files are package code. The 3 new app-target files are a `@AppStorage`-backed preference (spec-mandated precedent), a Settings view, and a copy projection extracted for testability (recorded deviation 5) |
| No `cellar.xcodeproj` diff | PASS — zero `.xcodeproj` paths in the staged diff (127 files). `PBXFileSystemSynchronizedRootGroup` makes this possible for new app files |
| English neutral strings | PASS — all new UI copy is neutral professional English. No regional or colloquial forms. No `Localizable.xcstrings` exists; the only catalog is `cellar/InfoPlist.xcstrings` (English-only) and needs no entry |

---

### TDD compliance

| Check | Result | Details |
|---|---|---|
| TDD evidence reported | Partial | A "TDD cycle evidence" table exists in `apply-progress.md` for **Batch 2 / unit 2** (tasks 2.1–2.18) only. Batches 1 and 3 carry prose only. See W1 |
| All tasks have tests | Pass | 57/57 tasks ticked; every RED task names a test file and all 29 named files exist |
| RED confirmed (tests exist) | Pass | 29/29 named files present; batch 2's table records concrete RED failures; unit 3's defect section records the two RED locator tests and their exact pre-fix value |
| GREEN confirmed (tests pass) | Pass | Both suites re-executed in this phase: 0 failures across 2128 package tests, 354 app tests and 38 UI tests |
| Triangulation adequate | Pass | Multi-case coverage throughout: 4 network codes + 2 privilege codes in classification, 7 rejected name shapes, 7 locator priority orderings, 3 freshness states swept through every copy surface, both fan-out orders |
| Safety net for modified files | Pass | Batch 2's table records running counts before each modification; "N/A (new)" only appears for genuinely new files |

**C1 remediation TDD classification.** `apply-progress` records the Approval Testing path rather than a
new-behaviour RED, which is the correct call: production was already right, so an honest first run of the
new test is GREEN. The teeth were proved by temporarily inverting the four load-bearing expectations,
observing exactly four failures with real values (`brewTransitionsWhileNpmIsHeld → 1`,
`npmLocator.callCount → 1`, `npm.state → .disabled`, `brewRepublicationsAfterRelease → 0`), then restoring
the file byte-for-byte. This run independently confirms the restoration: the staged blob and the worktree
hash identically and every assertion is in its non-inverted form.

**Assertion quality**: no tautologies, no orphan empty-collection assertions, no ghost loops, no
smoke-test-only cases, and no mock-heavy files across the 32 changed/added test files. The new C1 test is
clean by the same standard: every `#expect` asserts a concrete observed value, both zero-valued assertions
(`brewRepublicationsAfterRelease == 0`, and the held-window `npm.state == .disabled`) are paired with
companion non-zero/positive assertions in the same test that prove the mechanism was live, and the test
calls production code on both stores.

### Test layer distribution

| Layer | Tests | Files | Tool |
|---|---|---|---|
| Unit | ~331 npm-related | 30 | Swift Testing |
| Integration (real npm, self-skipping) | 3 | 1 (`BrewIntegrationTests`) | Swift Testing |
| UI (E2E) | 1 flow (part of 38) | 1 (`NpmSourceToggleUITests`) | XCUITest |

Coverage analysis: skipped. `openspec/config.yaml` sets `threshold: 0` and no per-file coverage report was
produced for this run. Not a failure.

### Quality metrics

**Linter**: `swiftlint 0.65.1`, informational only — `openspec/config.yaml` itself records "no
`.swiftlint.yml` in repo", and SwiftLint is not wired into any build phase or CI. New-code findings on the
files this change adds: **61** (1 error, 60 warnings), one more than the prior run — the remediation added a
single `vertical_whitespace` warning at `NpmDetectionStoreTests.swift:254` (two consecutive blank lines
between the new test and the one after it). Modified pre-existing files carry 24 baseline findings at
`HEAD`, which pre-date this change.
**Type checker**: `swiftc`, compiler-enforced — both suites compiled and ran clean.

---

## Issues

### CRITICAL

**None.** C1 is closed (see the remediation section above).

### WARNING

**W1 — Strict TDD cycle evidence covers only 18 of 57 tasks.** *(carried forward)*
`apply-progress.md` carries a per-task RED/GREEN/TRIANGULATE/SAFETY-NET table for Batch 2 only. Batch 1
(28 tasks) has prose plus an explicit note that the apply worker was interrupted by a provider rate limit
after reporting green, so the orchestrator wrote the file from on-disk state. Batch 3 (11 tasks) has a
"Delivered" narrative and a detailed defect section, but no table. The **substance** of TDD is
independently verifiable — every RED task names a test file, all 29 exist, and all pass at runtime — so
this is a reporting-protocol gap rather than evidence that TDD was skipped. Worth closing at archive by
backfilling the two tables.

**W2 — Spec artifact scenario count drift.** *(carried forward)*
The Engram `sdd/npm-package-source/spec` summary (#7972) states npm-source is "10 req / 24 sc". The
canonical file `specs/npm-source/spec.md` contains **26** scenarios. The canonical file is authoritative
and all 26 were mapped; the Engram summary should be corrected at archive so downstream totals do not
inherit the wrong number. Whole-change authoritative totals are **24 requirements / 72 scenarios**.

### SUGGESTION

**S1 — The apply-progress SwiftLint claim understates new findings.** *(carried forward, count updated)*
`apply-progress.md` records "Nothing else new." The scan finds **61** default-rule findings on files this
change adds (was 60 before the remediation, which added one `vertical_whitespace` warning). Non-blocking:
no config, not in CI, and 46 of them are `trailing_comma` in test collection literals. Either fix the
sweep or restate the claim. The stray blank line at `NpmDetectionStoreTests.swift:254` is a one-character
cleanup worth taking at archive.

**S2 — cellarTests count drift between apply and verify.** *(carried forward)*
`apply-progress.md` reports cellarTests "328 passed". Both verify runs observed 365 case executions across
354 unique identifiers, 0 failed, on the same tree. This is a measurement-method difference (raw
`xcodebuild` log lines vs. Xcode's own summary), not a regression. Recording the counting method alongside
the number would remove the ambiguity.

**S3 — Total changed lines remain far above the nominal budget.** *(carried forward, not a finding)*
Production is 3,742 lines, comfortably inside the accepted 8,000 `size:exception` under the maintainer's
production-only ruling. Total code + tests + fixtures is now 10,506, and 11,987 including `openspec/`.
Already flagged by apply and explicitly ruled on; recorded here for the archive record only.

---

## Final verdict

**PASS WITH WARNINGS** — 0 CRITICAL, 2 WARNING, 3 SUGGESTION.

All **72 of 72** specified scenarios across **24 of 24** requirements are proven by tests that passed at
runtime in this phase. The C1 blocker is closed by a faithful, honest, additive test that changed no
production code — confirmed by the production line count matching the prior verify exactly. Every safety
invariant holds, and the non-coupling of brew and npm detection is now a runtime proof rather than a
structural argument. All eight design deviations remain recorded and spec-justified, all 57 tasks are
complete, and both suites are green with zero failures and no recurrence of the two known load-dependent
flakes.

The two remaining warnings are documentation-hygiene items for the archive phase (backfill the two TDD
tables; correct the Engram spec count). Neither blocks archive.

**Next**: `sdd-archive`.
