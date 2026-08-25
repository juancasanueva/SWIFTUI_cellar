```yaml
schema: gentle-ai.verify-result/v1
evidence_revision: sha256:db79e6e6ade774aca87750232dad4613862e775701c417a98231aac5281766fc
verdict: pass_with_warnings
blockers: 0
critical_findings: 0
requirements: 4/4
scenarios: 35/35
test_command: xcodebuild test -project cellar.xcodeproj -scheme cellar -destination 'platform=macOS,arch=arm64' -only-testing:cellarTests
test_exit_code: 0
test_output_hash: sha256:c02a5f44cac7d5602fc562d9e461678f14124302706a368e206c1e90e1569133
build_command: xcodebuild build -project cellar.xcodeproj -scheme cellar -destination 'platform=macOS,arch=arm64'
build_exit_code: 0
build_output_hash: sha256:5bbf7ed9545a911797c45ce6f6172bb3427201bc7b31f1552ae4545f89d12899
```

## Verification Report — round 3 (supersedes rounds 1 and 2)

**Change**: `m11-tap-search`
**Version**: spec deltas **r3** — PS8 ADDED, PD6 MODIFIED, TM5 + TM11 MODIFIED. **Unchanged since
round 2**: `openspec/changes/m11-tap-search/specs/**` has a zero-line diff across the remediation.
**Mode**: Strict TDD (`openspec/config.yaml` `testing.strict_tdd: true`), coverage threshold 0
**Branch**: `feat/m11-tap-search` @ `f98d9fa`, **14 commits** off `main` @ `edda9a5`, working tree
clean before this run and carrying only this rewritten report after it
**Artifact store**: hybrid — this file is canonical; Engram topic `sdd/m11-tap-search/verify-report`
mirrors it. RDD disabled: no review lifecycle, no receipt, delivery under ordinary repository policy.
**Delivery**: `single-pr` with a maintainer-accepted `size:exception` (2026-08-25). The branch now
measures **6,340** changed lines against the 5,000 budget — recorded, **not** a finding.
**Independence**: fresh context. Every runner was re-executed against `f98d9fa`; the remediation's own
RED proof was re-derived here rather than accepted on report.

---

### Round 2 summary (superseded)

Round 2 (`36f1b8d`) returned **`verdict: fail` on evidence completeness only — 0 blockers, 0 CRITICAL,
4 WARNING, 7 SUGGESTION, requirements 4/4, scenarios 34/35**. One fact denied a passing verdict:

- **W1** — PS8 sc15's THEN reads *"**neither** contains a trust type name, a trust badge or a trust
  control"*, where "neither" names the **projection** and the **surface**.
  `theBrowseTapSurfaceComposesNoTrustGateAndNoBadge` still scanned the round-1 pair
  (`BrowseView.swift`, `TapSearchView.swift`), spending both slots on a file byte-identical to `main`
  that already had its own dedicated test. `TapPackageSearch.swift` was never scanned for trust, so the
  scenario was **PARTIAL**. The clause was true — round 2 verified by inspection that all eight
  forbidden identifiers occurred zero times in the projection — but nothing enforced it.

Round 2 also raised **W2** (task `6′.7` open), **W3** (the latency scenario is release-gated and so
skipped by the declared `unit` runner), **W4** (exact latency figures not independently reproducible),
and **S1–S7**. All four warnings and all seven suggestions are re-assessed below; W1 is **closed**.

### The remediation, verified

`81d4783` — *"test(taps): scan the projection and the surface, not Browse, for trust references"* —
**one file, +17/−11, no production line**. It does exactly what W1's remediation prescribed, and one
thing more:

| Change | Verified |
|---|---|
| `let scanned = [browse(), surface()]` → `for source in [projection, surface]` | ✅ Both PS8-named sources now scanned for all eight identifiers |
| The whole-file lowercase `trust` sweep moved out of the loop and scoped to `surface` alone | ✅ Justified in-code by TM5's pinned `"…while this tap is untrusted."`, and the projection remains covered by the eight-identifier scan |
| Renamed `theBrowseTapSurfaceComposesNoTrustGateAndNoBadge` → `theTapSearchSurfaceComposesNoTrustGateAndNoBadge` | ✅ Not requested, but correct: the old name described the round-1 topology where the surface lived inside Browse |

**The exemption is minimal and precisely bounded.** `TapPackageSearch.swift` contains exactly **one**
occurrence of `trust` in any case — line 147, inside the pinned TM5 sentence — and **zero** occurrences
of all eight forbidden identifiers (`TrustGrantStore`, `TrustGrantState`, `TapProjection.trust(`,
`TapCommand`, `"Untrusted"`, `"Trust`, `grantsIndividually`, `grantMarker`), re-checked this session.
`TapSearchView.swift` contains **zero** occurrences of `trust` in any case, so the sweep it still
carries is the strictest of the two and is applied to the file that can bear it.

**Independent RED proof.** I did not rely on the orchestrator's mutation. I planted a **different**
identifier and a second, distinct probe, ran the scoped suite, and restored both byte-identically:

| # | Mutation | Expected | Observed |
|---|---|---|---|
| **MA** | `private let grantMarker = 0` in **`TapPackageSearch.swift`** — the file round 2's test never read | the corrected scan rejects it | ❌ `** TEST FAILED **` — `theTapSearchSurfaceComposesNoTrustGateAndNoBadge` failed; **every other test in the suite passed** |
| **MB** | `private let trustProbe = 0` in **`TapSearchView.swift`** — a lowercase `trust` that is none of the eight identifiers | the rescoped whole-file sweep rejects it | ❌ `** TEST FAILED **` — the same single test failed; every other test passed |

**MA is the decisive one**: it is precisely the regression that would have passed silently under round
2's test. Both files restored with `shasum -a 256` matching the pre-mutation digest, and
`git status --porcelain` printed nothing. The corrected assertion is load-bearing in both directions —
it catches an identifier in the projection and a bare `trust` in the surface — and it is not
over-broad, because it left the other nine tests in the suite untouched in both runs.

---

### Completeness

| Metric | Value |
|--------|-------|
| Task checkboxes total (both rounds) | 115 |
| Complete | 113 |
| Incomplete | **2** — `6.7` (round 1, marked **VOID** in the file, deliberately unchecked) and `6′.7` (open the PR) |

Unchanged from round 2 and re-counted this session: 113 `- [x]`, 2 `- [ ]`. Round 1 is 58 of 59 with
`6.7` void; **round 2 is 55 of 56**, the single open box being `6′.7`, a delivery task successive
launch briefs have forbidden. The remediation added no task and closed none.

---

### Build & Tests Execution — all four runners re-executed at `f98d9fa`

**Build**: ✅ Passed — `** BUILD SUCCEEDED **`, exit 0.

**Tests**: ✅ all green, 0 failures.

| # | Runner | Exact result | Exit | Output sha256 |
|---|---|---|---|---|
| 1 | `xcodebuild test … -only-testing:cellarTests` | **`** TEST SUCCEEDED **`** — 267 passing results / **257** distinct ids, 0 failed | 0 | `c02a5f44…9133` |
| 2 | `swift test --package-path Packages/CellarCore` | **1,870 tests / 217 suites passed, 1 known issue** | 0 | `4550ee17…71ae` |
| 3 | `xcodebuild build … -scheme cellar` | **`** BUILD SUCCEEDED **`** | 0 | `5bbf7ed9…2899` |
| 4 | `swift test -c release … --filter 'TapPackageSearchTests'` | **32 tests / 1 suite passed** — both latency rows ran and passed | 0 | `79fc4a87…1c27` |

The app-target counts are **identical to round 2** (267/257), which is the expected signature of a
pure rename: one test changed identity, none was added or removed. The core suite is likewise
unchanged at 1,870/217 with the one shipped known-issue row. The
`OperationCenterCancelTests.swift:183` timing flake did not occur in this session's core run, so no
re-run was needed.

**Latency (release configuration, runner 4)**: both rows passed — `theCatalogKeystrokeTurnIsUnchanged`
in 1.520 s and `theTapSurfaceKeystrokeTurnStaysUnderTheCeiling` in 2.103 s. The binding assertions are
`p95 < 8 ms` **and** `max < 8 ms`, and the tap row proves its own worst case before measuring: the
empty query is first among ≥101 queries and is asserted to reach every published package, so a p95
cannot step over the turn DD-16 makes the most expensive.

**Coverage**: ➖ Not available — no coverage tool is configured; threshold is 0.
**Linter / type checker**: ➖ No separate linter; the Swift 6 compiler is the type checker and both
targets build clean.

---

### Evidence continuity — why round 2's proofs still bind

Every production file is **byte-identical between rounds**, SHA-verified this session rather than
assumed:

| File | sha256 at `36f1b8d` and at `f98d9fa` |
|---|---|
| `Packages/CellarCore/Sources/BrewClient/TapPackageSearch.swift` | `3b8c0783c33d728aa9fe4256b278372a044341aafb7d0b7e3debf8c6d58f1807` |
| `cellar/Browse/TapSearchView.swift` | `b185b6ab4d26b38a38093f6d0a1ca44cfd4cf698edbdc674ea0d7ac4a1804410` |
| `cellar/Browse/BrowseView.swift` | `aca5633672dc65f340cee093dc740b9b1026a9ffed96d43c4d842b79f6b19cae` |

`git diff --stat 36f1b8d..f98d9fa` lists exactly two files: the 28-line test edit and the round-2
report. **No production line changed between rounds.** Round 2's six reversible mutations (M1–M6 —
routability guards, empty-query listing, token-aware ladder, published-name cap, copy ownership, Browse
untouchability) therefore still prove exactly what they proved then, against the same bytes, and are
not re-run here. Rounds 2 and 3 together contribute **eight** independent non-vacuity proofs.

---

### Spec Compliance Matrix

35 scenarios across 4 requirement blocks, re-counted from the files this session
(`rg -c '^### Requirement:'` → **4**, `rg -c '^#### Scenario:'` → **35**): PS8 **17**, PD6 **4**
(3 reproduced byte-identical + 1 new), TM5 **11** (10 + 1), TM11 **3** (2 + 1) — **20 new**.

#### PS8 — packages published by installed third-party taps (17 scenarios)

| Scenario | Test | Result |
|---|---|---|
| Found by a non-empty query | `TapPackageSearchTests > aTapPackageIsFoundByANonEmptyQuery` | ✅ COMPLIANT |
| The ladder is token-aware | `> aHyphenatedNameMatchesByTokenAtEveryRung`, `> theLadderConvergesWithTheCatalogIndexOnOneFixture`, `> aTapNameQueryMatchesThroughThePublishedName` | ✅ COMPLIANT |
| The composed order is total and reproducible | `> theOrderIsTotalAndReproducible` | ✅ COMPLIANT |
| Five facts and its copy, nothing else | `> aHitCarriesItsFiveFactsAndItsCopyAndNothingElse` | ✅ COMPLIANT |
| The kind filter restricts the source | `> theKindFilterIsHonoured` | ✅ COMPLIANT |
| An empty query lists everything | `> anEmptyQueryListsEveryTapPackage`, `> theDefaultListingOrderMatchesTheSearchOrder` | ✅ COMPLIANT |
| Unavailable / empty is an ordinary empty state | `> anUnavailableInventoryIsAnEmptyStateNotAnError`, `> thePresentationDistinguishesEveryEmptyReason`, `> theEmptyStateCopyIsExact`, `> thePresentationKeepsStaleContentWhileRefreshing` | ✅ COMPLIANT |
| A collision is reported and never suppressed | `> aCollidingHitIsShownAndIsNotRoutable`, `> theCollisionNoteIsPresentExactlyWhenItIsTrue` | ✅ COMPLIANT |
| Three install states with exact copy | `> theThreeInstallStatesCarryTheirExactCopy` | ✅ COMPLIANT |
| An ambiguous installed hit is not routable | `> anAmbiguousInstalledHitIsNotRoutable`, `> twoTapsPublishingOneNameAreBothUnroutable` | ✅ COMPLIANT |
| Hide-installed composes; no outdated control | `> hideInstalledSubtractsFromTheSection`, `> theTapSourceAdmitsNoOutdatedPredicate`, `TapSearchCompositionTests > theTapFilterBarOffersNoInertControl` | ✅ COMPLIANT |
| The surface holds the ceiling on its own turn | `> theTapSurfaceKeystrokeTurnStaysUnderTheCeiling`, `> theCatalogKeystrokeTurnIsUnchanged`, `> theCatalogFixtureIsTheOnePS6MeasuresOver` | ✅ COMPLIANT (release runner — **W2**) |
| Its own titled entry; not-installed rows inert | `TapSearchCompositionTests > theTapSearchSurfaceIsWiredAtEveryAppSectionSite`, `> theSurfaceTitleIsTheSidebarEntry`, `> notInstalledTapRowsAreNotSelectable` | ✅ COMPLIANT |
| An installed hit opens the receipt-backed detail | `> theTapSurfaceResolvesThroughTheSharedDetail` | ✅ COMPLIANT |
| **No trust gate and no local copy** | **`> theTapSearchSurfaceComposesNoTrustGateAndNoBadge`** (projection **+** surface) **, `> theSurfaceCopyLivesInTheProjectionNotTheView`** | ✅ **COMPLIANT — was PARTIAL in round 2** |
| Composing reaches no process layer | `> neitherTapSearchFileReachesTheProcessLayer`, `TapPackageSearchTests > theProjectionTakesNoLauncherAndNoCatalogStore` | ✅ COMPLIANT |
| The catalog query surface is untouched | `> browseIsUntouchedByThisChange` + `git diff --stat main...HEAD` (BrowseView.swift absent from the changed-file set) | ✅ COMPLIANT (durability — **S3**) |

**ps15 re-traced in full.** The scenario's GIVEN names two sources and its WHEN applies three scans.
All six cells are now covered by a passing test:

| | trust type name | trust badge / control | install-state + collision copy |
|---|---|---|---|
| **Projection** | ✅ `theTapSearchSurfaceComposesNoTrustGateAndNoBadge` (8 identifiers) | ✅ same test | ✅ `theSurfaceCopyLivesInTheProjectionNotTheView` (must **contain** all six sentences) |
| **Surface** | ✅ same test + whole-file lowercase sweep | ✅ same test | ✅ same test (must **not** contain any of them) |

The THEN's second half — *"the install affordance is offered for every hit whatever the origin tap's
trust state"* — is asserted in the same test over the unconditional `MutationMenu(center:)` /
`PackageEntry(installed: nil, catalog: nil, id: hit.mutationTarget)` composition, with `MutationCommand`,
`PackageTarget(`, `submit(`, `FormulaID` and `CaskID` all asserted absent from the surface.

#### PD6 (4), TM5 (11), TM11 (3)

| Requirement | Scenario | Test | Result |
|---|---|---|---|
| PD6 | A composed tap surface leaves catalog search unchanged (new) | `TapPackageSearchTests > aComposedTapSearchLeavesTheIndexUnchanged` | ✅ COMPLIANT |
| PD6 | 3 reproduced scenarios | shipped `package-detail` suites, unmodified and green | ✅ COMPLIANT |
| TM5 | The inventory feeds an outside search surface (new) | `> theTapInventoryFeedsASurfaceOutsideTapManagement` | ✅ COMPLIANT |
| TM5 | 10 reproduced scenarios | `TapProjectionTests` + `TapShippingProofTests`, unmodified and green | ✅ COMPLIANT |
| TM11 | A tap package found elsewhere adds no action (new) | `> aTapPackageFoundHereAddsNoTapManagementAction` + shipped `TapShippingProofTests` enumeration | ✅ COMPLIANT (see **S1**) |
| TM11 | 2 reproduced scenarios | `TapShippingProofTests` (`:95`, `:317`), unmodified and green | ✅ COMPLIANT |

**Compliance summary**: **35/35 compliant, 0 partial, 0 untested, 0 failing.**

---

### Invariants — zero-diff proof, re-run at `f98d9fa`

`git diff --stat main...HEAD` lists 23 files (22 from round 2, plus this report). Each path below was
checked individually and returned an empty diff:

| Path | Result |
|---|---|
| `cellar.xcodeproj/project.pbxproj` | ✅ ZERO-DIFF |
| `openspec/specs/**` | ✅ ZERO-DIFF |
| `cellar/Browse/BrowseView.swift` | ✅ ZERO-DIFF |
| `cellar/Browse/PackageDetailView.swift` | ✅ ZERO-DIFF |
| `cellarUITests/**` | ✅ ZERO-DIFF |
| `PackageSearchIndex.swift` | ✅ ZERO-DIFF |
| `MutationCommand.swift` | ✅ ZERO-DIFF |
| `TapCommand.swift` | ✅ ZERO-DIFF |
| `TapProjection.swift` | ✅ ZERO-DIFF |
| `scripts/`, `.github/workflows/` | ✅ ZERO-DIFF |

`BrowseView.swift` is additionally SHA-matched to its round-2 bytes, so the remediation — which
*removed* Browse from a scan — did not touch the file it stopped scanning. No new brew invocation;
`BrewClient` depends on `Catalog` and not the reverse (II7).

---

### Coherence (Design DD-1 … DD-17)

All seventeen decisions were confirmed in round 2 against production bytes that have not changed since,
and are carried forward on the SHA continuity established above. The remediation touches no decision:
**DD-11** (the scanner lists) is the only one in its neighbourhood, and it governs
`TapSearchSources.paths` and `PerPackageTrustSources.views()`, both untouched by `81d4783`.
`BrowseView.swift` remains a member of `TapSearchSources.paths` and remains the subject of
`browseIsUntouchedByThisChange` and of `assertAnchored`, so removing it from the *trust* scan left no
dead helper and no unanchored path.

Two judgments from round 2 stand and are worth restating, because they are the two places the
implementation departed from its own tasks and was right to:

- **`@Binding var selection`, not the tasks' `@State`** — a locally-owned `@State` would leave the
  shared `PackageDetailView` arm permanently empty and make PS8 sc14 false. The binding is what
  delivers "no new routing branch".
- **`.error(_, hasLastGood: true)` maps to content, not to the unavailable copy** — **licensed by the
  spec**, which conditions the empty state on the inventory being *unavailable*. With last-good rows
  resident, "No packages from your taps." would be false while those rows are on screen. The `.failed`
  mapping is asserted over an empty inventory, exactly the case the scenario describes.

---

### TDD Compliance

| Check | Result | Details |
|---|---|---|
| TDD Evidence reported | ✅ | Two full cycle tables in `apply-progress.md`; the remediation's own RED is re-derived in this report rather than recorded there |
| All tasks have tests | ✅ | Every behavioural task names a test file |
| RED confirmed (tests exist) | ✅ | All 21 round-2 test names exist; the renamed one resolves to `theTapSearchSurfaceComposesNoTrustGateAndNoBadge` |
| GREEN confirmed (tests pass) | ✅ | 267 cellarTests + 1,870 core + 32 release-filter, all passing this session |
| Triangulation adequate | ✅ | Every row triangulated except three explicitly-marked `➖` (two deletions, one single-claim) |
| Safety net for modified files | ✅ | The remediation ran against a 267/257 baseline and returned 267/257 — a rename, provably not an addition or a deletion |
| RED where behaviour pre-existed | ✅ | Nine round-2 rows proven by reversible mutation; the remediation proven here by **MA** and **MB**, both restored byte-identically |
| Withdrawn behaviour deleted, not left green | ✅ | All seven round-1 tests for retired behaviour are gone; `isSectionVisible` survives only inside the assertion of its own absence |

**TDD Compliance**: 8/8 checks passed.

### Test Layer Distribution

| Layer | Tests | Files | Tools |
|---|---|---|---|
| Unit (`unit`) | 32 in `TapPackageSearchTests` (30 debug + 2 release-gated) | 1 + 2 fixtures | Swift Testing |
| Unit-app (`unit-app`) | 10 in `TapSearchCompositionTests`, plus edits to 3 shipped suites | 4 | Swift Testing + `#filePath` source scan |
| Integration | 0 | 0 | not applicable to this change |
| E2E (`cellarUITests`) | 0 — zero-line diff | 0 | XCUITest (out of scope) |

### Changed File Coverage

➖ Coverage analysis skipped — no coverage tool is configured. Threshold is 0.

### Assertion Quality

| File | Line | Assertion | Issue | Severity |
|---|---|---|---|---|
| `TapPackageSearchTests.swift` | 987-990 | `#expect([...8 string literals].count == 8)` | Tautology over a literal — exercises no production code | SUGGESTION (**S1**) |

Re-audited after the remediation. The rescoped sweep introduced no new pattern: the eight-identifier
loop runs over a two-element literal collection (no ghost loop), and the single whole-file sweep is a
direct assertion on a named source rather than a loop. Everything else is as round 2 found it — no
`#expect(true)`; every scan loop runs behind a positive anchor (`swiftFiles.count > 50`,
`sources.count == paths.count`, `assertAnchored`); every `.isEmpty` assertion is either paired with a
non-empty companion or is itself a positive anchor; no mocks in either new file.

**Assertion quality**: 0 CRITICAL, 0 WARNING, 1 SUGGESTION.

---

### Deviations

The twelve deviations `apply-progress.md` recorded were each judged in round 2 and **all twelve
accepted, zero rejected**. Nothing in the remediation disturbs that assessment; the production bytes
they describe are unchanged. They are not re-litigated here.

---

### Commit hygiene and branch size

- **14 commits**, all Conventional Commits, no AI attribution anywhere
  (`git log main..HEAD --format='%B'` matches none of `co-authored`, `generated with`, `claude`).
- `81d4783` is correctly typed `test(taps):` — it changes only a test file, and its subject line names
  the actual behaviour change ("scan the projection and the surface, not Browse").
- `git diff --shortstat main...HEAD` → **23 files changed, 6,314 insertions(+), 26 deletions(−)** =
  **6,340 authored lines** against the 5,000 budget, under the **maintainer-accepted `size:exception`
  (2026-08-25)**. Split: **code+test 2,649**, **artifacts 3,691**. The growth since round 2's 5,889 is
  **+445 report lines and +6 net test lines** — that is, verification itself is now the larger half of
  the increment (**S7**).
- Working tree clean at start; only this report is modified at the end. No `InfoPlist.xcstrings` churn.

---

### Out-of-scope tracked items (not findings against this change)

- The full `-scheme cellar` runner is **red on `main`** from two pre-existing `cellarUITests` Taps
  failures (`cellarUITests.swift:209`, `:231`), tracked for a separate PR by maintainer decision.
  `cellarUITests/**` carries a **zero-line diff** on this branch, re-verified. The scoped runners are
  the gate for m11.
- `PRD.md` §7 ends at **M6**; no PRD milestone closes with this change.

---

### Issues Found

**CRITICAL**: None.

**RESOLVED since round 2**: **W1** — PS8 sc15's trust scan now covers the projection. Closed by
`81d4783`, verified here by two independent mutations, one of which (**MA**) is precisely the
regression round 2's test would have missed.

**WARNING** (3):

- **W1 (was round-2 W2) — one task is open: `6′.7`, "Delivery — one PR".** 55 of 56 round-2 tasks are
  complete. `6′.7` was deferred by explicit instruction not to push and not to open a pull request; its
  six PR-body statements are drafted in `apply-progress.md`. This is a delivery task, not
  implementation, and it is the same shape m10 closed with.
  **Remediation**: open the PR with the drafted body — updating statement 2's latency figures and
  statement 6's line count to the round-3 numbers — then tick `6′.7`. No code changes.

- **W2 (was round-2 W3) — the latency scenario is not exercised by the spec's declared `unit` runner.**
  Both latency rows carry `.enabled(if: TapSearchBuildConfiguration.isRelease)`, so under
  `swift test --package-path Packages/CellarCore` they report **skipped**, not run. The scenario is
  genuinely covered, but only by `swift test -c release …`, which this session ran (32 tests, both rows
  green). This mirrors the shipped PS6 precedent exactly
  (`CatalogTests/SearchLatencyTests.swift:35` uses the same idiom), so it is house convention rather
  than an m11 novelty — but PS8's verification-class table names the debug runner for all 12 `unit`
  scenarios and does not execute two of them.
  **Remediation**: at archive, add the release invocation beside the `unit` runner in the promoted
  scenario's provenance, or note in `specs/README.md` that latency scenarios are release-gated in this
  repository, as PS6 already is. No code change.

- **W3 (was round-2 W4) — the exact latency figures are not independently reproducible.** `p95`, median
  and max are interpolated into the `#expect` failure message only, so a green run prints none of them.
  Apply's **tap p95 1.501 ms / max 1.856 ms** and **catalog p95 1.068 ms** remain apply's measurement.
  What this run independently confirms, for the second time, is the binding clause: both turns —
  including the empty-query worst case — are under **8 ms**.
  **Remediation**: none required. If the figures are quoted in the PR body, either record them with an
  `Attachment` or attribute them to apply's run.

**SUGGESTION** (8):

- **S1 — a tautological assertion.** `TapPackageSearchTests.swift:987-990` asserts
  `[...8 string literals].count == 8`, which exercises no production code. TM11 sc3's substance rests
  on the source scan below it plus the shipped `TapShippingProofTests` enumeration (`:95`, `:317`,
  backed by a real enum), both green. Read the shipped enumeration instead of restating it.
- **S2 — `AppSection.tapSearch.title == "Search taps"` is unreachable.** Its only consumer
  `ShellToolbarItems` is suppressed for every member of `pinnedHeaderSections`, and `.tapSearch` is one.
  Harmless and consistent with `.browse`, but DD-14 site 1 calls it *"pinned by spec"* and the spec pins
  nothing for `title` — correct that line at archive.
- **S3 — the zero-diff half of PS8 sc17 has no shipped enforcement.**
  `browseIsUntouchedByThisChange` enforces the no-reference half and five structural anchors every run;
  the *"zero-line difference"* clause is proven by `git diff`, re-verified this session but unassertable
  from a test without git access. Consider a CI step
  (`git diff --quiet <base> -- cellar/Browse/BrowseView.swift`).
- **S4 — correct the design's wiring table to ten sites.** `BrewfileCompositionTests.swift:617-630`
  carries a second full `rawValue` anchor and its own `count == 22`.
- **S5 — DD-17's prose overstates what the spec pins.** It says *"the four empty states"* are pinned;
  the spec pins **two**. Consequently `"Reading your taps"` (`TapSearchView.swift:184`) is the one
  user-visible sentence on this surface composed in the view and covered by no copy assertion.
  Permitted by PS8, but worth pinning if the discipline is meant to be total.
- **S6 — one intermediate commit does not build the app target.** `656e2d5` (WU6) deletes
  `isSectionVisible` while `70f7148` (WU7) removes its only caller. Apply self-reported this and
  corrected its own rollback-boundary text. No action for a single-PR merge; worth a squash if the
  branch is ever bisected.
- **S7 — three branch-size figures are now in circulation.** `apply-progress.md` 6′.6 records
  **5,754**; round 2 measured **5,889**; the branch now measures **6,340**, of which **445** is the
  round-2 report this file replaces. Quote the final figure in the PR body, and note that a re-verified
  branch grows by its own report.
- **S8 (new) — the renamed test is still referenced under its old name in two artifacts.**
  `design.md:271` lists `theBrowseTapSurfaceComposesNoTrustGateAndNoBadge` in its "Unchanged and still
  green" set, and `tasks.md:348` and `:819` name it in task text. The test now exists only as
  `theTapSearchSurfaceComposesNoTrustGateAndNoBadge`. Harmless historical drift — the artifacts record
  what was planned — but the archive should record the rename so a later reader searching for the old
  name finds it.

---

### Verdict

**PASS WITH WARNINGS.** 0 blockers, 0 CRITICAL, 3 WARNING, 8 SUGGESTION, requirements **4/4**,
scenarios **35/35**.

Round 2's single blocking finding is closed, and closed properly: the fix is a test-only change that
scans exactly the two sources PS8 names, exempts the projection from the whole-file sweep only for the
one pinned TM5 sentence that forces it, and keeps the strictest form of the sweep on the file that can
bear it. I proved it non-vacuous with a mutation the orchestrator did not use — planting `grantMarker`
in `TapPackageSearch.swift`, the exact regression round 2's test would have let through — and it failed
that test and only that test. The rename it carried is an improvement nobody asked for and the right
one, since the old name described a topology this change deleted.

Everything else re-confirms. All four runners are green with exit code 0 at `f98d9fa`. The app-target
counts are unchanged at 267/257, which is the arithmetic signature of a rename rather than an addition.
Every production file is byte-identical to round 2 by SHA, so round 2's six mutation proofs and its
DD-1…DD-17 coherence findings carry forward against the same bytes rather than on trust — eight
independent non-vacuity proofs across the two rounds. Every zero-diff invariant holds, including the
one the remediation could plausibly have disturbed: `BrowseView.swift`, removed from a scan, is
SHA-identical to the file it was removed from scanning.

The three remaining warnings are one deferred PR and two notes about how latency is measured in this
repository, none of which blocks archive. **`m11-tap-search` is archive-ready.**
