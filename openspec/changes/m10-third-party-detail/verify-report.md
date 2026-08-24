```yaml
schema: gentle-ai.verify-result/v1
evidence_revision: sha256:334e3de273cba775040597621afbbdb188d55453dfcd4bcec050daa78925276e
verdict: fail
blockers: 0
critical_findings: 0
requirements: 3/3
scenarios: 24/25
test_command: xcodebuild test -project cellar.xcodeproj -scheme cellar -destination 'platform=macOS,arch=arm64'
test_exit_code: 65
test_output_hash: sha256:aac6c5cbb422ead59900c5c839a798748cfcb32ba774978df08787956ea76e42
build_command: xcodebuild build -project cellar.xcodeproj -scheme cellar -destination 'platform=macOS,arch=arm64'
build_exit_code: 0
build_output_hash: sha256:c1d6035d914598afa0beb9c6508b06173c568d3dfa1811928465c8f191a80a84
```

## Verification Report — round 1

**Change**: `m10-third-party-detail`
**Version**: spec deltas rev 1 (II15 ADDED, PD6 MODIFIED, TM5 MODIFIED)
**Mode**: Strict TDD
**Branch**: `feat/m10-third-party-detail` @ `3545328`, 6 commits off `main` @ `5a0860b`, working tree
clean but for this untracked report
**Artifact store**: hybrid — this file is canonical, Engram topic `sdd/m10-third-party-detail/verify-report`
mirrors it. RDD disabled: no review lifecycle, no receipt, ordinary repository policy.

### Read this first — what `verdict: fail` does and does not mean

**`fail` on evidence completeness only. 0 blockers, 0 CRITICAL, nothing in the shipped behaviour is
defective.** This is the same shape `m9-per-package-trust` used at its own round 1, and it discharges
the same way: a small, test-side round 2.

Two facts deny a passing verdict, and both are recorded rather than argued away:

1. The declared verify runner exits **65** — two `cellarUITests` cases fail. This verifier **reproduced
   both on unmodified `main`** in a separate worktree, so they are pre-existing and outside this
   change's blast radius (W1).
2. One scenario of the 25 is **PARTIAL**: II15 sc7's second `THEN` has no covering assertion (W2).

Neither is a defect in what m10 ships. `gentle-ai sdd-verify-validate` refuses a passing verdict paired
with a non-zero command exit **or** an incomplete scenario count — this report was written with
`pass_with_warnings` first and was correctly denied on both grounds. Softening either finding to obtain
admission would have been the wrong repair, so the verdict moved instead.

**The implementation itself verified cleanly**: 3/3 requirements implemented, 24/25 scenarios
COMPLIANT, 0 UNTESTED, 0 FAILING, all 18 new tests observed passing by name, every pinned copy string
byte-verified, and all three "must not move" bindings holding a genuine zero-line diff.

---

### Completeness

| Metric | Value |
|--------|-------|
| Tasks total | 52 |
| Tasks complete | 51 |
| Tasks incomplete | **1** — `6.7` (open the PR), a delivery task the launch brief forbade |

Every implementation and verification task is complete. The one open task creates no code obligation.

---

### Build & Tests Execution

All four commands were executed by this verifier in this session. Hashes are SHA-256 over the exact
captured output with the harness's appended exit marker removed.

| # | Command | Exit | Result | Output hash |
|---|---|---|---|---|
| 1 | `swift test --package-path Packages/CellarCore` (class `unit`) | **0** | **1,837 tests / 216 suites passed**, 0 failures, 1 known issue | `sha256:52724a41…8ca524` |
| 2 | `xcodebuild test … -scheme cellar` (**declared verify runner**; contains class `unit-app`) | **65** | **290 passing results, 2 failures** — both pre-existing (W1) | `sha256:aac6c5cb…6ea76e42` |
| 3 | `xcodebuild build … -scheme cellar` (declared build) | **0** | `** BUILD SUCCEEDED **`, **0 compiler warnings** | `sha256:c1d6035d…f8191a80a84` |
| 4 | `xcodebuild test … -only-testing:<the two failing UI cases>` **on `main` @ `5a0860b`** | **65** | Both reproduce identically — the baseline control | `sha256:ff87e3f2…6347b459` |

Command 4 is not part of the change's declared verification; it is the controlled experiment that
establishes W1's attribution. The worktree was removed afterwards and the repository left clean.

**Baselines confirmed against apply-progress.** CellarCore 1,825 → **1,837** (+12), `cellarTests`
239 → **245** (+6, measured here as 277 pass lines across the app-test target). Both deltas match the
apply report exactly.

**All 18 new tests were observed executing and passing by name**, not inferred from a summary line:

- 12 `unit` — `Suite "Installed detail projection" passed after 0.498 seconds`, with every case in the
  matrix below appearing as its own `passed after` line in output 1.
- 6 `unit-app` — `ReceiptDetailCompositionTests/…() passed` for all six cases in output 2, and
  `PerPackageTrustCompositionTests` 2/2 still green with its extended source list.

**Coverage**: ➖ Not available — no coverage tool is configured; `rules.verify.coverage_threshold` is
`0`, so nothing is below threshold.

---

### Spec Compliance Matrix

Authoritative counts read from the retrieved delta files: **3 requirements**, **25 scenarios**
(II15 12, PD6 3, TM5 10). 14 are new to this change; the other 11 are reproduced byte-identical and
verified still green by their shipped covering tests.

#### `installed-inventory` — II15 (ADDED, 12 scenarios, all new)

| Scenario | Class | Test | Result |
|---|---|---|---|
| sc1 detailed from its receipt alone | `unit` | `InstalledDetailProjectionTests > aReceiptOnlyPackageIsDetailedFromItsSnapshotAlone` (+ `theGroupsKeepTheirOrderAndNoLabelRepeats`) | ✅ COMPLIANT |
| sc2 reaches no process layer | `unit-app` | `ReceiptDetailCompositionTests > composingTheReducedDetailReachesNoProcessLayer` | ✅ COMPLIANT |
| sc3 facts do not cross between kinds | `unit` | `factsDoNotCrossBetweenFormulaAndCask` | ✅ COMPLIANT |
| sc4 auto-updates has three outcomes | `unit` | `aCaskAutoUpdatesTriStateStaysThreeAnswers` | ✅ COMPLIANT |
| sc5 linked multi-keg formula | `unit` | `aMultiKegFormulaShowsItsPrimaryKegAndACountOfTheRest` | ✅ COMPLIANT |
| sc6 unlinked formula, singular other keg | `unit` | `anUnlinkedFormulaStillNamesItsPrimaryKeg` (+ `aFormulaReportsBothLinkStates`) | ✅ COMPLIANT |
| sc7 withheld tap ⇒ no origin fact **and no marker** | `unit` | `aWithheldTapProducesNoOriginFact` | ⚠️ **PARTIAL** — W2 |
| sc8 absent description/homepage is absent | `unit` | `absentDescriptionAndHomepageAreOmittedNotEmptied` | ✅ COMPLIANT |
| sc9 no fact reports an install date | `unit-app` | `theReceiptPaneRendersNoInstallDate` | ✅ COMPLIANT |
| sc10 marker beside origin, never composed locally | `unit-app` | `theReceiptPaneResolvesTheMarkerThroughTheOneProjection` (+ the DD-11 `PerPackageTrustSources` loop) | ✅ COMPLIANT (S2) |
| sc11 the row's verbs, no trust control | `unit-app` | `theReceiptPaneOffersTheSameVerbsAsTheRow` + `theReceiptPaneOffersNoTrustControl` | ✅ COMPLIANT |
| sc12 catalog-miss copy stays scoped | `unit-app` | `theScopedCatalogMissCopyIsUnchanged` | ✅ COMPLIANT |

#### `package-detail` — PD6 (MODIFIED, 3 scenarios)

| Scenario | Class | Test | Result |
|---|---|---|---|
| sc1 third-party tap package is a normal not-found | shipped | `CatalogTests/DetailTests > "A third-party tap package is an ordinary not-found after a successful sync"` | ✅ COMPLIANT (byte-identical, still green) |
| sc2 every snapshot record belongs to a covered tap | shipped | `CatalogTests/ProjectionTests > "Every projected record belongs to a covered tap"` | ✅ COMPLIANT (byte-identical, still green) |
| sc3 receipt-backed detail creates no catalog record | `unit` | `InstalledDetailProjectionTests > aReceiptBackedDetailCreatesNoCatalogRecord` | ✅ COMPLIANT |

#### `tap-management` — TM5 (MODIFIED, 10 scenarios)

| Scenario | Class | Test | Result |
|---|---|---|---|
| sc1–sc9 (nine shipped scenarios) | shipped | `TapProjectionTests` — prefix normalization, fully qualified cask token, equal-token distinctness, exact-tap handoff, the three withheld-tap cases, catalog absence, large-inventory filtering | ✅ COMPLIANT (byte-identical, all green in output 1) |
| sc10 handoff lands on a receipt-backed detail | `unit` | `InstalledDetailProjectionTests > theHandoffLandsOnAReceiptBackedDetail` | ✅ COMPLIANT (W3 on one clause's assertion) |

**Compliance summary**: **24/25 COMPLIANT, 1 PARTIAL, 0 UNTESTED, 0 FAILING.**

---

### Correctness (Static Evidence)

| Requirement clause | Status | Evidence |
|---|---|---|
| Pure, `nonisolated`, `Sendable`, totally derived from one record | ✅ | `public init(_ package: InstalledPackage)` is the only entry point; `Sendable, Hashable` by composition; no annotation, no actor, no I/O in the file |
| No brew invocation, no scan started | ✅ | Neither source contains `Process`, `BrewProcess`, `launcher`, `brewPath`, `/bin/`, `refresh`, `.task`, `Task {`, `await `, `async ` — asserted per-token behind a positive file anchor |
| Group order identity → origin → install state | ✅ | `orderedFacts = identity + tapOfOrigin + installStateFacts`; asserted on **positions** (`tapIndex == identity.count`), not on a concatenation the test rebuilds |
| Exact copy `Linked` / `Not linked` | ✅ | `InstalledDetailProjection.copy(_:LinkState)` :202-207; asserted as whole-array equality |
| Exact copy `N other versions installed` / `1 other version installed` | ✅ | `otherVersionsCopy(_:)` :220-223, singular branch pinned; `nil` for a single keg |
| Exact copy `Updates itself` / `Updated by Homebrew` / **no fact** | ✅ | :141-147; three outcomes asserted pairwise-distinguishable, so "not declared" can never read as "declared false" |
| Footer `Cellar’s` with U+2019 | ✅ | Byte-verified by hexdump: `43 65 6c 6c 61 72 **e2 80 99** 73` in `PackageDetailView+Receipt.swift:170`. The test compares against the sentence as it appears in the shipped `PackageDetailView.swift`, not a retyped copy, and pins the straight-apostrophe variant absent |
| `Trusted individually` only via `TapProjection` | ✅ | The only definition in the tree is `TapProjection.swift:255`. The pane contains the literal in neither code nor comments (`pane.raw`), and the extended `PerPackageTrustSources.views()` loop now covers the new file |
| Absence never a sentinel | ✅ | Seven distinct shapes enumerated; every emitted `Fact.value` non-empty and `!=` each of `unknown`, `Unknown`, `—`, `-`, `n/a`, `N/A`, behind a non-vacuity guard (`emitted.isEmpty == false`) |
| No install date, no epoch-derived value | ✅ | Both sources scanned for `Installed on`, `installedAt`, `install_date`, `timeIntervalSince1970`, `epoch`, `Date(`, `DateFormatter`; plus a value-level assertion using a fixture that **does** carry a timestamp, so the absence is the rule and not missing input |
| No latest/current/published version fact | ✅ | `installStateFacts` emits only `Version` (the primary keg), `Link state`, `Other versions`, `Pin state`; the version story stays the shared header's `versionStory(installed:)` |

---

### Coherence (Design)

| Decision | Followed? | Notes |
|---|---|---|
| DD-1 name/shape `InstalledDetailProjection` | ✅ Yes | `public struct`, `Sendable`, `Hashable`, one total `init` |
| DD-2 asymmetry as a sum type | ✅ Yes | `KindState.formula/.cask`; proved *unrepresentable* rather than merely unwritten by a `Mirror` assertion on each state's member list |
| DD-3 absence is `Optional`/omission, no sentinel | ✅ Yes | Plus `present(_:)` rejects the empty string at the last hop |
| DD-4 `tapOfOrigin` is the seam; no marker field | ✅ Yes | Projection carries no marker, no `isTrusted`, takes no `TrustGrantState`; the pane joins under `if let tap = snapshot.tap, let origin = detail.tapOfOrigin` — one guard, so fact and marker cannot disagree |
| DD-5 no latest-version / outdated row | ✅ Yes | Verified above |
| DD-6 no install date, absence asserted | ✅ Yes | Verified above |
| DD-7 store facts stay view-side | ✅ Yes | `installedAs(for:)` and `sizeOnDisk(for:)` appended by the pane; the init stays a pure function of one record. See S1 on ordering |
| DD-8 `MutationMenu(center:entry:)` byte-unchanged | ✅ Yes | `MutationMenu` is not in the branch diff at all; the pane builds no `MutationCommand`, calls no `submit(`, constructs no `PackageTarget(` |
| DD-9 six helpers internal, none duplicated | ✅ Yes | Exactly five `private` keywords dropped (`header`, `versionStory(installed:)`, `fact`, `sizeOnDisk`, `installedAs`) plus the new internal `factLink` = six. `factLink` **removed** an existing duplication by replacing the catalog pane's inline homepage block. `favoriteButton`, `statusBadge`, `factLabel`, `theme` stay private. No helper body appears twice in the tree |
| DD-10 nonisolated, synchronous in `body` | ✅ Yes | No `Task`, no `.task {}`, no `await` in either source — asserted, not assumed |
| DD-11 extend `PerPackageTrustSources.views()`, sorted anchor | ✅ Yes | New path added and the sorted-name anchor now names four files, so the new surface cannot escape the "composes no marker locally" loop (**R3 closed**). See S5 on the reported diff size |
| DD-12 scoped footer verbatim, U+2019 | ✅ Yes | Byte-verified |

**Bindings held.** `git diff main...HEAD` touches **16 files** and **none** of:
`cellar.xcodeproj/project.pbxproj` (**0-line diff**, the file-system-synchronized-group assumption held),
`openspec/specs/**` (**0-line diff**), `cellarUITests/**` (**0-line diff**),
`MutationCommand.swift`, `TapCommand.swift`, `TapProjection.swift`, `InstalledDecoder.swift`,
`InstalledModels.swift`, or any `Catalog` source. No catalog or search path changed; nobody "fixed" the
epoch defect DD-6 defers.

**Recorded deviations, judged:**

| # | Deviation | Judgment |
|---|---|---|
| 1 | `orderedFacts` added to the projection | **ACCEPT.** Strictly additive, computed, stores nothing. It makes II15 sc1's central clause ("in that group order") a property of the *type* rather than an order the test assembles — a materially stronger assertion. Nothing in the spec or design forbids it; II15 is explicitly member-name-neutral |
| 2 | `PerPackageTrustCompositionTests.swift` edit is larger than DD-11's "2 lines" | **ACCEPT.** DD-11's binding intent is *one* enumeration of grant-mentioning surfaces, preserved exactly; the extra lines are a required comma and a comment that would otherwise have contradicted the assertion beneath it. Correctly reported rather than absorbed. The stated size is off by one line (S5) |
| 3 | Fact labels chosen (`Type`, `Homepage`, `Tap`, `Version`, `Link state`, `Other versions`, `Pin state`, `Updates`) | **ACCEPT.** II15 is explicitly "member-name-neutral" and pins values, not labels. All eight are unique (asserted), and `Pin state` reuses `InstalledRow.swift`'s shipped pin *values* (`Pinned at 1.2.3` / `Pinned`) so the two surfaces agree. Labelling the row `Pin state` rather than `Pinned` avoids a label equalling its own value |

One deviation was **not** recorded — see S1.

---

### TDD Compliance

| Check | Result | Details |
|-------|--------|---------|
| TDD Evidence reported | ✅ | Full cycle table in `apply-progress.md` covering every task |
| All tasks have tests | ✅ | 17/17 behavioural task rows; the one non-behavioural unit is exempted in writing |
| RED confirmed (tests exist) | ✅ | Both new test files exist and compile; every named case executes |
| GREEN confirmed (tests pass) | ✅ | **18/18** observed passing by name at runtime, not inferred |
| Triangulation adequate | ✅ | Tri-state cask asserted pairwise-distinguishable; three pin states; both link states; 1/2/3-keg formulae; 7-shape absence enumeration; `Mirror` structural proof per kind |
| Safety Net for modified files | ✅ | WU2 239/239 with an **identical test-id set**; WU3/WU4 1,835→1,837 core; WU5 239/239 → 245 |

**TDD Compliance: 6/6.**

Two RED rows warrant explicit comment, and both survive scrutiny:

- **WU2 has no RED row.** `tasks.md` :157-160 pins this in advance: strict TDD sequences RED before
  GREEN for *behavioural* tasks, and dropping `private` from five helpers adds no behaviour. Its guard
  is an approval test — the byte-identical 239-id set before and after. Legitimate.
- **WU4's RED is self-attested** (source file moved aside → 504 × `cannot find
  'InstalledDetailProjection' in scope`, then restored) because the two tests were authored after WU3
  landed. Not reproducible post-hoc, but **independently corroborated**: commit `e3cab43` contains
  **zero production lines** (only `InstalledDetailProjectionTests.swift` +120 and `tasks.md`), which is
  exactly the situation that forces the file-move technique. Accepted.

---

### Test Layer Distribution

| Layer | Tests | Files | Tools |
|-------|-------|-------|-------|
| Unit (`unit`, CellarCore) | 12 | 1 new (+1 fixture modified) | Swift Testing / `swift test` |
| Unit-app (`unit-app`, source-scan composition) | 6 | 1 new (+1 modified) | Swift Testing / `xcodebuild test -only-testing:cellarTests` |
| E2E (XCUITest) | 0 new | 0 — `cellarUITests/` byte-untouched | XCTest |
| **Total new** | **18** | **2 new, 2 modified** | |

Both classes are the established ones (`openspec/specs/app-updates/spec.md:16-17`); no new verification
class is introduced, and no `manual-evidence` scenario exists in this change.

---

### Assertion Quality

| File | Line | Assertion | Issue | Severity |
|------|------|-----------|-------|----------|
| `InstalledDetailProjectionTests.swift` | 442–443 | `#expect(launcher.launchCount == 0)`, `#expect(launcher.specs.isEmpty)` | `RecordingProcessLauncher` is constructed at :394 and **never injected into anything**. Both assertions pass unconditionally regardless of production behaviour | WARNING (W3) |

Everything else is clean, and several patterns are notably strong rather than merely acceptable:

- **Every absence assertion runs behind a positive anchor.** `assertAnchored(_:)` fails loudly if a
  renamed file made the scan read nothing; `aReceiptBackedDetailCreatesNoCatalogRecord` proves the index
  really answers by finding `curl` before asserting `widget` is missing; the empty-value enumeration
  guards `emitted.isEmpty == false` first. There are **no ghost loops** here.
- **Comments are stripped before prohibition scans** (`AppSecuritySources.stripComments`), so a rule
  described in a doc comment is never mistaken for one violated in code — while exact-copy comparisons
  correctly use `raw`.
- No tautologies, no orphan empty checks, no type-only assertions, no smoke tests, no mock-heavy files.

**Assertion quality**: 0 CRITICAL, 1 WARNING.

---

### Quality Metrics

**Compiler**: ✅ `** BUILD SUCCEEDED **`, **0 warnings** across the whole project.

**Linter**: ⚠️ SwiftLint is installed but **not wired into this project** — there is no `.swiftlint.yml`
anywhere in the tree and no lint build phase — so the following are default-rule advisories, not gate
failures. Baseline comparison run against `main`'s versions of the same files:

| File | Finding | New? |
|---|---|---|
| `PackageDetailView.swift` | file_length 858, type_body_length 632 (error), function_body_length, line_length | **Pre-existing** — and **improved** by m10 (main: 874 / 651) |
| `InstalledDetailProjection.swift` | 3 × nesting (types nested 2 deep) | New — a direct consequence of DD-2's deliberate sum-type design |
| `InstalledDetailProjectionTests.swift` | file_length 465, type_body_length 348 | New |
| `PerPackageTrustCompositionTests.swift:32` | line_length 123 | New — the DD-11 anchor line; main had zero findings in this file |
| `PackageDetailView+Receipt.swift` | — | **Clean** |

---

### Commit Hygiene & Size

| Check | Result |
|---|---|
| Conventional commits | ✅ 6/6 (`docs(sdd)`, `refactor(browse)`, `feat(installed)`, `test(installed)`, `feat(browse)`, `docs(sdd)`) |
| `Co-Authored-By` / AI attribution | ✅ **None** on any commit |
| One work unit per commit | ✅ WU1–WU5 map 1:1; WU4 verified to contain **zero production lines** (S7 notes one cosmetic spill) |
| Working tree | ✅ Clean; nothing pushed, no PR opened, no review lifecycle started |

**Measured size** — `git diff --shortstat main...HEAD`: **16 files changed, 3,116 insertions(+),
41 deletions(−)** = **3,157 changed lines** against the cached `review_budget_lines: 5000` → **63 %**.
With this report the branch lands near **3,550 / 5,000**. `single-pr` stands; no chain, no
`size:exception`. Code+tests are 1,280 of that; SDD artifacts 1,877.

---

### Issues Found

**CRITICAL**: None.

**WARNING**

- **W1 — the declared verify runner exits 65.** `xcodebuild test … -scheme cellar` ends
  `** TEST FAILED **` on `cellarUITests.testTapDetailFilteringInstalledHandoffAndForceDisclosure`
  (`cellarUITests.swift:231`, *"Failed to get matching snapshot: … Multiple matching elements found"*)
  and `cellarUITests.testTapsNavigationOfficialSourcesAndAddConfirmation` (`:209`, `XCTAssertTrue
  failed`).
  **Classified pre-existing and out of scope on independently produced evidence, not on the apply
  report's word**: this verifier checked out `main` @ `5a0860b` in a separate worktree, confirmed
  `cellarUITests.swift` byte-identical, ran exactly those two cases, and reproduced **both failures at
  the same two line numbers with the same two messages** (exit 65). Corroborating: `cellarUITests/` has
  a zero-line diff, both cases exercise only the Taps surface (`taps-list`, `tap-package-filter`,
  `tap-add-field`, `tap-force-untap-button`), and m10 touched no Taps view and no `TapProjection`.
  **This is the finding that most needs a human decision** — see "Discharge path" below. m9's round-2
  verify skipped the UI suite entirely, so m10 is the first change in this project to surface it.
- **W2 — II15 sc7 is PARTIAL.** The scenario's GIVEN includes "a grant report granting a package of the
  same kind and name under some tap", and its second THEN is "it carries no per-package grant marker".
  `aWithheldTapProducesNoOriginFact` constructs **no grant report at all**; it proves only the
  fact-absence half. The marker half holds by construction (the pane's single
  `if let tap = snapshot.tap, let origin = detail.tapOfOrigin` guard makes
  `TapProjection.grantsIndividually` unreachable without a tap), but no test exercises it. Note the
  declared class `unit` cannot assert it — the projection has no marker member — so the scenario is
  partly unassertable as classified.
  *Remediation*: add one `unit-app` case in `ReceiptDetailCompositionTests` asserting the marker call
  site is lexically inside the tap guard, **or** reclassify sc7's second THEN to `unit-app` and assert
  it there. Either is a test-only change.
- **W3 — a vacuous assertion in `theHandoffLandsOnAReceiptBackedDetail`.**
  `InstalledDetailProjectionTests.swift:394` constructs `RecordingProcessLauncher()` and never passes it
  to anything; `:442-443` then assert `launchCount == 0` and `specs.isEmpty`. Both pass no matter what
  the production code does, so TM5 sc10's "no additional brew invocation is recorded" clause has no
  runtime evidence *from this test*. The clause is genuinely covered elsewhere (II15 sc2's per-token
  source scan of both files, plus the projection's total pure init), so this is an assertion-quality
  defect rather than a coverage hole.
  *Remediation*: delete the two assertions and let the doc comment cite sc2, **or** wire the launcher
  through a real `BrewClient` path so the count means something.
- **W4 — task 6.7 incomplete.** The PR is not opened and nothing is pushed. This is a delivery task the
  launch brief explicitly forbade, not an implementation gap, and the body text it asks for is drafted
  in `apply-progress.md`.
  *Remediation*: push `feat/m10-third-party-detail`, open the single PR with the drafted (a)–(d) body
  plus W1's disclosure, and tick 6.7 before archive.

**SUGGESTION**

- **S1 — one unrecorded design deviation: install-state fact ordering.** The pane renders
  `Version, Link state, Other versions, Pin state, Installed as, Size on disk`; the design's Fact
  inventory table lists `Installed as` and `Size on disk` *before* the kind-specific facts. The
  implementation follows DD-7's operative verb ("**appended** into the install-state group by the
  pane"), and II15 mandates ordering only *between* the three groups, so no spec clause breaks — but
  the design's own table and prose disagree. Fix the table at archive, or record the deviation.
- **S2 — sc10's marker test does not pin the binding.** It asserts the pane *mentions*
  `TapProjection.grantsIndividually(` and `TapProjection.grantMarker`; a refactor that resolved the
  marker and then dropped it instead of passing `note:` to `receiptFact(origin, …)` would still pass.
  Consider asserting the `receiptFact(origin, note:` call shape. Folds naturally into W2's fix.
- **S3 — new SwiftLint advisories** (3 nesting on the projection, 2 size on the new test file, 1
  line_length on the DD-11 anchor). SwiftLint is unconfigured in this project, and m10 *reduced*
  `PackageDetailView.swift`'s pre-existing violations. Informational only.
- **S4 — `apply-progress.md` line accounting understates the branch.** It reports 2,901 changed lines;
  the measured total is **3,157** (`3,116+ / 41−`), because its own 256 lines were not yet committed
  when the table was written. Both are far under 5,000; correct the figure at archive.
- **S5 — deviation #2's stated size is off by one.** It says "3 additions / 2 deletions"; the measured
  diff for `PerPackageTrustCompositionTests.swift` is **4+ / 3−**. The prose does account for the
  comment line separately, so this reads as an arithmetic slip rather than a concealment.
- **S6 — two design size estimates overrun.** `InstalledDetailProjectionTests.swift` is 465 lines
  against an estimate of 240–360; `PackageDetailView+Receipt.swift` is 176 against 120–170. Harmless,
  but the test file's size is what triggers S3's file_length advisory.
- **S7 — one cross-work-unit spill.** WU5's commit `65a65cb` also carries a 7-line cosmetic reformat of
  `InstalledDetailProjectionTests.swift` (a `typealias` to shorten a long closure signature), which
  belongs to WU3/WU4's file. Cosmetic; no behaviour moved.

---

### Discharge path to a passing round 2

W2, W3, W4 and S1–S2 are all small and test- or document-side; none touches shipped behaviour. W1 is the
only one that needs a decision this verifier must not make alone, because both available routes change
the change's scope or its evidence contract:

| # | Action | Owner | Effect on the envelope |
|---|---|---|---|
| 1 | Add the sc7 marker assertion (W2) and fix S2 in the same case | `sdd-apply` | `scenarios: 25/25` |
| 2 | Remove or wire the unused launcher (W3) | `sdd-apply` | Assertion quality 0 WARNING |
| 3 | Correct S1's fact-inventory table, S4's line total, S5's diff size | `sdd-apply` | Artifacts self-consistent |
| 4 | Push and open the single PR, disclosing W1 in the body (W4) | maintainer | Task 6.7 ticked |
| 5 | **W1 — needs a human decision.** Either (a) repair the two pre-existing `cellarUITests` cases, which is a scope expansion m10 did not plan and its specs do not cover, or (b) accept a scoped verify runner for this change and track the UI defect as its own follow-up | **maintainer** | Only (a) yields `test_exit_code: 0` |

Route (b) is the one consistent with this project's own precedent — the two failures predate m10, m9
shipped over them, and both live on the Taps surface that m10's specs deliberately do not reach. But
choosing it means the branch merges with a red full suite, so it is the maintainer's call, not the
verifier's.

---

### Verdict

**FAIL — on evidence completeness only. 0 blockers, 0 CRITICAL, 4 WARNING, 7 SUGGESTION.
3/3 requirements, 24/25 scenarios.**

Nothing m10 ships is defective. The implementation matches the contract with unusual precision: every
pinned copy string is byte-verified (including the U+2019 apostrophe by hexdump), the formula/cask
asymmetry is proved *unrepresentable* rather than merely unwritten, absence is enumerated across seven
shapes rather than sampled, and the three bindings that could have silently broken —
`project.pbxproj`, `openspec/specs/**` and `cellarUITests/**` — all hold a genuine zero-line diff.

The verdict is `fail` because a passing one requires complete scenario coverage and a green declared
runner, and this branch has neither: one scenario clause is unasserted (W2), and the declared runner
exits 65 on two failures that this verifier proved are pre-existing (W1). **Not archive-ready as it
stands** — but the distance to a passing round 2 is four small test- and document-side edits plus one
maintainer decision, all itemised above.
