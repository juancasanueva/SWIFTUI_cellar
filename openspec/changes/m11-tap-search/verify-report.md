```yaml
schema: gentle-ai.verify-result/v1
evidence_revision: sha256:ea44fae668c92d4ebbed36f6bb80b192a94f36b422594903910184cb91661fd2
verdict: pass_with_warnings
blockers: 0
critical_findings: 0
requirements: 4/4
scenarios: 37/37
test_command: xcodebuild test -project cellar.xcodeproj -scheme cellar -destination 'platform=macOS,arch=arm64' -only-testing:cellarTests
test_exit_code: 0
test_output_hash: sha256:5f772468b1146a575d8657cb5243306274bea1b37b85682457936063291234af
build_command: xcodebuild build -project cellar.xcodeproj -scheme cellar -destination 'platform=macOS,arch=arm64'
build_exit_code: 0
build_output_hash: sha256:22d789de8d86ad2c7d1ab4168c700e1dc8c055791ff88c497562184a5472ff2f
```

## Verification Report — round 5 (supersedes rounds 1–4)

**Change**: `m11-tap-search`
**Version**: spec deltas **r5** — PS8 ADDED (offered-version fact and shared update pill), PD6 MODIFIED,
TM5 + TM11 MODIFIED
**Mode**: Strict TDD, coverage threshold 0
**Branch**: `feat/m11-tap-search` @ `c760d28`, **26 commits** off `main` @ `edda9a5`, working tree clean
before this run and carrying only this rewritten report after it
**Artifact store**: hybrid — this file is canonical; Engram topic `sdd/m11-tap-search/verify-report`
mirrors it. RDD disabled.
**Delivery**: `single-pr` with a maintainer-accepted `size:exception` (2026-08-25). The branch measures
**7,516** changed lines against the 5,000 budget — recorded, **not** a finding.
**Independence**: fresh context. All four runners re-executed at `c760d28`; three reversible mutations
of my own, none of them apply's two.

---

### History (superseded)

| Round | Commit | Verdict | Substance |
|---|---|---|---|
| 1 | — | superseded | Tap results as a `Section` inside `BrowseView`; withdrawn by the scope change. |
| 2 | `36f1b8d` | **fail** (34/35) | PS8 sc15's trust scan missed the projection. |
| 3 | `f98d9fa` | **pass_with_warnings** (35/35) | `81d4783` fixed the scan; re-proven by planting `grantMarker`. |
| 4 | `9894a6a` | **pass_with_warnings** (35/35) | Shared **Installed** pill (`StatusPill` extracted); `Installed.`/`Not installed.` withdrawn. Raised **W4** against apply's test-count correction. |

**Round 4's W4 is closed.** Apply amended round-3's deviation 5 **in place** (`apply-progress.md:376-381`):
it now records 257 → 258, names the correct cause (three parameterized tests printing one line per case),
and cites the verify finding. The record is accurate.

---

### What round 4 of apply changed, and whether it is right

Round 3 gave the tap rows the catalog row's **Installed** pill and stopped there. An installed tap
package whose own receipt already reported it outdated — apply cites `druk` at `1.21.1` against an
offered `1.22.1` — read as merely installed here while reading as updatable on the catalog surface and
in the Installed list. That is the second half of the drift round 3 closed.

| Obligation (PS8 r5) | Delivered | Verified |
|---|---|---|
| Offered version is a **sixth fact** of the hit | `nextVersion: String?`, **stored** | ✅ |
| Read from the **installed receipt**, never the tap or catalog | `offeredVersion(for:)` → `installed.package(id)` → `receipt.catalogVersion` | ✅ no brew invocation, PD6/TM5 untouched |
| Gated on the receipt's **own** outdated rule (II4, incl. self-updating-cask exclusion) | `guard … receipt.isOutdated` | ✅ proven by **MF** |
| Absent for not-installed **and** for installed-but-current | both return `nil` | ✅ |
| Present for the **withheld** state, which is installed | keyed off `installedHandoff`, which both installed states answer | ✅ |
| Marked by the **same shared update pill**, **after** the Installed pill | `UpdateTag(nextVersion: next)` after `StatusPill.installed` | ✅ proven by **MI** |
| Component declared exactly once; version handed as a **value** | `struct UpdateTag: View` at `PackageRow.swift:114`, sole declaration tree-wide | ✅ |
| Neither surface composes update wording | `"UPDATE"` appears only at `PackageRow.swift:119` | ✅ |
| "no version" narrowed to "no **published** version" | prohibition and test both amended | ✅ |

**The keying decision is the subtle one, and it is correct.** `offeredVersion(for:)` keys off
`TapPackage.installedHandoff`, **not** `package.id`. `TapProjection.installState` deliberately answers
`.notInstalled` for a receipt whose `tap` names a *different* tap, so a lookup by bare identity would
hang an UPDATE pill on a row this very surface calls not installed. I did not take that on the design's
word — **MG** re-keyed it to `package.id` and the dedicated test failed with
`hit.nextVersion → "9.9.9"` where `nil` was required.

**`UpdateTag` needed no extraction**, which is the round's cheapest fact and the reason
`PackageRow.swift` and `StatusPill.swift` both carry a **zero-line diff this round**: the component was
already `internal`, already drawn by the Installed and Updates lists, and already took the version as a
value — the exact shape DD-18 had to *create* for the installed pill. Round 4 joins an existing
component rather than building one, and the test says so rather than overclaiming symmetry.

**Stored, not computed — and the inverse of round 3's choice, deliberately.** `isInstalled` is computed
so `Mirror` does not enumerate it and the facts scenario stays honest at its stated count; `nextVersion`
is stored so `Mirror` *does* enumerate it, because it genuinely is a fact the hit carries. Both
decisions serve the same rule from opposite sides, and the code comments say so.

---

### Non-vacuity — three reversible mutations, none of them apply's

Apply proved its rows with a local `Text("UPDATE")` and with the chip moved above the Installed pill. I
used three different probes. Each was applied, run, restored with `shasum -a 256` matching the
pre-mutation digest; `git status --porcelain` printed nothing after each.

| # | Mutation | Expected | Observed |
|---|---|---|---|
| **MF** | drop `receipt.isOutdated` from the guard — offer a version to every installed hit | the II4 gate is enforced | ❌ `onlyAnOutdatedInstalledHitOffersAVersion` failed with **4 issues**, including the up-to-date hit gaining `"1.0.0"` and `compactMap(\.nextVersion)` returning three versions where two were required |
| **MG** | key the lookup off `package.id` instead of `installedHandoff` | a receipt from another tap must not offer a version | ❌ `aReceiptFromAnotherTapOffersNoVersion` failed — `hit.nextVersion → "9.9.9"`, exactly one issue |
| **MI** | `UpdateTag(nextVersion: next)` → `UpdateTag(nextVersion: hit.displayName)` — right component, wrong value | the value handed over is pinned | ❌ `bothSearchSurfacesDrawTheOneSharedUpdatePill` failed; the other **12** suite tests passed |

**MG is the one that matters most**, because it is the only probe that distinguishes a correct
implementation from a plausible-looking wrong one: keying off bare identity compiles, passes every other
test, and silently mislabels rows the surface itself calls not installed.

All three mutation runs used **suite-level** `-only-testing:` filters, per the trap apply documented
below.

---

### Completeness

| Metric | Value |
|--------|-------|
| Task checkboxes total (four rounds) | 161 |
| Complete | **159** |
| Incomplete | **2** — `6.7` (round 1, marked **VOID**) and `6′.7` (open the PR) |

Round 4 added **22** boxes and completed all 22 (137 + 22 = 159), and correctly declares no delivery
task of its own.

---

### Build & Tests Execution — all four runners re-executed at `c760d28`

**Build**: ✅ `** BUILD SUCCEEDED **`, exit 0.

| # | Runner | Exact result | Exit | Output sha256 |
|---|---|---|---|---|
| 1 | `xcodebuild test … -only-testing:cellarTests` | **`** TEST SUCCEEDED **`** — **259 distinct test ids**, 0 failed | 0 | `5f772468…34af` |
| 2 | `swift test --package-path Packages/CellarCore` | **1,872 tests / 217 suites passed, 1 known issue** (was 1,870; **+2**) | 0 | `de02f614…a929` |
| 3 | `xcodebuild build … -scheme cellar` | **`** BUILD SUCCEEDED **`** | 0 | `22d789de…ff2f` |
| 4 | `swift test -c release … --filter 'TapPackageSearchTests'` | **34 tests / 1 suite passed** (was 32; **+2**), both latency rows ran and passed | 0 | `e33a6db7…7ee7` |

Every figure apply reported reproduced: core **1,872/217**, app target **259 distinct**, release filter
**34**. The core `+2` is `onlyAnOutdatedInstalledHitOffersAVersion` and
`aReceiptFromAnotherTapOffersNoVersion`; the facts row was **renamed**, not added.

The unattributed core-suite flake apply saw in one of five runs **did not occur** in this session's run,
as in every previous round (**S11**).

**Latency** (release): `theCatalogKeystrokeTurnIsUnchanged` 1.528 s, `theTapSurfaceKeystrokeTurnStaysUnderTheCeiling`
2.099 s. Fourth consecutive round under the 8 ms ceiling, with the empty-query worst case asserted to
reach every published package before measuring.

#### Counting distinct ids correctly — a refinement to both prior methods

Apply's round-4 investigation was right that a line-based scan can silently drop an id when xcodebuild's
concurrent status block interleaves itself into a `Test case …` line. Working from the three logs I have
retained across rounds, the rule is narrower than either of us stated:

**An interleaved status block only costs an id when it lands *inside the quoted id*.** When it lands in
the line's tail — after `' passed` — the id is still extracted and already counted, so adding one would
over-count.

| Log | Mangled lines | Where the break landed | Clean distinct | Adjustment | **True** |
|---|---|---|---|---|---|
| round 3, `f98d9fa` | 1 | tail, after `' passed on 'My Mac - Home-C` — id intact | 257 | none | **257** |
| round 4, `9894a6a` | 1 | tail, id intact | 258 | none | **258** |
| round 5, `c760d28` | 1 | **inside the id** — `aFreshInstallReadsAs` + timestamp, no closing quote | 258 | **+1** | **259** |

So the progression is a clean **257 → 258 → 259**, one unit-app test added per round, and apply's 259 at
`c760d28` is correct. My own first count this round read 258 and was one low — the same trap, in my log
this time rather than apply's. The lost id is
`AutomaticUpdateChecksTests/aFreshInstallReadsAsOff()`, verified absent from the clean set and present
in the round-4 log. Recorded as **S10** so the next reader applies the narrow rule rather than either
approximation.

---

### Spec Compliance Matrix

**37 scenarios across 4 requirement blocks**, re-counted this session (`rg -c '^### Requirement:'` → **4**,
`rg -c '^#### Scenario:'` → **37**): PS8 **19** (+2), PD6 4, TM5 11, TM11 3. Verification classes tally
29 `unit` + 6 `unit-app` = 35 inline lines; the two unlabelled are PD6's reproduced scenarios, which
predate the convention — consistent with every prior round.

#### The three scenarios r5 added or amended

| Scenario | Requires | Test | Result |
|---|---|---|---|
| **six facts** (amended from five) | kind, token, published name, tap, install state, **offered version**; and no **published** version | `TapPackageSearchTests > aHitCarriesItsSixFactsAndItsCopyAndNothingElse` — `Mirror` labels enumerated, and the version-shaped members asserted **by name**: `labels.filter { $0.lowercased().contains("version") } == ["nextVersion"]` (`:194`) | ✅ COMPLIANT |
| **Only an installed hit its receipt reports outdated exposes an offered version** (new, `unit`) | four states: outdated ⇒ its own version; withheld **and** outdated ⇒ its own *distinct* version; installed-and-current ⇒ none; not-installed ⇒ none; and no offered version equals the installed one | `> onlyAnOutdatedInstalledHitOffersAVersion` (`:630`) + `> aReceiptFromAnotherTapOffersNoVersion` (`:682`) | ✅ COMPLIANT — non-vacuous by **MF** and **MG** |
| **Both search surfaces mark an available update with the one shared update pill** (new, `unit-app`) | same component, declared once; version handed as a value; drawn **after** the installed mark; gated on the offered version alone; no local update wording | `TapSearchCompositionTests > bothSearchSurfacesDrawTheOneSharedUpdatePill` — tree-walk uniqueness, both call sites, range-ordered position on **both** surfaces, three re-derivation routes forbidden (`isOutdated`, `catalogVersion`, `installed.package(`), three local-wording literals forbidden, and the label's home positively anchored | ✅ COMPLIANT — non-vacuous by **MI** |

The amended version-token assertion is **stronger** than the token scan it replaces, not weaker: the old
`contains { $0.contains("version") }` failed on any version member; the new equality also fails if
`nextVersion` is renamed or removed.

#### The other 34 scenarios

Unchanged in text and re-confirmed green, including the whole round-3 pill contract
(`bothSearchSurfacesDrawTheOneSharedPill`), the trust scan over projection **and** surface, the
withdrawn-copy literals, matching/order/collision/routability, empty states, latency, and the untouched
catalog surface. The id-set diff between rounds shows exactly one addition and none removed.

**Compliance summary**: **37/37 compliant, 0 partial, 0 untested, 0 failing.**

---

### Invariants — zero-diff proof, re-run at `c760d28`

| Path | Result |
|---|---|
| `cellar/Browse/BrowseView.swift` | ✅ **byte-identical to `main`** (`git diff --quiet` clean) — fifth round running |
| `cellar/Browse/PackageRow.swift` · `cellar/Browse/StatusPill.swift` | ✅ **ZERO-DIFF this round** (`03be818..HEAD`) — the update pill needed no extraction |
| `cellar.xcodeproj/project.pbxproj` | ✅ ZERO-DIFF |
| `openspec/specs/**` | ✅ ZERO-DIFF |
| `cellar/Browse/PackageDetailView.swift` | ✅ ZERO-DIFF |
| `cellarUITests/**` | ✅ ZERO-DIFF |
| `PackageSearchIndex.swift` · `MutationCommand.swift` · `TapCommand.swift` · `TapProjection.swift` | ✅ ZERO-DIFF |

Round 4 touched exactly **11 files**: the projection, two fixtures, two test files, the tap view, and
five artifacts. No new brew invocation: the offered version comes from an inventory the projection
already holds.

---

### Coherence — DD-19

| # | Decision | Followed? | Notes |
|---|---|---|---|
| **DD-19 (new)** | offered version from the installed receipt, keyed off `installedHandoff`, stored not computed; the shared `UpdateTag` after the Installed pill | ✅ | Both halves independently proven (**MG**, **MI**). The stored/computed asymmetry against round 3's `isInstalled` is deliberate and correctly reasoned in both directions |

DD-1…DD-18 are unchanged and were confirmed in earlier rounds against production bytes that round 4 did
not touch, except `TapPackageSearch.swift` and `TapSearchView.swift`, both re-verified here.

---

### TDD Compliance

| Check | Result | Details |
|---|---|---|
| TDD Evidence reported | ✅ | Round-4 cycle table, 4 rows |
| RED confirmed | ✅ | Projection rows are a **genuine compile failure** at 9 sites (`no member 'nextVersion'`) with no other error; view row by two reversible mutations |
| GREEN confirmed | ✅ | 259 distinct cellarTests + 1,872 core + 34 release-filter, all passing this session |
| Triangulation adequate | ✅ | Four install/outdated states, **two distinct** offered versions so a hit reading its neighbour's offer fails, plus the wrong-tap receipt as its own row |
| Safety net | ✅ | 258 → 259 distinct, exactly +1; 1,870 → 1,872, exactly +2 with one rename in and out |
| Fixture integrity | ✅ | `InstalledFixture.receipt(outdatedTo:)` sets the version **and** the flag together, so an incoherent receipt is unrepresentable — a good refactor, not just a fixture |
| Mutations restored | ✅ | Apply reports `shasum -a 256 -c` `OK`; my own three independently SHA-verified |

**TDD Compliance**: 7/7 checks passed.

**Worth promoting to the archive**: apply discovered that a **function-level** `-only-testing:` filter
(`…/TapSearchCompositionTests/someTest`) selects **nothing** for a Swift Testing test and exits
`** TEST SUCCEEDED **`. Used as a RED gate it cannot distinguish "passed" from "never ran" — a trap that
silently converts a mutation proof into a false negative. Apply caught it, disbelieved the result, and
re-ran at suite level. Every mutation run in this report used suite-level filters for that reason.

### Test Layer Distribution

| Layer | Tests | Files | Tools |
|---|---|---|---|
| Unit (`unit`) | **34** in `TapPackageSearchTests` (32 debug + 2 release-gated) | 1 + 3 fixtures | Swift Testing |
| Unit-app (`unit-app`) | **13** in `TapSearchCompositionTests` (was 12), plus edits to 3 shipped suites | 6 | Swift Testing + `#filePath` source scan |
| Integration / E2E | 0 | 0 | `cellarUITests` zero-diff, out of scope |

### Changed File Coverage

➖ Coverage analysis skipped — no coverage tool configured. Threshold is 0.

### Assertion Quality

| File | Line | Assertion | Issue | Severity |
|---|---|---|---|---|
| `TapPackageSearchTests.swift` | 1113 | `#expect([...8 string literals].count == 8)` | Tautology over a literal | SUGGESTION (**S1**) |

Round 4's new assertions are sound: the uniqueness check is a **tree walk** returning a file-name list
compared by equality (not a `contains`), positions are compared by `Range` bounds on both surfaces, and
the version-token check is an equality over a filtered label list. No `#expect(true)`, no ghost loops,
no mocks.

**Assertion quality**: 0 CRITICAL, 0 WARNING, 1 SUGGESTION.

---

### Round-4 deviations, judged

| # | Deviation | Judgment |
|---|---|---|
| 1 | **The "no version" prohibition narrowed to "no *published* version"**, and the token scan replaced by enumeration-by-name | **ACCEPT.** Verified at `:194`. The replacement is strictly stronger — it fails on a second version member *and* on renaming or removing `nextVersion`. Narrowing a prohibition because reality changed, while making its test harder to satisfy, is the right shape. |
| 2 | **The facts test was renamed five → six** | **ACCEPT.** Keeping the old name would have left a row asserting six facts under a name claiming five. The `+2` arithmetic is unaffected: one id out, one in. |
| 3 | **The Outdated control's *reason* was false after round 4 and was rewritten** | **ACCEPT, and this is the most important of the six.** PS8 said there is no outdated control "because a tap hit carries no version" — which round 4 made false. The **rule** is unchanged; only its premise is restated (the fact exists for a strict minority of listed hits, so a chip would *replace* the listing rather than filter it). PS8 promotes into the main spec at archive; leaving a false premise inside a promoted requirement would have been a durable defect. |
| 4 | **`UpdateTag` lives inside `PackageRow.swift`, so round 3's symmetric copy-ownership claim cannot be restated** | **ACCEPT.** The asymmetry is stated in the test's own doc comment rather than papered over: "neither surface composes the label" is provable for the tap view and meaningless for the declaring file, so a **tree walk** carries that half. Rejecting an extraction-for-symmetry is right — it would be a diff on a file with no reason to change, and `internal` already makes "the same component" representable, which was DD-18's problem and not this round's. |
| 5 | **The first app-target baseline was wrong; 258 is correct and verify round 4 was vindicated** | **ACCEPT**, and refined further in **S10**: the adjustment applies only when the break lands inside the quoted id. Apply also amended round-3's deviation 5 in place, closing round 4's W4. |
| 6 | **A core-suite flake recurred and its identity was lost to `tail -2`** | **ACCEPT as reported** — not attributed, not absorbed. Feeds **S11**, which now has a concrete remedy. |

**Six accepted, zero rejected.**

---

### Commit hygiene and branch size

- **26 commits**, all Conventional Commits, **no AI attribution**.
- Round 4's five are correctly typed and ordered: `docs(sdd)` amendment first, then `feat(search)`
  projection, `feat(taps)` view, `test(taps)` guards, `docs(sdd)` record.
- **WU15 is independently revertible this round** — the member is *added*, never renamed, and
  `xcodebuild build` was run at that commit to prove it. That is a direct improvement on rounds 2 and 3,
  where the analogous commit left the app target non-compiling (**S6**).
- `git diff --shortstat main...HEAD` → **26 files, +7,461/−55 = 7,516 authored lines**, matching apply's
  6‴.4 exactly. Split: **code+test 3,190**, **artifacts 4,326**. Under the accepted `size:exception`.
- Working tree clean at start; only this report modified at the end.

---

### Out-of-scope tracked items

- The full `-scheme cellar` runner is red on `main` from two pre-existing `cellarUITests` Taps failures
  (`:209`, `:231`), tracked separately. `cellarUITests/**` zero-diff here.
- `PRD.md` §7 ends at **M6**; no PRD milestone closes with this change.

---

### Issues Found

**CRITICAL**: None.

**RESOLVED since round 4**: **W4** — apply amended round-3's deviation 5 in place, correcting both
figures and the stated cause.

**WARNING** (3):

- **W1 — one task is open: `6′.7`, "Delivery — one PR".** Deferred again by explicit instruction.
  **Remediation**: open the PR with the drafted body, now needing four corrections — line count
  **7,516**, app-target figure **259 distinct ids**, a statement that both search surfaces share **two**
  pill components (Installed and UPDATE), and the offered-version fact. Then tick `6′.7`.

- **W2 — the latency scenario is not exercised by the spec's declared `unit` runner.** Both rows are
  `.enabled(if: isRelease)` and report **skipped** under `swift test`. Covered only by the release
  runner, which this session ran. Mirrors the shipped PS6 precedent
  (`CatalogTests/SearchLatencyTests.swift:35`).
  **Remediation**: at archive, record the release invocation beside the `unit` runner, or note the
  convention in `specs/README.md`. No code change.

- **W3 — the exact latency figures remain unreproducible.** Emitted only inside the `#expect` failure
  message. The binding clause — both turns under **8 ms** — is independently confirmed for the fourth
  round.

**SUGGESTION** (11):

- **S1 — a tautological assertion** at `TapPackageSearchTests.swift:1113`
  (`[...8 string literals].count == 8`). Read the shipped `TapShippingProofTests` enumeration instead.
- **S2 — `AppSection.tapSearch.title == "Search taps"` is unreachable**; DD-14 calls it "pinned by spec"
  and the spec pins nothing for `title`.
- **S3 — the zero-diff half of PS8 sc17 has no shipped enforcement.** Hand-verified five rounds running;
  a CI step (`git diff --quiet <base> -- cellar/Browse/BrowseView.swift`) would end the manual check.
- **S4 — correct the design's wiring table to ten sites.**
- **S5 — DD-17 still says "the four empty states" are pinned**; the spec pins two.
  `"Reading your taps"` (`TapSearchView.swift:213`) remains the only view-composed, unpinned sentence on
  this surface.
- **S6 — intermediate commits that do not build the app target** (`656e2d5`, `9714cfc`). Round 4 **fixed
  this pattern** by adding rather than renaming and by building at the projection commit; the suggestion
  now applies to rounds 2–3 history only, and the round-4 approach is the one to keep.
- **S7 — five branch-size figures now circulate** (5,754 / 5,889 / 6,340 / 6,891 / **7,516**). Quote only
  the final one.
- **S8 — rename drift in the artifacts, now two tests.** `design.md:271` still names
  `theBrowseTapSurfaceComposesNoTrustGateAndNoBadge` and `design.md:352` still names
  `aHitCarriesItsFiveFactsAndItsCopyAndNothingElse`; `tasks.md` carries both. Record both renames at
  archive.
- **S9 — round-3 deviation 3's "names no trust concept" is loose**: `StatusPill.swift` cites
  `package-trust` PT5 in a doc comment. The conclusion is unaffected.
- **S10 (new) — record the precise distinct-id counting rule.** An interleaved xcodebuild status block
  costs an id **only when it breaks inside the quoted id**; a break in the line's tail leaves the id
  extractable and already counted. Both apply's original method (undercount) and a naive
  count-the-mangled-lines correction (overcount) get this wrong. The three retained logs show one
  mangled line each and only **one** of them cost an id.
- **S11 (new) — the unidentified core-suite flake is now three rounds old and has never been captured.**
  Apply lost its identity by piping to `tail -2`. **Remedy**: redirect full output (`> log 2>&1`) on
  every core run, as round 4 already does for the app target, so the next occurrence names itself. It has
  not reproduced in any of my five runs across rounds 2–5.

---

### Verdict

**PASS WITH WARNINGS.** 0 blockers, 0 CRITICAL, 3 WARNING, 11 SUGGESTION, requirements **4/4**,
scenarios **37/37**.

The second half of the drift round 3 closed is now closed too, and closed the same honest way: not by
drawing a matching orange chip, but by having the tap row draw **the** update pill the catalog row and
the Installed list already draw. That cost `PackageRow.swift` and `StatusPill.swift` a zero-line diff
each, because `UpdateTag` was already the shape DD-18 had to build for the installed pill — and the test
claims exactly that, joining an existing component rather than pretending to have created symmetry it
does not have.

The offered version is a fact of the hit, read from a receipt the projection already holds, gated on the
receipt's own outdated rule, and — the detail that would have been easiest to get wrong — keyed off
`installedHandoff` rather than bare identity, so a receipt belonging to a different tap cannot hang an
UPDATE pill on a row this surface calls not installed. I proved all three of those with mutations rather
than reading them: **MF** removed the gate, **MG** re-keyed the lookup, **MI** handed the component the
wrong value, and each failed precisely one test and left the other twelve passing.

Two artefacts of good practice deserve recording. Apply narrowed a prohibition because reality changed
and simultaneously made its test *harder* to satisfy; and it rewrote the Outdated control's stated reason
once round 4 made the old one false, rather than leaving a false premise inside a requirement that
promotes into the main spec at archive. Both are the opposite of absorbing a deviation.

Every invariant holds, including `BrowseView.swift` byte-identical to `main` for the fifth round running.
The only genuinely new findings are documentation-grade: the precise rule for counting distinct test ids
(**S10**), and a three-round-old flake that keeps escaping identification because of how the run is piped
(**S11**). Neither blocks. **`m11-tap-search` is archive-ready.**
