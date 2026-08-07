```yaml
schema: gentle-ai.verify-result/v1
evidence_revision: sha256:c4b38166f15a9d5d9ddf1cda499f542cc1876def9a655129a3042abfbcb6d99d
verdict: pass
blockers: 0
critical_findings: 0
requirements: 15/15
scenarios: 80/80
test_command: swift test --package-path Packages/CellarCore
test_exit_code: 0
test_output_hash: sha256:2d7d8fc20f46cce6461294570876436da07dda576d6b2571e5f69b205f635639
build_command: xcodebuild build -project cellar.xcodeproj -scheme cellar -destination 'platform=macOS,arch=arm64'
build_exit_code: 0
build_output_hash: sha256:a83cbc6efa5ad89884de9747d6bb12827c9edfb364d17bb04b6ccf0400912484
```

## Verification Report

**Change**: m5-health
**Version**: specs rev 2 (obs #7535) — `system-health` ADDED-only 11 req / 51 sc; `installed-inventory` 2 MODIFIED / 15 sc; `local-package-metadata` 2 MODIFIED / 14 sc. **Re-counted from the delta files this run: 15 requirements, 80 scenarios.**
**Mode**: Strict TDD
**Baseline**: `7d48779` working tree, uncommitted (RDD disabled, nothing committed)

### Revision history

| Rev | Verdict | Req | Scen | CRITICAL | WARNING | SUGGESTION | Note |
|---|---|---|---|---|---|---|---|
| 1 | **FAIL** — real defect | 13/15 | 77/80 | 1 (SH11 sc1/sc3 untested) | 2 | 2 | `evidence_revision` `sha256:8d0bd70d…`, blockers 1 |
| 2 | **FAIL** — zero defects, one scenario short of complete evidence | 14/15 | 79/80 | 0 | 1 | 3 | `evidence_revision` `sha256:39f18909…`, blockers 1 (SH4 sc3 PARTIAL) |
| 3 | **PASS WITH WARNINGS** | **15/15** | **80/80** | 0 | 1 | 5 | This revision. Focused re-verify after the user-chosen integration-test route (generation 6, 191 lines) |

**Both prior FAILs are preserved deliberately.** Rev 1's remediation and rev 2's rescope were each
authorized *against* the failed evidence revision above them; a report that erased either would hide
what was bought. Rev 1 failed on a live untested seam. Rev 2 found zero defects and failed only because
the admission gate refuses a passing verdict against incomplete scenario evidence. Rev 3 is the first
revision where the evidence is complete.

### What rev 3 re-checked

This is a **focused re-verify**. Everything closed at rev 1 and re-validated at rev 2 — the SH11
remediation chain, the D4 comment/assertion contradiction, the mutation-proof corroboration, the binding
invariants, the design-coherence table — is carried forward unchanged and not re-derived. Rev 3
re-checked exactly four things: the new integration test read critically, the full FAST suite, the
build, and the task/record state.

### Completeness

| Metric | Value |
|--------|-------|
| Tasks total | 71 |
| Tasks complete | 71 |
| Tasks incomplete | 0 |

Re-counted from `tasks.md` this run: **71 `- [x]`, zero `- [ ]`**. Batch 4 added no task and re-ticked
none, matching apply-progress.

**A batch-4 risk claiming a `tasks.md` 13.3 inconsistency is incorrect, and is dismissed here on
evidence.** `tasks.md:174–177` carries 13.3 as `[x]` with an inline annotation recording that every
user-facing string was presented verbatim to the user on 2026-08-07 and **accepted as-is with no
rewording**, and that the same round ruled F13. The checkbox and its annotation agree. 71/71 stands.

### Build & Tests Execution — re-run in full this phase

**Build**: ✅ `xcodebuild build -project cellar.xcodeproj -scheme cellar -destination 'platform=macOS,arch=arm64'` → `** BUILD SUCCEEDED **`, exit 0.

| Suite | Command | Result | Exit |
|---|---|---|---|
| FAST | `swift test --package-path Packages/CellarCore` | ✅ **1,656 tests / 199 suites passed**, 1 known issue | 0 |
| Focused | `swift test --package-path Packages/CellarCore --filter DoctorIntegrationTests` | ✅ **1 test / 1 suite passed**, 1.804 s | 0 |

Focused-run output digest: `sha256:fffd77a13cecf07fc85f617f8abcf32caf72be6018569688b466a16cf056abb1`.

**Counts confirmed exactly as forecast: 1,656 / 199**, up from rev 2's 1,655 / 198 — **+1 test, +1
suite, and nothing else moved.** Zero failure glyphs anywhere in the FAST log. The 1 known issue is the
recorded pre-existing one; the 1 skipped test is the recorded `p95 as-you-type latency` performance
case. **No regression.**

APP (`xcodebuild test -only-testing:cellarTests`) and FULL (`cellarUITests`) were **not re-run this
phase and are not claimed**. Batch 4 touches no app-target file — the only new file lives under
`Packages/CellarCore/Tests/` — so rev 2's APP evidence (`TEST SUCCEEDED`, 146 cases, 0 failed) and rev
1's FULL evidence are carried, not refreshed. Stated rather than papered over.

**Coverage**: ➖ threshold 0 in `openspec/config.yaml`; no coverage tool run.

### SH4 sc3 — the one scenario rev 2 could not close, read critically

**Scenario (verbatim, `specs/system-health/spec.md:216–220`)**: *"GIVEN the last-update reading taken
before a doctor run, WHEN doctor runs and the reading is taken again, THEN it is unchanged."*

The covering test is `Packages/CellarCore/Tests/BrewClientTests/DoctorIntegrationTests.swift`
(111 lines, 1 `@Test`, sha256 `13b0c685…`). Rev 3 read it against the shipped source rather than
against its own doc comments.

#### Does it exercise the shipped path, or a re-implementation of it?

| Claim | Verified against source | Finding |
|---|---|---|
| Marker resolved by the **shipped** locator | `HomebrewRepositoryLocator.repository(for:access:)` + `.fetchMarkerName` (`HomebrewUpdateReader.swift:77`, `:93–103`) | ✅ The test never spells out `FETCH_HEAD` or a `.git` path. It calls the same two-candidate probe the app calls |
| Read by the **shipped** reader | `HomebrewUpdateReader.lastUpdate(roots:now:access:)` (`:126–146`) | ✅ Same entry point `HealthStore` uses. It holds no cache — each call re-reads through the `FileMetadataAccess` seam — so `after` is a genuinely fresh read, not a memoized `before` |
| Doctor run through the **shipped** command path | `BrewDoctorSource().run(using:)` (`DoctorSource.swift:43–80`) with its default `SystemProcessLauncher` | ✅ Real spawn, real argv `DoctorCommand.command.arguments`, real classification. No spy, no fake launcher |
| The `HOMEBREW_NO_AUTO_UPDATE` pin is **asserted, not re-applied** | Test `:84–86` builds `BrewEnvironment.current(commandOverrides: DoctorCommand.command.environmentOverrides)`; `DoctorSource.swift:49–51` builds **the same expression, token for token** | ✅ This is the sharpest thing in the file. The test reads the exact environment the production run composes, so a regression dropping the pin fails the assertion instead of being masked by a test that set it itself |

#### Are the three vacuity refusals real?

| Refusal | Test line | Would it actually bite? |
|---|---|---|
| Unresolved marker | `#expect(before.date != nil, …)` `:95` | ✅ Yes. `.absent == .absent` holds on a machine with no Homebrew — the exact vacuous pass this scenario invites. This forbids it |
| Doctor never completed | `try #require(outcome.evidence, …)` `:101` | ✅ Yes. `.unavailable` is the only arm carrying no evidence (`DoctorSource.swift:72–76`), and it is reachable only by cancellation or signal — neither of which describes a completed run. A marker that did not move because nothing spawned cannot pass |
| Completed but wrote nothing | non-empty `rawStdout` or `rawStderr` `:102–105` | ✅ Yes |

#### Is the suite gate honest?

`.enabled(if: hasRealBrew && fetchMarker != nil)` plus the `.realBrew` tag — the idiom
`BrewProcessTests/BrewIntegrationTests.swift` already established in this project. A machine without
Homebrew **skips rather than fails**, which is the right trade.

The gate takes a documented shortcut: it builds `HomebrewRoots` from the hardcoded binary path because
it must be synchronous and `DefaultBrewLocator.detect` is `async`. Rev 3 verified the shortcut is
genuinely inert — `HomebrewRoots.swift:11` derives `prefix` from `installation.executableURL` alone, so
the `prefix: .appleSilicon` and `version:` arguments the gate passes are never read on this path — **and**
the test re-resolves the marker from the *detected* installation and asserts the two agree (`:74–78`),
so the shortcut cannot widen what is observed even if that derivation changed.

#### Did it actually run, or silently skip?

This is the question that decides the rating, so it was checked in the log rather than assumed.

- FAST log line 4479: `Test "Running doctor does not move the last-update reading" passed after 3.004 seconds`
- FAST log line 4480: `Suite "Real Homebrew doctor integration" passed after 3.020 seconds`
- Focused run: `Test run with 1 test in 1 suite passed after 1.804 seconds`

**Passed, not skipped**, in both runs. The 1.8–3.0 s durations are consistent with probe U10's measured
2–3 s real `brew doctor` spawn and are impossible for a test that short-circuited.

#### Independent corroboration, outside the test's own assertion

Rev 3 observed the marker directly rather than relying only on the test's verdict:

- `/opt/homebrew/.git/FETCH_HEAD` — 54 KB, mtime **2026-08-07 07:45:27.242812383 +0200** = `05:45:27 UTC`.
- That is **byte-identical to the date in apply-progress's batch-4 RED evidence** (`.read(2026-08-07 05:45:27 +0000)`), recorded hours earlier.
- It is unchanged after this phase's two further real doctor runs (~15:04 and ~15:05 local).

So the marker has now survived at least four real `brew doctor` runs across two sessions without moving.
That is corroboration the test could not manufacture.

- `/opt/homebrew/Homebrew/.git/FETCH_HEAD` **does not exist on this machine**, so resolution genuinely
  falls through to the second probe candidate. SH5's two-candidate probe order is therefore exercised
  end-to-end against a real installation here, not only against unit fixtures — an unplanned bonus, and
  noted because it strengthens SH5 rather than SH4.

#### Rating

**SH4 sc3 → ✅ COMPLIANT.** The scenario's GIVEN, WHEN and THEN each map to a distinct executed
statement over shipped code, three vacuous passes are explicitly refused, the test passed at runtime in
this verification run, the assertion was proven discriminating by a genuine inverted-assertion RED in
apply, and the marker's own mtime corroborates the result independently. This is an observation, not the
argv argument rev 2 correctly refused to accept as a substitute.

**SH4 → 4/4. Requirements 15/15. Scenarios 80/80.**

### Spec Compliance Matrix

| Requirement | Scenarios | Covering evidence | Result |
|---|---|---|---|
| SH1 non-zero exit is ordinary, document on stderr | 5/5 | `DoctorSourceTests` (13), `DoctorParserTests` | ✅ COMPLIANT |
| SH2 doctor inversion quarantined | 3/3 | `DoctorPayloadQuarantineTests` (both directions, 3 sources × 4 statuses) | ✅ COMPLIANT |
| SH3 evidence preserves bytes, counts ungrouped lines | 6/6 | `DoctorParserTests` (20), `DoctorFixtureManifestTests` (5) | ✅ COMPLIANT |
| **SH4 doctor is a read, fixes nothing** | **4/4** | `DoctorCommandTests`, `DoctorSourceTests`, `HealthCompositionTests` run-doctor copy, **and now `DoctorIntegrationTests` for sc3** | ✅ **COMPLIANT — was 3/4** |
| SH5 last-update reading costs no brew invocation | 4/4 | `HomebrewUpdateReaderTests` (14); probe order additionally corroborated live this run | ✅ COMPLIANT |
| SH6 typed answer, never an invented date | 5/5 | `HomebrewUpdateReaderTests`, `HealthScoringTests` | ✅ COMPLIANT |
| SH7 projection acquires nothing to render | 4/4 | `HealthProjectionTests`, `HealthCompositionTests` | ✅ COMPLIANT |
| SH8 every row states what it does not know | 5/5 | `HealthProjectionTests` × 5 reasons; `HealthCompositionTests` 8 mappings | ✅ COMPLIANT |
| SH9 answered inputs only, unknowns inseparable | 7/7 | `HealthScoringTests` (11) | ✅ COMPLIANT |
| SH10 every weight visible | 4/4 | `HealthWeightsTests` (18) | ✅ COMPLIANT |
| SH11 remediation offers only shipped verbs | 4/4 | `HealthProjectionTests` vocabulary + `HealthRemediationTests` (5) — closed at rev 2 | ✅ COMPLIANT |
| II13 multi-select, bulk-eligible verbs | 11/11 | `BulkSelectionTests`, `BulkFanOutTests`, `ConfirmationDisclosureTests`, `BulkSnoozeTests` | ✅ COMPLIANT |
| II14 label counts the set it submits | 4/4 | `BulkActionBarTests` mixed selection 3/2/1/4 | ✅ COMPLIANT |
| LPM4 snooze scoped to a version | 7/7 | `BulkSnoozeTests` + in-memory `MetadataStore` cross-check | ✅ COMPLIANT |
| LPM5 badge suppression + guard scope | 7/7 | `SnoozeGuardTests` widened, `noSnoozeCallerOutsideThisPackageCanEvadeTheGuard` | ✅ COMPLIANT |

**Compliance summary**: **80/80 scenarios compliant** (77 → 79 → 80), **0 PARTIAL, 0 UNTESTED**.
**15/15 requirements fully compliant** (13 → 14 → 15).

Per-requirement counts re-derived this run by scanning `^### Requirement:` / `^#### Scenario:` in the
three delta files: 11 req / 51 sc + 2 / 15 + 2 / 14 = **15 requirements, 80 scenarios**. The envelope
totals are counted, not inherited.

### Correctness (Static Evidence)

| Area | Status | Notes |
|---|---|---|
| Batch 4 is test-only | ✅ Verified | `git diff --numstat` shows `DoctorIntegrationTests.swift` at **111 additions, 0 deletions**, matching apply-progress's `+111`. Zero production lines added or changed by batch 4 |
| Binding zero-line diffs still hold | ✅ Verified | `Package.swift`, `cellar.xcodeproj/project.pbxproj`, `CatalogFootprintTests.swift`, `HomebrewRoots.swift`, `brew-execution/spec.md` all measure **0 lines**. The new file is SwiftPM-discovered, so pbxproj is untouched as predicted |
| No `CompositionRequestSpy` call site added | ✅ Verified | `DoctorIntegrationTests` uses the real launcher via `BrewDoctorSource`'s default and touches no spy |
| Records updated, not absorbed | ✅ Verified | `design.md:511–517` carries the eighth Apply-Time Amendment naming verify-2's FAIL, the two exits offered, the maintainer's choice and the resulting file; `apply-progress.md:359` opens the batch-4 section |

### Coherence (Design)

Rev 1's and rev 2's coherence tables stand unchanged. One row is added:

| Decision | Followed? | Notes |
|---|---|---|
| SH4 sc3 closed by observation, not by assertion | ✅ Yes | The amendment states the reasoning verify-2 gave, the two exits, and that the maintainer chose the test. The shipped test matches the amendment's description in every particular rev 3 checked |

### TDD Compliance

| Check | Result | Details |
|---|---|---|
| TDD evidence reported | ✅ | Four sections now — batches 1, 2, the verify-1 remediation, and a batch-4 section with its own line budget, RED evidence and rollback |
| All tasks have tests | ✅ | 71/71; batch 4 added no task |
| RED confirmed (tests exist) | ✅ | 19 new test files verified present (18 + `DoctorIntegrationTests.swift`) |
| GREEN confirmed (tests pass) | ✅ | Re-executed this phase: FAST 1,656 pass / 0 fail; the new test named and passed in both the full and focused runs |
| Triangulation adequate | ➖ Single, correctly | The spec has exactly one scenario for this observation. The test carries five assertions over one behaviour rather than five behaviours — the right shape here |
| Safety net for modified files | ✅ N/A (new) | `DoctorIntegrationTests.swift` is genuinely new — 111 additions, 0 deletions. No existing file was modified by batch 4 |
| Non-vacuity proven | ✅ | apply's inverted-assertion RED failed at `:109` after a real 2.453 s spawn, with both readings real `.read` dates rather than a matching pair of non-answers — which is the part that makes the inversion meaningful. Independently corroborated here by the marker's own unmoved mtime |

**TDD compliance**: 7/7 checks passed.

### Test Layer Distribution

| Layer | Files | Notes |
|---|---|---|
| Unit | 12 | Unchanged |
| Structural (source-scan guards) | 5 | Unchanged; each carries a positive anchor **and** a violation control |
| Integration (app composition) | 1 | `HealthCompositionTests` |
| **Integration (real `brew` subprocess)** | **1** | **`DoctorIntegrationTests` — new. Joins `BrewIntegrationTests` in the `.realBrew`-tagged layer `openspec/config.yaml` already declares** |
| E2E (XCUITest) | 1 | `HealthSectionUITests` (rev 1 evidence, carried) |
| **Total new test files** | **19** | 18 at rev 2, +1 |

The tooling is present and detected: this layer runs against the real binary at `/opt/homebrew/bin/brew`
and is excludable from the inner loop with `--skip tag:realBrew`. It is **not** excluded from the
declared FAST command, which is why sc3's evidence appears in the headline suite run rather than only in
a special invocation.

### Assertion Quality

**✅ No banned patterns in the new file.** Zero tautologies, zero ghost loops, zero assertions that never
call production code, zero smoke-tests-only, zero implementation-detail coupling, zero mocks (the file
uses no test double at all — it is deliberately the opposite of mock-heavy).

Every assertion in `DoctorIntegrationTests` was traced to the production symbol it exercises. All five
are load-bearing:

| Line | Assertion | Carries |
|---|---|---|
| 74–78 | detected marker equals gate marker | Closes the gate shortcut |
| 87 | `environment["HOMEBREW_NO_AUTO_UPDATE"] == "1"` | The pin, read from the production expression |
| 95 | `before.date != nil` | Refuses the no-Homebrew vacuous pass |
| 101–105 | evidence present and non-empty | Refuses the never-ran vacuous pass |
| 109 | `after == before` | **The scenario itself** |

One no-severity note: `:74–78` uses `#expect` rather than `#require`, so a gate/detected disagreement
would record a failure and continue rather than halt. The test still fails either way, so this is a
style observation, not a finding.

Rev 2's single assertion-quality SUGGESTION (three entailed assertions in
`aCleanupRemediationKeepsItsOwnersConfirmation`) is unchanged and carried below.

**Assertion quality**: 0 CRITICAL, 0 WARNING, 1 SUGGESTION (carried).

### Quality Metrics

**Linter**: ⚠️ SwiftLint clean on the new file (exit 0, zero violations). Two warning-level findings in
change-touched code that rev 2 did not record are raised below as SUGGESTIONs 4 and 5. Note there is
**no `.swiftlint.yml` in this repository**, so all thresholds are SwiftLint defaults.

**Type checker**: ✅ `** BUILD SUCCEEDED **`, exit 0.

### Issues Found

**CRITICAL**: None. Rev 1's CRITICAL was closed at rev 2 and re-validated there; rev 3 found no new one.

**BLOCKER**: None. Rev 2's sole blocker — SH4 sc3 lacking a runtime observation — is closed.

**WARNING** (1)

1. **`cellar/cellarApp.swift`'s initializer is past the lint limit.** Re-measured this run:
   `function_body_length` **156 lines against a limit of 100** (`cellarApp.swift:164`), an error-level
   SwiftLint rule. Carried unchanged from rev 1 and rev 2.
   **Rev 3 verified the "pre-existing" claim rather than repeating it**: linting the `HEAD` (`7d48779`)
   copy of the file shows the initializer already spanned **142 lines**, the file already 462 lines
   (limit 400) and the struct body already 260 (limit 250). So the violation genuinely predates this
   change, which adds **+14 lines** to an already-violating initializer. Pre-existing is the correct
   characterisation — and this composition root has now been pushed further by five consecutive slices.
   It should be extracted before M6 adds to it again.

**SUGGESTION** (5)

1. **F12 remains open**: `DiskUsageSnapshot` encodes non-deterministically because
   `[DiskArea: DiskRootState]` serialises as a JSON array and `.sortedKeys` does not sort array
   elements. Correctly deferred (the fix touches `DiskUsageModels.swift`, a binding zero-line-diff file)
   and honestly recorded in `design.md`. It should become a tracked follow-up rather than living only in
   an amendment note. (Carried from rev 1.)
2. **The `ReleaseNotesUITests` baseline is now four slices old.** 4 cases / 7 error lines, unowned and
   undiagnosed, raised at every gate since `7d48779`. Not re-executed this phase, so not re-measured —
   which is itself part of the problem. It should be assigned before it stops being recognisable as "the
   known baseline". (Carried from rev 1.)
3. **Three assertions in `aCleanupRemediationKeepsItsOwnersConfirmation` are entailed rather than
   discriminating.** `CleanupCommand.requiresConfirmation` is the constant `{ true }` and `disclosure`
   inherits the constant `.packageRemoval` from `BrewMutating`, so `:70`, `:73` and `:74` cannot fail
   independently of `offered == owner` at `:68`. Worth a comment naming which assertion carries the
   weight. (Carried from rev 2.)
4. **NEW — `cellar/Health/HealthCopy.swift:104` exceeds cyclomatic complexity** (11 against a default
   limit of 10), warning-level. This is a file this change created, so the finding is
   change-introduced. Rev 2 did not record it; recorded here for completeness. Not blocking — copy
   mapping over many cases is a reasonable place for a wide switch — but splitting it by signal family
   would remove it.
5. **NEW — `Packages/CellarCore/Sources/BrewClient/OperationCenterBulk.swift` crossed the file-length
   threshold** (403 lines against a default limit of 400), warning-level. Measured at `HEAD`: **383
   lines**, so this change pushed it over by adding the bulk pin/unpin fan-out. Rev 2 did not record it.
   Not blocking, and the file is coherent — but it is now on the wrong side of a threshold it was
   comfortably inside before.

**Recorded at no severity** (record accuracy, not code):

- Rev 2's correction stands: apply-progress and `design.md` say the verify-1 mutation "failed all three
  real-code tests"; there are four, and the described edits reach only three.
- **The ledger's maintainer-authorized reset of 2026-08-07 is an authorization, not a defect, and is
  recorded as such.** It was issued for a measurement artifact: an intent-to-add made the entire
  uncommitted change visible to `git diff --numstat` mid-attempt, so the measured delta reflected all of
  batches 1–4 instead of the work unit. Rev 3 corroborates both halves independently — all 69 changed
  files now appear as tracked-with-additions (the intent-to-add signature, with zero staged content),
  and the real batch-4 delta reconstructs exactly to **191 lines** (111 test + 12 design + 67 minus 1
  apply-progress), inside the 200 hard bound.
- A batch-4 risk asserting a `tasks.md` 13.3 inconsistency is **incorrect** and is dismissed above on the
  evidence of `tasks.md:174–177`.

### Verdict

**PASS WITH WARNINGS.**

**80/80 scenarios compliant, 15/15 requirements, 71/71 tasks complete, zero CRITICAL, zero blockers,
zero failing commands, zero regressions.** FAST is 1,656 tests / 199 suites green — exactly +1 test and
+1 suite over rev 2, which is precisely what a test-only batch must produce — the build succeeds, and
every binding zero-line diff still measures zero.

The scenario that failed rev 2 is closed the way rev 2 said it had to be closed: by observation. The new
test resolves the fetch marker through the shipped locator, reads it through the shipped reader, spawns
real `brew doctor` through the shipped source, asserts the `HOMEBREW_NO_AUTO_UPDATE` pin from the exact
expression production composes rather than setting it, refuses three separate vacuous passes, and skips
honestly on a machine with no Homebrew. It passed at runtime here in both a full and a focused run, its
assertion was proven discriminating by a genuine inverted RED in apply, and the marker's own mtime —
unmoved across four real doctor runs spanning two sessions — corroborates the result from outside the
test entirely.

The one WARNING is a pre-existing lint violation in the composition root, now measured at `HEAD` rather
than asserted, and the five SUGGESTIONs are follow-ups rather than gates.

**Archive-ready.** Nothing is committed (RDD disabled); delivery remains under ordinary repository
policy.
