```yaml
schema: gentle-ai.verify-result/v1
evidence_revision: sha256:a60257aca94c81e5f2c90fcbd468f1e7faa78a296cf2c64d07e6176a781c42da
verdict: pass_with_warnings
blockers: 0
critical_findings: 0
requirements: 5/5
scenarios: 56/56
test_command: xcodebuild test -project cellar.xcodeproj -scheme cellar -destination 'platform=macOS,arch=arm64' -only-testing:cellarTests
test_exit_code: 0
test_output_hash: sha256:c10780b0e08ef071d6f8074abb64dbfc233d2dbce1991fa61154216469166498
build_command: xcodebuild build -project cellar.xcodeproj -scheme cellar -destination 'platform=macOS,arch=arm64'
build_exit_code: 0
build_output_hash: sha256:b2fe5342782b36b3ca84eb20428448194282d1a87e22ac7d89498af2e90efec0
```

## Verification Report — round 11 (supersedes rounds 1–10)

**Change**: `m11-tap-search`
**Version**: spec deltas **r10** — PS8 ADDED (leading icon tile), PD6 MODIFIED, TM5 + TM11 MODIFIED,
`installed-inventory` II15 MODIFIED
**Mode**: Strict TDD, coverage threshold 0
**Branch**: `feat/m11-tap-search` @ `925ccf9`, **56 commits** off `main` @ `edda9a5`, tree clean before
this run and carrying only this rewritten report after it
**Artifact store**: hybrid — this file is canonical; Engram topic `sdd/m11-tap-search/verify-report`
mirrors it. RDD disabled.
**Delivery**: `single-pr` with a maintainer-accepted `size:exception`. The branch measures **11,153**
changed lines — recorded, **not** a finding.
**Independence**: fresh context. All runners re-executed at `925ccf9`, **not co-scheduled** (round 10's
S12); four reversible mutations of my own.

---

### History (superseded)

| Round | Verdict | Substance |
|---|---|---|
| 2 `36f1b8d` | **fail** (34/35) | PS8 sc15's trust scan missed the projection. |
| 3–7 | pass_with_warnings | Installed pill; UPDATE pill; mutation handoff; name-only pane (42/42). |
| 8 `21956b0` | **fail** (42/43) | Colliding hits selectable; the selection scenario's install-state clause unenforced. |
| 9 `b93962d` | pass_with_warnings (43/43) | Closed by pinning the whole selection condition. |
| 10 `5d8f659` | pass_with_warnings (55/55) | Shared Actions section on both tap panes; new `MODIFIED II15` delta. |

---

### What round 9 of apply changed, and whether it is right

The last visible half of the round-2 instruction *"a visual copy of Browse"*. Every catalog row and every
Installed row opens with a leading icon tile; the tap rows opened with text. Rounds 3, 4 and 5 closed the
chip, pill and verb halves of that drift; this closes the tile.

| Obligation (PS8 r10) | Delivered | Verified |
|---|---|---|
| Same component, same leading position | `PackageIconTile(...)` first in the row | ✅ **MX**, **MZ** |
| **Same argument shape** as the catalog row | call text **byte-identical** to `PackageRow.swift:34` | ✅ **MY2** |
| Component declared exactly once | `CaskIconView.swift:68`, tree-walk asserted | ✅ |
| Artwork deps optional, handed in by the shell | `var assets: CaskBrowseAssets?` / `var iconLoader: CaskIconLoader?`; `ContentView` passes `caskAssets` / `caskIcons` at the one call site | ✅ |
| Tile not conditional on a catalog record | drawn for every hit; no catalog gate | ✅ |
| Surface starts no load, no async work | `code` (comments stripped) contains no `.task`, `await ` or `async ` | ✅ |
| Surface composes no artwork of its own | five forbidden constructors | ✅ **MX** |

I compared the two call sites directly rather than by type name:

```
PackageRow.swift:34      PackageIconTile(id: entry.id, assets: assets, iconLoader: iconLoader)
TapSearchView.swift:172  PackageIconTile(id: entry.id, assets: assets, iconLoader: iconLoader)
```

— identical text. The `entry` is bound once per row and read twice, so the tile and the mutation menu are
provably about the same package rather than two values that agree today.

#### The fallback claim, verified by reading — with one precision

The record states that an unknown cask token reaches `CaskIconView(isKnownToken: false)` → no CaskFlow
rungs → the coloured initial tile. Reading the chain:

- `PackageIconTile` branches on `id.kind` **only** — no catalog lookup anywhere. A formula gets
  `FormulaIconTile` (a bundled asset, **zero network**); most tap packages are formulae.
- A cask with a loader reaches `CaskIconView(token:size:isKnownToken: assets?.isKnownIconToken(name) ?? false, iconLoader:)`.
  For a third-party tap's cask that gate is `false`.
- With `icon == nil` and `loadsRemote == true`, the body renders `PackageTile(name: token, …)` — **the
  coloured initial**. The visual claim is exactly right.
- `CaskIconURL.candidateURLs(for:isKnownToken:)` returns `isKnownToken ? caskFlowIconURLs : []` **and
  then appends the App-Fair URL**. So "no CaskFlow rungs" is correct, but it is **one rung, not zero**:
  a tap cask still attempts a single App-Fair request, which normally 404s and then stamps a `.miss`
  marker with a **24-hour** retry window (`isKnownToken ? 15min : 24h`), so later renders cost nothing.
  The shipped `CaskIconURLTests.unknownTokenSkipsCaskFlow` pins exactly that single-URL result.

The precision matters only for the record's phrasing, not for the design: deviation 5's actual claim —
that adding `.task { await assets?.load() }` would buy nothing — is **correct**, because the asset
catalog gates only the CaskFlow rungs and a tap cask is never in it either way. Recorded as **S13**.

---

### Non-vacuity — four reversible mutations

Each applied, run, restored with `shasum -a 256` matching the pre-mutation digest;
`git status --porcelain` printed nothing after each. Suite-level filters throughout.

| # | Mutation | Expected | Observed |
|---|---|---|---|
| **MX** | replace the tile with `Image(systemName: "shippingbox")` | the no-local-artwork loop must bite | ❌ `bothSearchSurfacesDrawTheOneSharedIconTile` only; other **15** passed |
| **MY2** | same component, **second pipeline**: `assets: nil` | the argument-shape pin must bite | ❌ same single test; other 15 passed |
| **MZ** | move the tile **after** the kind chip | the leading-position pin must bite | ❌ same single test; other 15 passed |
| **MY** | `id: hit.id` instead of `entry.id` | — | **type-impossible**: `hit.id` is `TapSearchHit.RowID`, not `PackageID` |

**MY2 is the valuable one**: it compiles, still draws a real tile through the shared component, and
changes only which pipeline feeds it — precisely what a substring search for the type name would miss,
and precisely what the byte-identical call-text assertion exists to catch.

**MX is the one that matters for deviation 2**: it proves the relocated prohibition loop is now
*reachable* under mutation. **MY** is an incidental finding worth recording: DD-2's decision to make
`RowID` a distinct type from `PackageID` makes the most obvious wrong-identity substitution fail at
compile time rather than at review.

---

### Build & Tests Execution — re-executed at `925ccf9`, not co-scheduled

**Build**: ✅ `** BUILD SUCCEEDED **`, exit 0.

| Runner | Exact result | Exit | Output sha256 |
|---|---|---|---|
| `swift test --package-path Packages/CellarCore` | **1,879 tests / 218 suites passed, 1 known issue** | 0 | `4f85f212…d355` |
| `swift test -c release … --filter 'TapPackageSearchTests'` | **36 tests / 1 suite passed**, latency rows green | 0 | `bf91b22b…5c33` |
| `xcodebuild test … -only-testing:cellarTests` (run 1) | `** TEST SUCCEEDED **` — **262 distinct ids**, 0 failed | 0 | `c10780b0…6498` |
| `xcodebuild test … -only-testing:cellarTests` (run 2) | `** TEST SUCCEEDED **` — **262 distinct ids**, 0 failed | 0 | `ebd47502…e1d3` |
| `xcodebuild build … -scheme cellar` | `** BUILD SUCCEEDED **` | 0 | `b2fe5342…fec0` |

**Round 10's S12 remedy works.** I ran both CellarCore suites **first and alone**, before any xcodebuild
load, and `CatalogFootprintTests` passed on the first attempt — where co-scheduling produced a negative
resident-memory measurement last round. Latency holds under the 8 ms ceiling for the **tenth**
consecutive round.

#### Distinct ids — 262, by three methods

Run 1: 261 clean + 1 dropped = **262**. Run 2: 261 + 1 = **262**. Union of the two clean sets: **262**.
Against round 10's union the delta is exactly **one addition and no removals** —
`TapSearchCompositionTests/bothSearchSurfacesDrawTheOneSharedIconTile()` — matching apply's "+1 by
`comm`". Progression: **257 → 258 → 259 → 260 → 261 → 261 → 261 → 261 → 262**.

---

### Spec Compliance Matrix

**56 scenarios across 5 requirement blocks** (`rg -c '^### Requirement:'` → **5**,
`rg -c '^#### Scenario:'` → **56**): `package-search` **23** (+1), `package-detail` 6,
`tap-management` 15, `installed-inventory` 12.

| Scenario | Test | Result |
|---|---|---|
| **Both search surfaces open their rows with the one shared package icon tile** (new, `unit-app`) | `bothSearchSurfacesDrawTheOneSharedIconTile` — tree-walk uniqueness; **byte-identical call text** on both rows; five local-artwork constructors forbidden; the shared `entry` bound once and read by tile and menu; both optional properties asserted **against Browse**; leading position by range comparison on both rows; both `ContentView` call sites scoped by `callSite(…)`; and the zero-diff file re-checked | ✅ COMPLIANT — **MX**, **MY2**, **MZ** |
| The other 55 | unchanged and green | ✅ COMPLIANT |

**Compliance summary**: **56/56 compliant, 0 partial, 0 untested, 0 failing.**

---

### Invariants — re-run at `925ccf9`

| Path | Result |
|---|---|
| `cellar/Browse/BrowseView.swift` | ✅ **byte-identical to `main`** — eleventh round running |
| `cellar/Casks/**` | ✅ ZERO-DIFF — including `CaskIconView.swift`, where the tile is declared |
| `Packages/CellarCore/Sources/Catalog/**` | ✅ ZERO-DIFF — including `CaskIconURL.swift` |
| `cellar/Activity/MutationMenu.swift` · `project.pbxproj` · `openspec/specs/**` · `cellarUITests/**` | ✅ ZERO-DIFF |
| `TapProjection.swift` | ✅ ZERO-DIFF |
| `cellar/Browse/PackageRow.swift` | **+6/−27** vs `main`, from **exactly one** commit — round 3's `30608ab` — and **unchanged since `2548e40`** |

The tile was reused, never edited: the component, its loader and its URL ladder are all untouched.

---

### Round-9 deviations, judged (six recorded, not five)

| # | Deviation | Judgment |
|---|---|---|
| 1 | **`PackageRow.swift` is not zero-diff vs `main`, and the brief's bindings list said it should be** | **ACCEPT.** Verified exactly: **+6/−27**, from exactly one commit — round 3's `30608ab` — which is the diff **DD-18 exists to have produced**. Round 9 touches the file not at all. Recording the binding as "unchanged since `2548e40`" is the honest form, and saying so beats quietly satisfying a list that had gone stale. |
| 2 | **The first mutation proved less than the design claimed, and the *test* was fixed rather than the claim softened** | **ACCEPT — the round's most valuable finding.** A prohibition loop placed **after** `try #require(...)` is only reached while the file is already correct, because the `#require` throws under the very mutation the loop is meant to catch. Moving it above turned 2 issues into 3. This is a general trap in Swift Testing, not a local slip, and **MX** independently confirms the relocated loop is now reachable. |
| 3 | **`TapSearchView.swift`'s diff is far larger than estimated and almost all whitespace** | **ACCEPT.** Verified exactly: **+73/−40**, and `git diff -w` gives **+35/−2**. The re-indentation is forced by nesting the text column in an `HStack(spacing: 10)` to match `PackageRow`'s tile-to-name gap, rather than inheriting the outer stack's 6 — a 4-point mismatch on the one thing the round exists to fix. Reporting both figures is the right way to present it. |
| 4 | **`systemImage:` had to leave the forbidden list** | **ACCEPT.** `TapSearchEmptyState` has passed it to `ContentUnavailableView` since round 2; forbidding it would fail the row on shipped, correct code. The five constructors that remain are every way this file could draw artwork itself. |
| 5 | **No `.task { await assets?.load() }`, unlike `BrowseView`** | **ACCEPT.** Both reasons hold: DD-12 forbids async work in this file, and the asset catalog gates only CaskFlow rungs, which a tap cask never reaches. See **S13** for one phrasing precision — the tile still attempts a single App-Fair rung, so "no CaskFlow rungs" is exact but "no network" would not be. |
| 6 | **`WU32` shipped before `WU33` in commit order, and the test was still written first** | **ACCEPT.** Authored to a genuine 6-issue RED before any production line existed, committed after so each commit carries one kind of change. The record says which is which rather than letting the log imply otherwise. |

**Six accepted, zero rejected.**

A small note on the doc comment at `TapSearchView.swift:42-43`: it explains the absent `.task` and so
contains the literal `.task` and `await`. Harmless, and anticipated by the round-2 test design —
comments are stripped before the process-layer scan, precisely so a prohibition *described* in prose is
never mistaken for one violated in code. I verified all three occurrences are comment lines and that the
stripped `code` contains none.

---

### Completeness

| Metric | Value |
|--------|-------|
| Task checkboxes total | 286 |
| Complete | **284** |
| Incomplete | **2** — `6.7` (round 1, **VOID**) and `6′.7` (open the PR) |

Round 9 added 24 boxes and completed all 24 (260 + 24 = 284).

---

### Commit hygiene and branch size

- **56 commits**, all Conventional Commits, **no AI attribution**.
- Round 9's four are correctly ordered and typed: `docs(sdd)` amendment, `feat(taps)`, `test(taps)`,
  `docs(sdd)` record.
- `git diff --shortstat main...HEAD` → **33 files, +11,060/−93 = 11,153 authored lines**, matching
  apply's figure exactly.
- Working tree clean at start; only this report modified at the end.

---

### Issues Found

**CRITICAL**: None. **Blockers**: None.

**WARNING** (3):

- **W1 — one task is open: `6′.7`, "Delivery — one PR".** Deferred again by instruction. The drafted body
  needs the final figures — **11,153** lines, **262** distinct ids — and a statement that the tap rows
  now carry the shared icon tile.
  **Remediation**: open the PR, then tick `6′.7`. No code changes.

- **W2 — the latency scenario is not exercised by the spec's declared `unit` runner.** Both rows are
  `.enabled(if: isRelease)` and report **skipped** under `swift test`; covered only by the release
  runner, which this session ran. Mirrors the shipped PS6 precedent.

- **W3 — the exact latency figures remain unreproducible**, emitted only inside the `#expect` failure
  message. The binding clause — both turns under **8 ms** — is confirmed for the tenth round.

**SUGGESTION** (13):

**S1** tautological assertion in `TapPackageSearchTests.swift` · **S2** `AppSection.tapSearch.title` is
unreachable and DD-14 wrongly calls it spec-pinned · **S3** PS8 sc17's zero-diff half has no shipped
enforcement, hand-verified **eleven** rounds; a CI step would end the manual check · **S4** correct the
design's wiring table to ten sites · **S5** DD-17 says "the four empty states" are pinned where the spec
pins two · **S6** non-building intermediate commits in rounds 2–3 only · **S7** the branch-size figure
moves with the verify report, up and down; state the convention once at archive · **S8** rename drift in
`design.md`/`tasks.md`, four tests · **S9** round-3 deviation 3's "names no trust concept" is loose ·
**S10** record the distinct-id rule at archive: **membership**, plus the **two-run union** · **S11** the
round-6 ledger arithmetic still does not foot · **S12** do not co-schedule `swift test` with
`xcodebuild`; `CatalogFootprintTests` measures a resident-memory delta and cannot survive the load —
**the remedy worked this round** · **S13 (new)** record that an unknown cask token skips the **CaskFlow**
rungs but still attempts **one** App-Fair URL, cached as a 24-hour miss; "no CaskFlow rungs" is exact
where "no network" would not be, and formula hits draw a bundled asset with no request at all.

---

### Verdict

**PASS WITH WARNINGS.** 0 blockers, 0 CRITICAL, 3 WARNING, 13 SUGGESTION, requirements **5/5**,
scenarios **56/56**.

The final visual half of "a visual copy of Browse" is closed the same way the other three were: by
reusing the shared component rather than reproducing it. The tile is drawn by a call whose text is
**byte-identical** to the catalog row's, from a component that is untouched — `cellar/Casks/**` and the
whole `Catalog` target carry zero diffs — with the artwork dependencies handed in by the same shell that
hands them to Browse, and with no load started on this surface at all.

Two judgments were worth making carefully. Apply's deviation 2 is the best methodological catch of the
whole change: a prohibition placed after a `try #require` is unreachable under exactly the mutation it
exists to catch, because the `#require` throws first — so the loop was moved above it and the mutation
re-run from 2 issues to 3. My **MX** confirms the relocated loop now bites. And deviation 1 corrects the
brief's own bindings list rather than quietly satisfying it: `PackageRow.swift` cannot be zero-diff
against `main`, because round 3's DD-18 extraction deliberately produced that diff; I verified it is
+6/−27 from exactly one commit and untouched this round.

One precision belongs in the record rather than in the code. The fallback chain does render the coloured
initial tile for a tap cask, as claimed — but `candidateURLs` skips the CaskFlow rungs and still appends
App-Fair, so a tap cask attempts one request, cached as a 24-hour miss. "No CaskFlow rungs" is exact;
"no network" would not be. The design conclusion it supports — that loading the asset catalog would buy
this surface nothing — is unaffected and correct.

Three mutations of my own hold the new guard, and the one that matters most compiles, still draws a real
tile, and changes only the pipeline behind it.

**`m11-tap-search` is archive-ready.**
