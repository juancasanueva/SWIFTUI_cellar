```yaml
schema: gentle-ai.verify-result/v1
evidence_revision: sha256:0acd9c0075ffa83adb8f7055d44e7dcd17e47972f9f6a29f02de25603789054f
verdict: pass_with_warnings
blockers: 0
critical_findings: 0
requirements: 3/3
scenarios: 25/25
test_command: xcodebuild test -project cellar.xcodeproj -scheme cellar -destination 'platform=macOS,arch=arm64' -only-testing:cellarTests
test_exit_code: 0
test_output_hash: sha256:f5b5b3f24d2f55852bc3e814fa023800c9d43b8027a5680f196be8d870fc8875
build_command: xcodebuild build -project cellar.xcodeproj -scheme cellar -destination 'platform=macOS,arch=arm64'
build_exit_code: 0
build_output_hash: sha256:86d22fa5c2b1e80b50bdb80593ecdf0e0f82d59a836328126f739c87789869bd
```

## Verification Report — round 2 (supersedes round 1)

**Change**: `m10-third-party-detail`
**Version**: spec deltas rev 2 (II15 ADDED, PD6 MODIFIED, TM5 MODIFIED) — unchanged since round 1
**Mode**: Strict TDD
**Branch**: `feat/m10-third-party-detail` @ `7ee4c35`, **10 commits** off `main` @ `5a0860b`, working
tree clean
**Artifact store**: hybrid — this file is canonical; Engram topic
`sdd/m10-third-party-detail/verify-report` mirrors it. RDD disabled: no review lifecycle, no receipt,
ordinary repository policy.
**Independence**: fresh context. Every number below was measured in this session; nothing is carried
over from round 1's report or from `apply-progress.md` on their word.

### Round 1 summary (superseded)

Round 1 (`1b71d4c`, branch @ `3545328`) returned **`verdict: fail` on evidence completeness only —
0 blockers, 0 CRITICAL, 4 WARNING, 7 SUGGESTION, 3/3 requirements, 24/25 scenarios**. Two facts denied
a passing verdict:

- **W1** — the then-declared verify runner (`xcodebuild test … -scheme cellar`, full scheme) exited
  **65** on two `cellarUITests` cases (`:209`, `:231`, Taps section). Round 1 reproduced both on
  unmodified `main` in a separate worktree, so they were classified pre-existing.
- **W2** — II15 sc7's second THEN ("carries no per-package grant marker") had no covering assertion, so
  the scenario was PARTIAL.

Also raised: **W3** (a vacuous `RecordingProcessLauncher` assertion pair), **W4** (task 6.7 open),
and **S1–S7**.

**Maintainer decision on W1, applied here as binding**: the two failures are pre-existing on `main`
`5a0860b` and will be fixed in a **separate PR after m10**. For m10 the declared verification runners
are therefore the **scoped** ones listed below. The full-scheme runner's state is recorded in
"Out-of-scope tracked items", **not** as a finding against this change.

---

### Completeness

| Metric | Value |
|--------|-------|
| Tasks total | 52 |
| Tasks complete | 51 |
| Tasks incomplete | **1** — `6.7` (open the PR), a delivery task the launch brief forbade |

Verified by counting the checkboxes in `tasks.md`: 52 total, 51 `[x]`, the single `[ ]` at `:339`.
Every implementation and verification task is complete; the one open task creates no code obligation.

---

### Build & Tests Execution

All three declared runners were executed by this verifier in this session. Hashes are SHA-256 over the
exact captured output with the harness's appended exit marker removed.

| # | Declared runner | Exit | Result | Output hash |
|---|---|---|---|---|
| 1 | `swift test --package-path Packages/CellarCore` (class `unit`) | **0** | **1,838 tests / 216 suites passed**, 0 failures, 1 pre-existing known issue | `sha256:263cb283…05bda84c` |
| 2 | `xcodebuild test … -only-testing:cellarTests` (class `unit-app`) | **0** | `** TEST SUCCEEDED **`, **246 distinct tests**, 0 failures | `sha256:f5b5b3f2…d870fc8875` |
| 3 | `xcodebuild build … -scheme cellar` | **0** | `** BUILD SUCCEEDED **`, **0 compiler warnings** | `sha256:86d22fa5…789869bd` |

The envelope carries runner 2 in its single `test_command` slot as the successor to round 1's app-target
slot; runner 1 is an equally declared runner and its exit code and hash are recorded above rather than
elided. Both are green.

**Expected counts met exactly.** Round 2's remediation predicted CellarCore **1,838** and `cellarTests`
**246**; both were measured here at those values, 0 failures. The `cellarTests` count is `sort -u` over
the emitted test ids (246) and reconciles with the `' passed on'` line count (256, which includes
retried/duplicated emissions).

**The 1 known issue is not this change's**: it is `OperationCenterCancelTests.swift:183` in the
"Operation center cancel" suite, present before and after.

**All 20 tests of the change were observed passing by name**, not inferred from a summary line:

- **13 `unit`** — every `@Test` display name in `InstalledDetailProjectionTests` was grepped for its own
  `passed after` line in output 1; all 13 returned exactly one hit. Suite line:
  `Suite "Installed detail projection" passed after 0.506 seconds.`
- **7 `unit-app`** — all seven `ReceiptDetailCompositionTests` case ids appear in output 2, including
  the new `theReceiptPaneResolvesTheMarkerOnlyUnderTheTapGuard()`. `PerPackageTrustCompositionTests`
  is still 2/2 with its extended source list.

**Coverage**: ➖ Not available — no coverage tool is configured; `rules.verify.coverage_threshold` is
`0`, so nothing is below threshold.

---

### Spec Compliance Matrix

Authoritative counts re-read from the retrieved delta files in this session: **3 requirements**,
**25 scenarios** (II15 12, PD6 3, TM5 10). 14 are new to this change; the other 11 were verified
**byte-identical** to the main specs by extracting each `#### Scenario:` block from both sides and
comparing them programmatically: PD6 **2 identical / 0 differing / 1 new**, TM5 **9 identical /
0 differing / 1 new**.

#### `installed-inventory` — II15 (ADDED, 12 scenarios, all new)

| Scenario | Class | Test | Result |
|---|---|---|---|
| sc1 detailed from its receipt alone | `unit` | `aReceiptOnlyPackageIsDetailedFromItsSnapshotAlone` (+ `theGroupsKeepTheirOrderAndNoLabelRepeats`) | ✅ COMPLIANT |
| sc2 reaches no process layer | `unit-app` | `composingTheReducedDetailReachesNoProcessLayer` | ✅ COMPLIANT |
| sc3 facts do not cross between kinds | `unit` | `factsDoNotCrossBetweenFormulaAndCask` | ✅ COMPLIANT |
| sc4 auto-updates has three outcomes | `unit` | `aCaskAutoUpdatesTriStateStaysThreeAnswers` | ✅ COMPLIANT |
| sc5 linked multi-keg formula | `unit` | `aMultiKegFormulaShowsItsPrimaryKegAndACountOfTheRest` | ✅ COMPLIANT |
| sc6 unlinked formula, singular other keg | `unit` | `anUnlinkedFormulaStillNamesItsPrimaryKeg` (+ `aFormulaReportsBothLinkStates`, `aPinnedFormulaReportsItsPinWithAndWithoutAVersion`) | ✅ COMPLIANT |
| **sc7 withheld tap ⇒ no origin fact AND no marker** | `unit` (+ `unit-app`) | `aWithheldTapProducesNoOriginFact` · **`aWithheldTapCarriesNoGrantMarkerEither`** · **`theReceiptPaneResolvesTheMarkerOnlyUnderTheTapGuard`** | ✅ **COMPLIANT — W2 discharged** |
| sc8 absent description/homepage is absent | `unit` | `absentDescriptionAndHomepageAreOmittedNotEmptied` | ✅ COMPLIANT |
| sc9 no fact reports an install date | `unit-app` | `theReceiptPaneRendersNoInstallDate` | ✅ COMPLIANT |
| sc10 marker beside origin, never composed locally | `unit-app` | `theReceiptPaneResolvesTheMarkerThroughTheOneProjection` + **the new guard case** (S2) + the DD-11 `PerPackageTrustSources` loop | ✅ COMPLIANT |
| sc11 the row's verbs, no trust control | `unit-app` | `theReceiptPaneOffersTheSameVerbsAsTheRow` + `theReceiptPaneOffersNoTrustControl` | ✅ COMPLIANT |
| sc12 catalog-miss copy stays scoped | `unit-app` | `theScopedCatalogMissCopyIsUnchanged` | ✅ COMPLIANT (see S8) |

**sc7's declared class stays `unit` and stays honest.** The `unit` case
`aWithheldTapCarriesNoGrantMarkerEither` covers the whole scenario as a statement about the projection;
the `unit-app` case is *additive*, covering the further claim the presenting surface makes. No delta
spec file was edited to reach compliance, and `openspec/specs/**` holds a zero-line diff.

#### `package-detail` — PD6 (MODIFIED, 3 scenarios)

| Scenario | Class | Test | Result |
|---|---|---|---|
| sc1 third-party tap package is a normal not-found | shipped | `"A third-party tap package is an ordinary not-found after a successful sync"` — observed passing | ✅ COMPLIANT (byte-identical) |
| sc2 every snapshot record belongs to a covered tap | shipped | `"Every projected record belongs to a covered tap"` — observed passing | ✅ COMPLIANT (byte-identical) |
| sc3 receipt-backed detail creates no catalog record | `unit` | `aReceiptBackedDetailCreatesNoCatalogRecord` | ✅ COMPLIANT |

#### `tap-management` — TM5 (MODIFIED, 10 scenarios)

| Scenario | Class | Test | Result |
|---|---|---|---|
| the nine shipped scenarios | shipped | `TapProjectionTests` — `Suite "Tap projection" passed`; prefix/equal-token identity, fully qualified cask token, exact-tap handoff, the three withheld-tap cases, tap names never becoming catalog records, large-inventory filtering | ✅ COMPLIANT (all nine byte-identical, all green) |
| the new scenario — handoff lands on a receipt-backed detail | `unit` | `theHandoffLandsOnAReceiptBackedDetail` | ✅ **COMPLIANT — W3 discharged** |

**Compliance summary**: **25/25 COMPLIANT, 0 PARTIAL, 0 UNTESTED, 0 FAILING.**

---

### Round-1 finding dispositions

| # | Round-1 finding | Round-2 disposition | Verified how |
|---|---|---|---|
| **W1** | Declared runner exits 65 on two `cellarUITests` cases | **Out of scope by maintainer decision** — scoped runners declared; separate PR after m10 | `cellarUITests/**` zero-line diff re-confirmed; both scoped runners exit 0 |
| **W2** | II15 sc7 second THEN unasserted (PARTIAL) | **DISCHARGED** | Both new cases read and **mutation-tested** below; sc7 now COMPLIANT |
| **W3** | Vacuous `RecordingProcessLauncher` assertions | **DISCHARGED** | `rg 'RecordingProcessLauncher\|launchCount\|specs.isEmpty'` over the test file → **no match**; replacements read at `:521-522` |
| **W4** | Task 6.7 (open the PR) incomplete | **OPEN by instruction** — carried forward as the one remaining WARNING | 52 checkboxes counted; `:339` is the only `[ ]` |
| **S1** | Unrecorded fact-ordering deviation | **RECORDED** as "Deviation 4" in `apply-progress.md`; code deliberately unchanged | Read; `design.md` confirmed untouched since `38f1f90` |
| **S2** | sc10's marker test did not pin the binding | **DISCHARGED**, folded into the new `unit-app` case | Assertion at `ReceiptDetailCompositionTests.swift:150-154` pins `receiptFact(origin, note: marker(…))` |
| **S3** | New SwiftLint advisories | **Accepted follow-up**, recorded | Re-run here; see Quality Metrics |
| **S4** | Line accounting understated | **CORRECTED** — apply-progress now states **3,894**; measured here **3,894** | `git diff --shortstat main...HEAD` → `17 files, 3853 insertions(+), 41 deletions(-)` |
| **S5** | Deviation 2's stated diff off by one | **CORRECTED** to `4+ / 3−`; measured `4 3` | `git diff --numstat main...HEAD -- cellarTests/PerPackageTrustCompositionTests.swift` |
| **S6** | Design size estimates overrun | **Accepted follow-up**, recorded (test file now 544 lines) | `wc -l` |
| **S7** | Cross-work-unit cosmetic spill in `65a65cb` | **Accepted follow-up**, recorded | Commit contents inspected |

---

### Non-vacuity proof (independent mutation testing)

The brief asked whether sc7's two new assertions can actually fail. Reading them was not treated as
sufficient; **both were proved by a reversible mutation, fully restored, tree left byte-identical.**

| Mutation | Applied to | Observed | Restoration |
|---|---|---|---|
| Added `public let grantMarkerNote: String? = nil` after `kindState` | `InstalledDetailProjection.swift` | `aWithheldTapCarriesNoGrantMarkerEither` **failed with 3 issues** — `:332` member list `["description","identity","tapOfOrigin","kindState","grantMarkerNote"]` ≠ expected, and `:335` twice on the forbidden-substring loop (`grant`, `marker`) | SHA-256 back to `19b03052…`, `git diff --stat` empty, test re-run **passed** |
| Hoisted the marker call above the tap guard (`let hoistedMarker = marker(for:publishedBy: snapshot.tap ?? "")`) | `PackageDetailView+Receipt.swift` | `theReceiptPaneResolvesTheMarkerOnlyUnderTheTapGuard` **failed**; **all six other cases in the file passed**, sc10's `theReceiptPaneResolvesTheMarkerThroughTheOneProjection` included | SHA-256 back to `e9b3bf2d…`, `git status --porcelain` empty, suite re-run `** TEST SUCCEEDED **` |

The second row independently reproduces the exact gap S2 named: a "mentions `grantMarker`" assertion
does not detect a marker resolved outside the guard, and the new case does. Both production files and
the whole working tree are byte-identical to `7ee4c35` at the close of this verification.

The mechanism is real, not incidental. `marker(for:` matches the call site at `:114` but not the
definition at `:156` (`marker(for id:`), so `callSites.count == 1` is a genuine uniqueness claim; the
brace-depth walk from the guard at `:113` closes at `:115`, bracketing the call.

---

### Correctness (Static Evidence)

| Requirement clause | Status | Evidence gathered this session |
|---|---|---|
| Pure, `nonisolated`, `Sendable`, totally derived from one record | ✅ | `public init(_ package: InstalledPackage)` is the only entry point; no annotation, no actor, no I/O |
| **No brew invocation, no scan started** | ✅ | The whole branch diff was scanned for added `Process(`, `BrewProcess`, `ProcessLauncher`, `.launch(`, `Task {`, `.task {`, `await `, `async `: the **only** `+` hits are inside the tests' own forbidden-token lists. `PackageDetailView+Receipt.swift` contains none of these tokens at all; the projection's single hit is the word `Process` inside a doc comment, and sc2 scans comment-stripped `code` |
| Group order identity → origin → install state | ✅ | `orderedFacts`; positions asserted, not a concatenation the test rebuilds |
| **Pinned copy byte-exact** — footer `Cellar’s` with U+2019 | ✅ | Re-verified by hexdump of `PackageDetailView+Receipt.swift:170`: `43 65 6c 6c 61 72 **e2 80 99** 73`. sc12 also pins the straight-apostrophe variant absent |
| Pinned copy `Linked` / `Not linked` / `N other versions installed` / `1 other version installed` / `Updates itself` / `Updated by Homebrew` / no fact when undeclared | ✅ | All observed passing by name in output 1 (sc4, sc5, sc6) |
| **`Trusted individually` only via `TapProjection`** | ✅ | `rg` over every `.swift` in the tree: the sole **definition** is `TapProjection.swift:255`. Every other occurrence is a test asserting against it. `ReceiptDetailCompositionTests.swift:87` pins `pane.raw` free of the literal |
| **No trust control on the surface** | ✅ | `theReceiptPaneOffersNoTrustControl` bans `"Trust`, `TapCommand`, `grant(`, `revoke`, `submit(.trust`, `TrustGrantCommand`, and the five implication words over `pane.raw` |
| Marker resolved only under the tap guard | ✅ | `PackageDetailView+Receipt.swift:113-115` read directly; mutation-proved above |
| Absence never a sentinel | ✅ | Seven shapes enumerated behind an `emitted.isEmpty == false` guard |
| No install date, no epoch-derived value | ✅ | `theReceiptPaneRendersNoInstallDate`; `InstalledDecoder.swift` zero-line diff, so the deferred epoch defect was not "fixed" |
| No latest/current/published version fact | ✅ | `installStateFacts` emits only `Version`, `Link state`, `Other versions`, `Pin state` |

---

### Coherence (Design)

DD-1 … DD-12 all hold; round 2 wrote **no production line**, so round 1's coherence findings stand
except where a disposition above changed them. Re-confirmed directly this session:

| Decision | Followed? | Evidence |
|---|---|---|
| DD-4 no marker field; the pane's single guard is the seam | ✅ Yes | The one `if let tap = snapshot.tap, let origin = detail.tapOfOrigin` at `:113`; **now mutation-guarded** |
| DD-8 `MutationMenu` byte-unchanged | ✅ Yes | `MutationMenu` source is **not in the branch diff**; the pane builds no `MutationCommand`, calls no `submit(`, constructs no `PackageTarget(` |
| DD-9 six helpers internal, none duplicated | ✅ Yes | `PackageDetailView.swift` diff read in full: exactly five `private` keywords dropped (`header`, `versionStory(installed:)`, `fact`, `sizeOnDisk`, `installedAs`) plus the new internal `factLink` = six. `factLabel` and `theme` stay private. `factLink` **removed** the inline homepage duplication |
| DD-11 extend `PerPackageTrustSources.views()`, sorted anchor | ✅ Yes | Diff is `4+ / 3−`: the path, the required comma, the anchor line, and one comment word. The sorted anchor now names four files |
| DD-7 store facts stay view-side | ✅ Yes | `installedAs(for:)` and `sizeOnDisk(for:)` appended by the pane at `:123-128`. Ordering deviation recorded as S1 |

**Bindings held — every one re-measured, not carried over.** `git diff --stat main...HEAD` is **empty**
for all of: `cellar.xcodeproj/project.pbxproj`, `openspec/specs/`, `cellarUITests/`,
`MutationCommand.swift`, `TapCommand.swift`, `TapProjection.swift`, `InstalledDecoder.swift`,
`InstalledModels.swift`, `scripts/`, `.github/workflows/`.

---

### TDD Compliance

| Check | Result | Details |
|-------|--------|---------|
| TDD Evidence reported | ✅ | Full cycle tables in `apply-progress.md` for round 1 **and** round 2 |
| All tasks have tests | ✅ | 17/17 behavioural task rows; the one non-behavioural unit (WU2) is exempted in writing at `tasks.md:157-160` |
| RED confirmed (tests exist) | ✅ | Both test files exist and compile; every named case executes |
| GREEN confirmed (tests pass) | ✅ | **20/20** observed passing by name at runtime |
| Triangulation adequate | ✅ | sc7's new case triangulates withheld **vs** granted against the *same* report; tri-state cask pairwise-distinguishable; three pin states; both link states; 1/2/3-keg formulae; 7-shape absence enumeration; two `Mirror` structural proofs |
| Safety Net for modified files | ✅ | Round 2: 1,837 → 1,838 core with no id removed; 245 → 246 `cellarTests` |

**TDD Compliance: 6/6.**

Round 2's RED could not come from absent production code — both cases assert behaviour that already
shipped correctly. It was produced by mutation, and **this verifier independently reproduced both
mutations** rather than accepting the report's word (see Non-vacuity proof). That is the strongest
form of RED evidence available for a guard written after the fact, and it is corroborated by commit
`d5f51e1`/`177fe85` containing **zero production lines**.

---

### Test Layer Distribution

| Layer | Tests (change total) | Files | Tools |
|-------|------|-------|-------|
| Unit (`unit`, CellarCore) | 13 | 1 new (+1 fixture modified) | Swift Testing / `swift test` |
| Unit-app (`unit-app`, source-scan composition) | 7 | 1 new (+1 modified) | Swift Testing / `xcodebuild test -only-testing:cellarTests` |
| E2E (XCUITest) | 0 new | 0 — `cellarUITests/` byte-untouched | XCTest |
| **Total new** | **20** | **2 new, 2 modified** | |

Both classes are the established ones; no new verification class is introduced, and no
`manual-evidence` scenario exists in this change.

---

### Assertion Quality

**Assertion quality**: ✅ **0 CRITICAL, 0 WARNING — all assertions verify real behaviour.**

Round 1's single WARNING (W3) is gone: `RecordingProcessLauncher`, `launchCount` and `specs.isEmpty`
have no occurrence anywhere in `InstalledDetailProjectionTests.swift`. The replacements at `:521-522`
(`resolved == receipt`, and a name the inventory does not hold staying a miss) exercise
`InstalledInventory.package(_:)` and can fail.

Both cases added in round 2 were audited for the banned patterns and pass:

- **No tautologies, no orphan empty checks, no type-only assertions, no ghost loops.** Each loop in
  `aWithheldTapCarriesNoGrantMarkerEither` runs over a collection guarded non-empty first
  (`members`, and `emitted` behind `#expect(emitted.isEmpty == false, …)`).
- **Every absence assertion runs behind a positive anchor.** The `unit` case asserts the grant report
  **really grants** `acme/tools/widget` before anything is denied; the `unit-app` case `#require`s the
  tap guard is found before measuring containment; sc12 `#require`s the shipped sentence exists.
- **Non-vacuity is measured, not argued** — see the mutation table.

---

### Quality Metrics

**Compiler**: ✅ `** BUILD SUCCEEDED **`, **0 warnings** across the whole project (runner 3).

**Linter**: ⚠️ SwiftLint 0.65.1 is installed but **not wired into this project** — no `.swiftlint.yml`
anywhere in the tree and no lint build phase — so these are default-rule advisories, not gate failures.
Re-run in this session over the six changed Swift files:

| File | Findings | New? |
|---|---|---|
| `PackageDetailView.swift` | file_length 858, type_body_length 632 (error), function_body_length, line_length | **Pre-existing** — and still **improved** by m10 (main: 874 / 651) |
| `InstalledDetailProjectionTests.swift` | file_length 544, type_body_length 391 (error) | Deepened by round 2's +79 lines; same rule classes as round 1 |
| `InstalledDetailProjection.swift` | 3 × nesting | Consequence of DD-2's deliberate sum-type design |
| `PerPackageTrustCompositionTests.swift:32` | line_length 123 | The DD-11 anchor line |
| `PackageDetailView+Receipt.swift` | — | **Clean** |
| `ReceiptDetailCompositionTests.swift` | — | **Clean** |

No new rule class appeared in round 2.

---

### Commit Hygiene & Size

| Check | Result |
|---|---|
| Conventional commits | ✅ **10/10** matched `^(feat|fix|chore|docs|style|refactor|perf|test|build|ci|revert)(\(scope\))?: ` |
| `Co-Authored-By` / AI attribution | ✅ **None** — full message bodies scanned for `co-authored-by`, `claude`, `anthropic`, `generated with`, `assistant`, `ai-generated`: no match |
| Author | ✅ All 10 `Juan Casanueva <juancasanueva@gmail.com>` |
| One work unit per commit | ✅ WU1–WU5 map 1:1; round 2's `d5f51e1` and `177fe85` each touch exactly **one test file** and no production file |
| Round-2 commit bodies | ✅ Each states the finding it discharges and the mutation that proved it |
| Working tree | ✅ Clean at close; nothing pushed, no PR opened, no review lifecycle started |

**Measured size** — `git diff --shortstat main...HEAD`: **17 files changed, 3,853 insertions(+),
41 deletions(−)** = **3,894 changed lines** against `review_budget_lines: 5000` → **78 %**.
This matches `apply-progress.md`'s corrected figure exactly. Buckets: code+tests **1,423**
(1,382+ / 41−), SDD artifacts **2,471**. Replacing round 1's 396-line report with this one leaves the
branch in the same band, comfortably under 5,000. **`single-pr` stands**: no chain, no
`size:exception`.

---

### Out-of-scope tracked items (not findings against m10)

- **The full-scheme runner is known red on `main`.**
  `xcodebuild test -project cellar.xcodeproj -scheme cellar -destination 'platform=macOS,arch=arm64'`
  exits **65** on `cellarUITests.testTapsNavigationOfficialSourcesAndAddConfirmation`
  (`cellarUITests.swift:209`, `XCTAssertTrue failed`) and
  `cellarUITests.testTapDetailFilteringInstalledHandoffAndForceDisclosure` (`:231`, *"Multiple matching
  elements found"*). Round 1 reproduced both on unmodified `main` @ `5a0860b` in a separate worktree.
  This round re-confirmed the attribution evidence that remains checkable: **`cellarUITests/` holds a
  zero-line diff across the whole branch**, both cases exercise only the Taps surface, and m10 touches
  no Taps view and no `TapProjection`. **Per the maintainer's binding decision this is tracked for a
  separate PR after m10 and is not a finding here.** It must be disclosed in the m10 PR body.

---

### Issues Found

**CRITICAL**: None.

**WARNING**

- **W4 (carried forward) — task 6.7 incomplete.** The PR is not opened and nothing is pushed. This is a
  delivery task the launch brief explicitly forbade in both rounds, not an implementation gap; the
  (a)–(d) body text it asks for is drafted in `apply-progress.md`.
  *Remediation*: push `feat/m10-third-party-detail`, open the single PR with the drafted body **plus
  the W1 disclosure above**, and tick 6.7 before archive.

No other WARNING is warranted. W1 is out of scope by maintainer decision, and W2, W3, S2, S4 and S5 are
discharged on evidence gathered independently in this session.

**SUGGESTION**

- **S1 (carried) — correct the design's fact-inventory table at archive.** The deviation is now
  recorded in `apply-progress.md` as "Deviation 4", and the decision to keep the shipped ordering is
  well argued (DD-7's operative verb is "appended", and II15 constrains order only *between* groups).
  `design.md` is untouched since `38f1f90`, so the table still contradicts its own prose. Correct the
  row order at archive; the source for the correction now exists.
- **S3 (carried) — SwiftLint advisories.** Unchanged in class; round 2 deepened the test file's
  `file_length` and `type_body_length`. Informational while no linter is wired into the project.
- **S6 (carried) — design size estimates overrun.** `InstalledDetailProjectionTests.swift` is now
  **544** lines against an estimate of 240–360. Harmless; it is what triggers S3's advisories.
- **S7 (carried) — one cross-work-unit cosmetic spill in `65a65cb`.** Historical; rewriting a landed
  commit is not worth the history.
- **S8 (new) — sc12's positive anchor now leans on an unrelated line.** WU5 removed the catalog-miss
  sentence from `uncatalogedContent`, so `PackageDetailView.swift` went from **2** occurrences on
  `main` to **1** on this branch — the survivor is the *pre-existing* fallback at `:61`, which fires
  when there is no installed record at all. `theScopedCatalogMissCopyIsUnchanged` anchors on
  `shipped.raw.contains(sentence)`, so correcting that unrelated fallback's copy (it describes an
  absent record as an "installed package", which is arguably wrong) would fail sc12's test even though
  the pane is correct. Consider anchoring the comparison on `TapProjection`-style shared constant, or
  noting the coupling in the test's comment.
- **S9 (new) — `tasks.md:319` still declares the full-scheme runner and is ticked.** Task 6.2 reads
  "Full app target: `xcodebuild test … -scheme cellar` → baseline plus the new composition cases,
  0 failures" and is `[x]`, which no longer matches the maintainer's scoped-runner decision or the
  observed state of that runner. The apply report discloses the two failures honestly, so nothing is
  concealed; the task text is simply stale. Reconcile it at archive so the archived plan and the
  archived evidence agree.

---

### Verdict

**PASS WITH WARNINGS — 0 blockers, 0 CRITICAL, 1 WARNING, 6 SUGGESTION.
3/3 requirements, 25/25 scenarios, all three declared runners exit 0.**

Round 1's two blocking facts are both resolved. II15 sc7 is no longer PARTIAL: its second THEN is
covered by a `unit` case proving the marker **structurally unrepresentable** in the value and a
`unit-app` case pinning the pane's resolution **lexically inside the tap guard** — and this verifier
proved both non-vacuous by mutation, restoring the tree byte-identical. The declared runners, scoped by
the maintainer's binding decision, are green: CellarCore **1,838/1,838**, `cellarTests` **246/246**,
build **succeeded with 0 warnings**.

The vacuous launcher assertions are gone and their replacements exercise real code. Every "must not
move" binding still holds a genuine zero-line diff — `project.pbxproj`, `openspec/specs/**`,
`cellarUITests/**`, `TapProjection.swift`, `InstalledDecoder.swift`, `MutationMenu`. The branch adds no
brew invocation, composes no grant marker locally, offers no trust control, and reproduces the pinned
copy byte-for-byte including the U+2019 apostrophe. Ten commits, all conventional, none carrying
attribution, at **3,894 / 5,000** changed lines.

The single remaining WARNING is task **6.7** — open the PR — which both apply rounds were instructed
not to perform. **Archive-ready once 6.7 is ticked**, with the full-scheme UI failures disclosed in the
PR body and tracked as their own follow-up.
