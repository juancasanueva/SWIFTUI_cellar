```yaml
schema: gentle-ai.verify-result/v1
evidence_revision: sha256:762987862a83a6d6d3dc84a50963955c272733ff7bf9b502aaa27d231c5de1f8
verdict: pass_with_warnings
blockers: 0
critical_findings: 0
requirements: 4/4
scenarios: 35/35
test_command: xcodebuild test -project cellar.xcodeproj -scheme cellar -destination 'platform=macOS,arch=arm64' -only-testing:cellarTests
test_exit_code: 0
test_output_hash: sha256:ebc22c6b8752cd45cf73579f4496a6268918a4d8b9c67fb9735fadae16f0555a
build_command: xcodebuild build -project cellar.xcodeproj -scheme cellar -destination 'platform=macOS,arch=arm64'
build_exit_code: 0
build_output_hash: sha256:fd39db5a2228166dca018bb3db14b6c5d4915f0f242d5090f2eb0d4bde2b9eac
```

## Verification Report — round 4 (supersedes rounds 1–3)

**Change**: `m11-tap-search`
**Version**: spec deltas **r4** — PS8 ADDED (install-state clauses rewritten by the 2026-08-25
maintainer UI feedback), PD6 MODIFIED, TM5 + TM11 MODIFIED
**Mode**: Strict TDD (`openspec/config.yaml` `testing.strict_tdd: true`), coverage threshold 0
**Branch**: `feat/m11-tap-search` @ `9894a6a`, **20 commits** off `main` @ `edda9a5`, working tree clean
before this run and carrying only this rewritten report after it
**Artifact store**: hybrid — this file is canonical; Engram topic `sdd/m11-tap-search/verify-report`
mirrors it. RDD disabled: no review lifecycle, no receipt, ordinary repository policy.
**Delivery**: `single-pr` with a maintainer-accepted `size:exception` (2026-08-25). The branch measures
**6,891** changed lines against the 5,000 budget — recorded, **not** a finding.
**Independence**: fresh context. All four runners re-executed at `9894a6a`; three reversible mutations
of my own choosing, none of them the three apply used.

---

### History (superseded)

| Round | Commit | Verdict | Why |
|---|---|---|---|
| 1 | — | superseded | Tap results lived as a `Section` inside `BrowseView`. Withdrawn by the 2026-08-25 scope change. |
| 2 | `36f1b8d` | **fail** (0 blockers, 0 CRITICAL, 34/35) | PS8 sc15's trust scan covered the surface but not the projection — it still scanned the round-1 pair (`BrowseView.swift`, `TapSearchView.swift`). Scenario PARTIAL. |
| 3 | `f98d9fa` | **pass_with_warnings** (35/35) | `81d4783` scanned the projection + surface and scoped the whole-file `trust` sweep to the surface. Closed, and re-proven here by planting `grantMarker` in the projection. |

Round 3 of **apply** — the maintainer UI feedback this report verifies — then landed in five commits
(`8f33b1f` docs, `9714cfc` projection, `30608ab` view, `88898d0` tests, `9894a6a` record).

---

### What round 3 changed, and whether it is right

Observed in the running app: tap rows carried a third text line reading `Installed.` or `Not
installed.`, where catalog rows carry a green **Installed** pill and say nothing when a package is not
installed. PS8 r4 now requires the tap rows to draw **the same shared pill**, withdraws both strings,
and keeps the withheld sentence as explanatory copy.

| Obligation (PS8 r4) | Delivered | Verified |
|---|---|---|
| Install state exposed as a **fact**, not a sentence | `stateCopy: String` → `stateNote: String?`, plus computed `isInstalled` | ✅ |
| Installed hit, **either** installed state, marked by the pill | `if hit.isInstalled { StatusPill.installed }`; `isInstalled` is `state != .notInstalled` | ✅ |
| **One shared component**, referenced by both surfaces | new `cellar/Browse/StatusPill.swift`; `PackageRow`'s `private func statusPill` **deleted**, its three call sites migrated | ✅ |
| Label composed by neither surface nor any projection | `StatusPill.static var installed` owns `"Installed"`; absent from both presenting files | ✅ |
| Withheld = pill **and** TM5 sentence | `stateNote` non-nil only for `.installedTapWithheld` | ✅ |
| Not-installed = no copy, no pill | both gates false; the note line is now conditional | ✅ |
| `Installed.` / `Not installed.` withdrawn from projection **and** surface | both constants deleted, not retained "just in case" | ✅ |
| TM5's own tap-detail rows keep both strings | `TapProjection.statusExplanation` untouched, `:56` still `"Not installed."` | ✅ |

**The extraction is genuinely shared, not a lookalike.** `StatusPill` carries the pill's whole
rendering — font, kerning, padding, corner radius, `help`, `accessibilityLabel` — moved intact from
`PackageRow`. Both surfaces call `StatusPill.installed`, and the private predecessor is gone, so there
is no second pill to drift toward. This is the claim PS8 r4 asks for ("the **same** pill, not one that
looks the same"), and it was only representable because the declaration lived in `PackageRow.swift`,
a file under no zero-diff constraint — **`BrowseView.swift` is untouched by the move**, verified below.

**The withdrawn-copy scan is correctly shaped.** `Installed.` is a prefix of the surviving withheld
sentence, so a bare substring search would convict the projection of carrying the copy it is *required*
to carry. The suite scans **complete Swift literals** (`"\"Installed.\""`, `"\"Not installed.\""`)
instead, which is the only honest form of the absence. I re-measured both files directly: zero
occurrences of either literal in `TapPackageSearch.swift`, `TapSearchView.swift` and `StatusPill.swift`,
while the withheld sentence survives at `TapPackageSearch.swift:171`.

---

### Non-vacuity — three reversible mutations, none of them apply's

Apply proved its rows with `Text("Installed.")`, a restored private `statusPill`, and the pill moved
above `KindTag`. I used three different probes, so the guards are tested rather than the demonstration
repeated. Each was applied, run, and restored with `shasum -a 256` matching the pre-mutation digest;
`git status --porcelain` printed nothing after each.

| # | Mutation | Expected | Observed |
|---|---|---|---|
| **MC** | `label: "Installed"` → `"INSTALLED"` **inside the shared component** | the pinned label is enforced | ❌ `bothSearchSurfacesDrawTheOneSharedPill` failed; the other **11** suite tests passed |
| **MD** | `StatusPill.installed` → `StatusPill(label: "Installed", background: …, foreground: …)` in the tap row — still the shared component, but the surface now composes the label | the drift PS8 r4 exists to forbid | ❌ same single test failed; the other 11 passed |
| **ME** | added `private func installedProbe(_ hit:) -> Int { hit.isInstalled ? 1 : 0 }` to the tap view | the narrowed routability guard still bites | ❌ `notInstalledTapRowsAreNotSelectable` failed; the other 11 passed |

**MD is the important one.** It keeps the shared component and changes only *where the label is
composed* — precisely the regression the requirement targets, and precisely what a weaker test that
merely checked "both files mention StatusPill" would have missed. **ME** discharges apply's deviation 2:
the guard was narrowed by removing `hit.isInstalled` from its forbidden list, and the compensating
assertions genuinely replace what was given up.

An earlier attempt at ME referenced a symbol that does not exist and failed to compile; I discarded it
and re-ran with a probe that builds, because a compile error proves nothing about an assertion.

---

### Completeness

| Metric | Value |
|--------|-------|
| Task checkboxes total (three rounds) | 139 |
| Complete | **137** |
| Incomplete | **2** — `6.7` (round 1, marked **VOID**, deliberately unchecked) and `6′.7` (open the PR) |

Re-counted this session: 137 `- [x]`, 2 `- [ ]` at `:430` and `:889`. Round 3 added **24** boxes and
completed all 24 (113 + 24 = 137), and correctly declares **no delivery task of its own** — the branch's
single open delivery box remains round 2's `6′.7`.

---

### Build & Tests Execution — all four runners re-executed at `9894a6a`

**Build**: ✅ `** BUILD SUCCEEDED **`, exit 0.

| # | Runner | Exact result | Exit | Output sha256 |
|---|---|---|---|---|
| 1 | `xcodebuild test … -only-testing:cellarTests` | **`** TEST SUCCEEDED **`** — **258 distinct test ids**, 268 `Test case … passed` lines, 0 failed | 0 | `ebc22c6b…555a` |
| 2 | `swift test --package-path Packages/CellarCore` | **1,870 tests / 217 suites passed, 1 known issue** | 0 | `e373d2f7…c937` |
| 3 | `xcodebuild build … -scheme cellar` | **`** BUILD SUCCEEDED **`** | 0 | `fd39db5a…9eac` |
| 4 | `swift test -c release … --filter 'TapPackageSearchTests'` | **32 tests / 1 suite passed** — both latency rows ran and passed | 0 | `294e39fe…cb86` |

The core suite is unchanged at 1,870/217 because round 3 **renames and restates** rows rather than
adding any. The one known issue is the shipped known-issue-guarded row. Apply reports one
non-reproducing extra issue in one of four core runs and declines to attribute it without evidence,
which is the right call; **it did not occur in this session's run**.

**Latency** (release, runner 4): `theCatalogKeystrokeTurnIsUnchanged` passed in 1.527 s and
`theTapSurfaceKeystrokeTurnStaysUnderTheCeiling` in 2.130 s. Binding assertions are `p95 < 8 ms` **and**
`max < 8 ms`, with the empty-query worst case asserted to reach every published package before
measuring. Third consecutive round in which the ceiling holds.

#### The disputed app-target figure, settled

Apply's round-3 deviation 5 states that my earlier "267 passing / 257 distinct" mixed two metrics, that
"roughly ten ids are reported twice under parallel execution", and that the distinct count at `8f233b1`
was **256**. I still hold the round-3 log, and `git diff --stat f98d9fa..8f233b1` touches **only the
verify report** — so cellarTests is byte-identical at both commits and the two logs are directly
comparable. Measured:

| | round-3 log (`f98d9fa`) | round-4 log (`9894a6a`) |
|---|---|---|
| `Test case … passed` lines | 267 | **268** |
| **Distinct test ids** | **257** | **258** |
| Ids appearing more than once | **3** | **3** |

The duplication is **not** ~10 ids double-reported under parallelism. It is exactly **three
parameterized tests** whose individual cases each print a line under the same id —
`aNonAnswerNeverShowsTheCard(reading:)` ×4, `hostileDownloadURLsAreNotLinked(published:)` ×5,
`theScannerDetectsAPlantedDirectConstruction(violation:)` ×4 — contributing 13 lines for 3 ids, hence
the constant offset of 10.

So the distinct count at `8f233b1` was **257, not 256**, and round 4's is **258, not 257**. Apply's
*delta* is right — `comm` over the two id sets shows exactly one id added,
`TapSearchCompositionTests/bothSearchSurfacesDrawTheOneSharedPill()`, and none removed — but both
absolutes are **one low**, and the stated mechanism is wrong. Recorded as **W4**; my own round-3 figure
of "267 passing results / 257 distinct" was arithmetically correct but the label "passing results"
invited exactly this confusion, and **258 distinct** is the honest number to carry forward.

---

### Spec Compliance Matrix

35 scenarios across 4 requirement blocks, re-counted this session (`rg -c '^### Requirement:'` → **4**,
`rg -c '^#### Scenario:'` → **35**). The r4 amendment **rewrites scenario text without changing counts**:
PS8 still 17, PD6 4, TM5 11, TM11 3.

#### The four scenarios r4 touched

| Scenario | Amended to require | Test | Result |
|---|---|---|---|
| **ps4** — five facts and its copy | "the projection-supplied **note** … absent here, because only the withheld state pins one" | `TapPackageSearchTests > aHitCarriesItsFiveFactsAndItsCopyAndNothingElse` — `hit.stateNote == nil`, `hit.isInstalled == false`, and the `Mirror` label list now reads `stateNote` | ✅ COMPLIANT |
| **ps9** — install states | renamed *"…and only the withheld state pins a sentence"*: three distinct states, first two report themselves installed **as a fact**, only the withheld carries a note, and neither withdrawn string is produced | `> theThreeInstallStatesCarryTheirExactCopy` (`:558`) — `isInstalled` asserted on all three, `stateNote` asserted `nil/sentence/nil`, both withdrawn strings enumerated as absences, and `compactMap(\.stateNote)` asserted to equal exactly the one surviving sentence | ✅ COMPLIANT |
| **ps15** — trust + copy scan | extended to the withdrawn strings and to *"the component that draws the installed mark … referenced by both surfaces, with its label composed by neither of them and by no projection"* | `TapSearchCompositionTests > theTapSearchSurfaceComposesNoTrustGateAndNoBadge` (trust half, projection + surface) · `> theSurfaceCopyLivesInTheProjectionNotTheView` (four surviving sentences + both withdrawn literals over both files) · **`> bothSearchSurfacesDrawTheOneSharedPill`** (new) | ✅ COMPLIANT |
| **five-facts integrity** | the hit must still carry exactly five stored facts | `isInstalled` is a **computed** property, so `Mirror` does not enumerate it — the five-facts assertion is unweakened by the new fact | ✅ COMPLIANT |

`bothSearchSurfacesDrawTheOneSharedPill` asserts: the component exists; the label is declared **exactly
once** inside it (`components(separatedBy:).count == 2`); both `PackageRow` and `TapSearchView` reference
`StatusPill.installed`; the private predecessor is gone; **neither presenting surface contains the
literal**; the pill is gated on `hit.isInstalled`; it sits after `KindTag` on **both** surfaces by range
comparison; and `BrowseView` contains neither `StatusPill` nor `statusPill`.

#### The other 31 scenarios

Unchanged in text and re-confirmed green: PS8's matching ladder, total order, kind filter, empty-query
listing, empty states, collision, routability, hide-installed, latency, sidebar entry, receipt-backed
detail, process-layer absence and untouched-catalog-surface; PD6's four; TM5's eleven; TM11's three.
Round 3 removed no test — the id-set diff shows one addition and zero deletions.

**Compliance summary**: **35/35 compliant, 0 partial, 0 untested, 0 failing.**

---

### Invariants — zero-diff proof, re-run at `9894a6a`

Each path checked individually and returning an empty diff:

| Path | Result |
|---|---|
| `cellar/Browse/BrowseView.swift` | ✅ ZERO-DIFF — **after** the pill extraction, which is DD-18's load-bearing claim |
| `cellar.xcodeproj/project.pbxproj` | ✅ ZERO-DIFF — `StatusPill.swift` is a **new file** and still needs no edit (`PBXFileSystemSynchronizedRootGroup`) |
| `openspec/specs/**` | ✅ ZERO-DIFF |
| `cellar/Browse/PackageDetailView.swift` | ✅ ZERO-DIFF |
| `cellarUITests/**` | ✅ ZERO-DIFF |
| `PackageSearchIndex.swift` · `MutationCommand.swift` · `TapCommand.swift` · `TapProjection.swift` | ✅ ZERO-DIFF |

**`cellarUITests.swift:226` is correctly out of scope.** Its
`app.staticTexts["Not installed."]` assertion sits in the tap-detail flow — the surrounding lines drive
`tap-package-filter`, `Show in Installed` and `tap-force-untap-button` — which is the surface **TM5**
governs, not this one. TM5 keeps both withdrawn strings by design, and `TapProjection.statusExplanation`
is byte-identical to `main`. The withdrawal is correctly scoped to PS8's surface alone.

`PackageRow.swift` is now modified (it lost its private pill), which is legitimate: it was never under a
zero-diff constraint, and it is exactly why the extraction was available at all.

---

### Coherence (Design DD-1 … DD-18)

DD-1…DD-6, DD-8, DD-10…DD-17 are unchanged and were confirmed in earlier rounds. Round 3 amends **DD-7**
and **DD-9** and adds **DD-18**:

| # | Decision | Followed? | Notes |
|---|---|---|---|
| **DD-7/DD-9 (amended)** | the projection supplies the *explanatory* note only; the state itself is a fact the row reads | ✅ | `stateNote: String?` + computed `isInstalled`; `note(for:)` is an **exhaustive** switch, so a fourth install state must decide visibly at compile time rather than inherit `nil` |
| **DD-18 (new)** | extract `PackageRow`'s private pill to an internal `StatusPill` with `static var installed` | ✅ | Both surfaces draw it; neither declares the label; `BrowseView` untouched; pbxproj untouched. The design's own reasoning for why this extraction was available and DD-10's (`EmptyResults`) was not — declaration file under a zero-diff constraint or not — is correct |

---

### TDD Compliance

| Check | Result | Details |
|---|---|---|
| TDD Evidence reported | ✅ | Round-3 cycle table with 6 rows in `apply-progress.md` |
| RED confirmed | ✅ | Projection rows are a **genuine compile failure** at 8 sites (`no member 'isInstalled'` / `'stateNote'`); view rows are reversible mutations |
| GREEN confirmed | ✅ | 258 distinct cellarTests + 1,870 core + 32 release-filter, all passing this session |
| Triangulation adequate | ✅ | Three states × `isInstalled` × `stateNote`, both withdrawn strings enumerated, position asserted on **both** surfaces rather than one |
| Safety net for modified files | ✅ | Baseline 257 distinct → 258, exactly +1, id-set diff confirms one addition and zero deletions |
| Mutations restored | ✅ | Apply reports `shasum -a 256 -c` `OK` on four files; my own three restorations independently SHA-verified |
| Withdrawn behaviour deleted, not left green | ✅ | Both copy constants **deleted** rather than orphaned — the code comment names the reason ("a live constant no caller reads is how withdrawn copy comes back"), and the private `statusPill` is deleted rather than left beside its replacement |

**TDD Compliance**: 7/7 checks passed.

### Test Layer Distribution

| Layer | Tests | Files | Tools |
|---|---|---|---|
| Unit (`unit`) | 32 in `TapPackageSearchTests` (30 debug + 2 release-gated) | 1 + 2 fixtures | Swift Testing |
| Unit-app (`unit-app`) | **12** in `TapSearchCompositionTests` (was 11), plus edits to 3 shipped suites | 5 | Swift Testing + `#filePath` source scan |
| Integration / E2E | 0 | 0 | `cellarUITests` zero-diff, out of scope |

### Changed File Coverage

➖ Coverage analysis skipped — no coverage tool configured. Threshold is 0.

### Assertion Quality

| File | Line | Assertion | Issue | Severity |
|---|---|---|---|---|
| `TapPackageSearchTests.swift` | 1017-1020 | `#expect([...8 string literals].count == 8)` | Tautology over a literal — exercises no production code | SUGGESTION (**S1**) |

Re-audited after round 3. The new assertions are sound: the label-uniqueness check uses a component
count rather than a bare `contains`; the position checks compare `Range` bounds on **both** surfaces;
the withdrawn-copy scan runs over a two-element literal collection behind the surviving-sentence anchor,
so it is not a ghost loop. No `#expect(true)`, no mocks, no smoke-test-only rows.

**Assertion quality**: 0 CRITICAL, 0 WARNING, 1 SUGGESTION.

---

### Round-3 deviations, judged

| # | Deviation | Judgment |
|---|---|---|
| 1 | **WU11 leaves the app target non-compiling until WU12** | **ACCEPT.** Identical in kind to round-2 deviation 9, and self-reported again rather than buried. `stateCopy` is renamed while the view still renders it. Reverse-order rollback is already the documented procedure, so nothing is unsafe; the unit's "independently revertible" framing was the error, and the table now says so. Feeds **S6**. |
| 2 | **`hit.isInstalled` removed from `notInstalledTapRowsAreNotSelectable`'s forbidden list** | **ACCEPT — and independently discharged.** A guard being narrowed is the kind of change that deserves suspicion, so I tested the compensation rather than reading it: **ME** planted `hit.isInstalled ? 1 : 0` in the view and the test failed. The reasoning is also sound — a `Bool` about installation cannot express routability, which additionally needs uncollided and unique, and both remain forbidden (`alsoInCatalog`, `hit.state ==`, `== .notInstalled`, plus newly-added `occurrences`). The pill's gate and the selection's gate are now asserted separately. |
| 3 | **`StatusPill.swift` does not join `PerPackageTrustSources.views()`** | **ACCEPT.** That scanner guards surfaces presenting per-package **trust** copy; the pill presents install state. Adding it would make the suite's sorted anchor assert something the file has no relationship to. One wording quibble in **S9**: the file does cite `package-trust` PT5 in a doc comment as rationale, so "names no trust concept" is loose — the conclusion is unaffected, since the file is not scanned and comments are stripped anyway. |
| 4 | **`TapPackage.statusExplanation` is now DD-9's original shape and is still not reused** | **ACCEPT.** Verified: it is `nil` for `.installed` — which after round 3 is exactly right — but still answers `"Not installed."` for the third state, which this surface withdrew, and it projects over `TapPackage` rather than over a hit. Keeping `TapPackageSearch.note(for:)` separate is correct, and recording it stops a future reader "simplifying" two different contracts into one. |
| 5 | **The round-2 record's "267 passing / 257 distinct" mixed two metrics** | **PARTLY REJECTED — see W4.** The diagnosis is right and worth making: the two numbers are different metrics and should not sit side by side unlabelled. But the correction is itself wrong. The distinct count at `8f233b1` was **257, not 256**, and at `9894a6a` it is **258, not 257**; the duplication comes from **three parameterized tests** contributing 10 extra lines, not from ~10 ids double-reported under parallelism. The **delta** of +1 is correct. Corrected here rather than carried into the archive. |

**Four accepted, one accepted-in-substance-but-corrected.**

---

### Commit hygiene and branch size

- **20 commits**, all Conventional Commits, **no AI attribution** anywhere.
- Round 3's five are correctly typed and ordered: `docs(sdd)` for the spec/design/task amendment
  **first**, then `feat(search)` for the projection, `feat(taps)` for the view, `test(taps)` for the
  guards, `docs(sdd)` for the record.
- `git diff --shortstat main...HEAD` → **25 files changed, +6,838/−53 = 6,891 authored lines**, matching
  apply's 6″.4 exactly. Split: **code+test 2,928**, **artifacts 3,963**. Under the accepted
  `size:exception`; recorded, not a finding.
- Working tree clean at start; only this report modified at the end. No `InfoPlist.xcstrings` churn —
  apply discarded the pre-existing churn before starting, as instructed.

---

### Out-of-scope tracked items (not findings against this change)

- The full `-scheme cellar` runner is **red on `main`** from two pre-existing `cellarUITests` Taps
  failures (`cellarUITests.swift:209`, `:231`), tracked for a separate PR. `cellarUITests/**` carries a
  zero-line diff here. The scoped runners are the gate.
- `PRD.md` §7 ends at **M6**; no PRD milestone closes with this change.

---

### Issues Found

**CRITICAL**: None.

**WARNING** (4):

- **W1 — one task is open: `6′.7`, "Delivery — one PR".** Round 3 correctly adds no delivery task of its
  own. `6′.7` remains deferred by explicit instruction not to push and not to open a pull request.
  **Remediation**: open the PR with the drafted body, applying apply's own two corrections (statement 6's
  line count → **6,891**, plus a new statement that both search surfaces now draw one shared pill), and
  a third: the app-target figure is **258 distinct test ids**. Then tick `6′.7`.

- **W2 — the latency scenario is not exercised by the spec's declared `unit` runner.** Both rows carry
  `.enabled(if: TapSearchBuildConfiguration.isRelease)` and report **skipped** under
  `swift test --package-path Packages/CellarCore`. Covered only by the release runner, which this session
  ran. Mirrors the shipped PS6 precedent (`CatalogTests/SearchLatencyTests.swift:35`), so it is house
  convention rather than an m11 novelty — but PS8's verification-class table names the debug runner for
  all 12 `unit` scenarios and does not execute two of them.
  **Remediation**: at archive, record the release invocation beside the `unit` runner, or note in
  `specs/README.md` that latency scenarios are release-gated in this repository. No code change.

- **W3 — the exact latency figures remain unreproducible.** `p95`, median and max are interpolated into
  the `#expect` failure message only, so a green run prints none. Apply's tap p95 1.501 ms / catalog
  1.068 ms are apply's measurement. What is independently confirmed, now for the third round, is the
  binding clause: both turns are under **8 ms**.

- **W4 (new) — apply's round-3 deviation 5 states two figures that are one low, and misattributes the
  cause.** The distinct-id count at `8f233b1` was **257** (not 256) and at `9894a6a` is **258** (not
  257); the offset of 10 comes from three parameterized tests, not from ~10 ids double-reported under
  parallel execution. Evidence: `git diff --stat f98d9fa..8f233b1` touches only the verify report, so the
  logs are directly comparable; both were measured this session. Left uncorrected, the archive would
  carry a wrong correction of an earlier report — the worst kind, because it looks like a fix.
  **Remediation**: amend deviation 5 in `apply-progress.md` to read "distinct ids 257 → 258; the raw
  `Test case … passed` line count exceeds it by 10 because three parameterized tests print one line per
  case". No code change.

**SUGGESTION** (9):

- **S1 — a tautological assertion.** `TapPackageSearchTests.swift:1017-1020` asserts
  `[...8 string literals].count == 8`, exercising no production code. TM11 sc3's substance rests on the
  source scan below it plus the shipped `TapShippingProofTests` enumeration, both green.
- **S2 — `AppSection.tapSearch.title == "Search taps"` is unreachable**, since `.tapSearch` is in
  `pinnedHeaderSections` and `ShellToolbarItems` is suppressed for those. DD-14 site 1 calls it "pinned
  by spec"; the spec pins nothing for `title`. Correct that line at archive.
- **S3 — the zero-diff half of PS8 sc17 has no shipped enforcement.** Proven by `git diff` each round but
  unassertable from a test without git access. Now that a *fourth* round has re-verified it by hand,
  a CI step (`git diff --quiet <base> -- cellar/Browse/BrowseView.swift`) looks increasingly worth it.
- **S4 — correct the design's wiring table to ten sites** (`BrewfileCompositionTests.swift:617-630` is
  the tenth).
- **S5 — DD-17 still says "the four empty states" are pinned by the spec**; the spec pins **two**.
  `"Reading your taps"` (`TapSearchView.swift:202`) remains the one user-visible sentence on this surface
  composed in the view and covered by no copy assertion. Permitted by PS8, and now the *only* such
  string, since round 3 removed the state sentences — which makes pinning it cheaper than before.
- **S6 — two intermediate commits do not build the app target** (`656e2d5` WU6, `9714cfc` WU11). Both
  self-reported. No action for a single-PR merge; worth a squash if the branch is ever bisected.
- **S7 — four branch-size figures now circulate** (5,754 / 5,889 / 6,340 / **6,891**). Quote only the
  final one in the PR body.
- **S8 — the test renamed in round 2's remediation is still named
  `theBrowseTapSurfaceComposesNoTrustGateAndNoBadge` in `design.md:271` and `tasks.md`.** Record the
  rename at archive.
- **S9 (new) — round-3 deviation 3's wording is loose.** `StatusPill.swift` does cite `package-trust`
  PT5 in a doc comment, so "names no trust concept" is not literally true; the conclusion (it should not
  join `PerPackageTrustSources.views()`) is right regardless, since the file presents install state and
  is not scanned by that suite.

---

### Verdict

**PASS WITH WARNINGS.** 0 blockers, 0 CRITICAL, 4 WARNING, 9 SUGGESTION, requirements **4/4**,
scenarios **35/35**.

The maintainer's UI complaint was real and the fix answers it properly. Rather than deleting two
sentences and drawing a lookalike chip, round 3 extracted the catalog row's pill into a shared component
and had both surfaces draw **the same one** — which is what makes "the two search surfaces cannot drift"
an assertion instead of an aspiration. The extraction was available only because the pill lived in
`PackageRow.swift` rather than in the zero-diff `BrowseView.swift`, and the design says so explicitly;
`BrowseView.swift` is still byte-identical to `main` after the move, which I verified rather than
assumed. The withdrawn-copy scan is shaped correctly around the fact that `Installed.` is a prefix of the
sentence that had to survive, and the projection now exposes install state as a fact a test can read
rather than a sentence a row prints — with `isInstalled` computed, so PS8's five-facts scenario is
unweakened.

I proved the new guards with three mutations of my own, none of them apply's. The one that matters most,
**MD**, keeps the shared component and moves only the label's composition into the surface — the exact
drift the requirement forbids — and it failed the new test and only the new test. **ME** discharged the
one deviation that deserved suspicion, a narrowed guard, by showing the compensating assertions bite.

All four runners are green at `9894a6a`; every zero-diff invariant holds, including the two the
extraction could plausibly have disturbed; `cellarUITests:226` is correctly untouched because it reads
TM5's tap-detail rows, not this surface; and the four amended scenarios trace to tests that assert the
new obligations rather than the old ones.

One thing does need fixing before archive, and it is documentation rather than code: apply's deviation 5
sets out to correct an earlier test-count figure and gets it wrong in both absolutes and in its stated
cause (**W4**). I have corrected it here from logs taken at both commits. **`m11-tap-search` is
archive-ready** once that record is amended.
