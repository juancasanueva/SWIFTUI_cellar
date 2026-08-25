```yaml
schema: gentle-ai.verify-result/v1
evidence_revision: sha256:e1e7d366d1af34610a6515d9dac7b5e6a47d84e3aaf0d78623f546e2acb29334
verdict: pass_with_warnings
blockers: 0
critical_findings: 0
requirements: 4/4
scenarios: 42/42
test_command: xcodebuild test -project cellar.xcodeproj -scheme cellar -destination 'platform=macOS,arch=arm64' -only-testing:cellarTests
test_exit_code: 0
test_output_hash: sha256:d7b4f5bcc6b76bb232f708524b418a6b2c90d8edba7c1aba137c1dd42b142c09
build_command: xcodebuild build -project cellar.xcodeproj -scheme cellar -destination 'platform=macOS,arch=arm64'
build_exit_code: 0
build_output_hash: sha256:0978e7ccac0ddb7a3aa3304f1bd09ddacba6b117649c0d905c26f6fe1ed9ce6d
```

## Verification Report — round 7 (supersedes rounds 1–6)

**Change**: `m11-tap-search`
**Version**: spec deltas **r7** — PS8 ADDED (selectability reversed, inventory-fed detail), PD6
MODIFIED, TM5 + TM11 MODIFIED
**Mode**: Strict TDD, coverage threshold 0
**Branch**: `feat/m11-tap-search` @ `8aeb774`, **38 commits** off `main` @ `edda9a5`, tree clean before
this run and carrying only this rewritten report after it
**Artifact store**: hybrid — this file is canonical; Engram topic `sdd/m11-tap-search/verify-report`
mirrors it. RDD disabled.
**Delivery**: `single-pr` with a maintainer-accepted `size:exception` (2026-08-25). The branch measures
**9,324** changed lines — recorded, **not** a finding.
**Independence**: fresh context. All four runners re-executed at `8aeb774`; four reversible mutations of
my own, none of them apply's.

---

### History (superseded)

| Round | Commit | Verdict | Substance |
|---|---|---|---|
| 1–2 | `36f1b8d` | **fail** (34/35) | Own sidebar surface; PS8 sc15's trust scan missed the projection. |
| 3 | `f98d9fa` | pass_with_warnings | Trust scan fixed. |
| 4 | `9894a6a` | pass_with_warnings | Shared **Installed** pill. |
| 5 | `c760d28` | pass_with_warnings (37/37) | Shared **UPDATE** pill; offered version as a fact. |
| 6 | `3cc53a4` | pass_with_warnings (38/38) | Installed rows reach the shared mutation menu with their record. |

---

### What round 6 of apply changed, and whether it is right

A maintainer **product decision** reverses the 2026-08-24 rule that a not-installed hit is
non-selectable. Such a hit is now selectable when its identity is unambiguous, and opens a **minimal,
inventory-fed detail**. This is the largest round so far: it is the first to touch
`PackageDetailView.swift`, which had been a zero-diff invariant for five rounds.

**The reversal is properly argued rather than merely asserted.** Round 1 withheld the route because
"there is nothing honest to present" — and the spec now observes that this was a claim about a *catalog*
pane and a *tap-source* read, both of which remain forbidden. What round 6 establishes is that the four
names the resident inventory has **already published** are honest to present, on exactly the terms PD6
and TM5 already grant the receipt-backed pane. Ambiguity is untouched.

| Obligation (PS8 r7) | Delivered | Verified |
|---|---|---|
| Routable **iff unambiguous**, in either install state | `routableID` = `collides == false && unique` | ✅ **MM** |
| Resolve only when **exactly one** tap publishes | `guard publishers.count == 1` | ✅ **MO** |
| Zero or several ⇒ fall through, never guess | falls to the shipped `ContentUnavailableView` | ✅ |
| An identity with a **receipt** resolves to nothing here | `guard installed.package(id) == nil` — keyed on the **receipt**, so the withheld-tap case still reaches its receipt pane | ✅ |
| Pane presents exactly identity, kind, tap, install state, menu, footer | `Type` / `Tap` / `Install state` + footer | ✅ **MN** |
| **No** collision note, asserted not assumed | absent; unreachable by construction | ✅ |
| No description, version, homepage, licence, deps, analytics, size | case-insensitive scan over 15 tokens | ✅ **MN** |
| No trust badge, control, copy; no PD8 grant marker | six trust tokens absent | ✅ |
| Both strings projection-owned, absent from **all** app sources | `stateCopy` + `footerCopy` on `TapInventoryDetail` | ✅ |
| Third branch, **after** catalog and receipt | range-ordered assertion on all three | ✅ |
| `taps:` passed at the **single** construction site | asserted, with a uniqueness check on the call | ✅ |

**The projection's three refusals are all refusals, never guesses**, and the receipt check is the subtle
one: it is keyed on the *receipt* rather than on the tap projection's install state, because Homebrew
withholds the tap of an untrusted package — the record's `tap` is absent but the record exists and
decides. That is what makes `stateCopy` honest by construction: no value carrying "Not installed." can
describe a package this Mac has.

**`kind` is computed off `id`** — and the design explains why DD-19's "stored, not computed" reasoning
does not apply: that reasoning is about facts `Mirror` would otherwise miss, and `id` is itself
enumerated and carries the kind. Storing a second copy would give one fact two homes.

---

### The zero-diff invariant that moved, and whether it was allowed to

`PackageDetailView.swift` carried a zero-line diff in rounds 2–6 and is now **+37/−8**. I read the whole
diff. It contains exactly three things:

1. `let taps: TapStore` — one parameter.
2. A **third** `else if` branch calling `TapInventoryDetail.resolve(…)` → `tapInventoryContent(for:)`.
3. `header(versionStory:)` widened `String` → `String?`, so the version line **and its separator dot**
   are omitted rather than emptied — a genuine ripple, since the shared header now serves a caller with
   no version, and a dangling separator is exactly the placeholder PD1 keeps off this pane.

Plus the preview's new argument. Nothing else moved.

**PS8's "no routing branch added for this source" clause survives literally**, and not by luck: the
scenario binds the **installed** hit's route, the new branch sits **third**, and the spec requires that
ordering explicitly so an installed package always reaches its receipt pane first. The unit-app test
pins the order by range comparison rather than trusting the prose.

**The guard that forbade `TapInventory` in that file was narrowed, and the narrowing is compensated.**
`theTapSurfaceResolvesThroughTheSharedDetail` still forbids all three tap-*search* tokens
(`TapSearchHit`, `TapPackageSearch`, `TapSearchView`) — the claim "the shared detail knows nothing about
the tap search surface" is unchanged. What replaced the blanket `TapInventory` ban is **stronger than a
ban would have been if simply dropped**: the file must contain `TapInventoryDetail.resolve(` and must
name `TapInventory` **exactly once**. A ban is unsatisfiable once the spec requires the branch; "exactly
once" is the strongest satisfiable form. I did not take that on trust — **MP** added a second
`TapInventory` reference and the test failed, so the narrowing provably cannot widen.

---

### Non-vacuity — four reversible mutations, none of them apply's

Each applied, run, restored with `shasum -a 256` matching the pre-mutation digest;
`git status --porcelain` printed nothing after each. All app-target runs used **suite-level** filters.

| # | Mutation | Expected | Observed |
|---|---|---|---|
| **MM** | `routableID` = `true` — make ambiguous hits routable | ambiguity must withhold the route | ❌ **4** tests, 6 issues — including the amended "whatever its install state" row on both the colliding-installed and colliding-not-installed cases |
| **MO** | `publishers.count >= 1` — resolve when several taps publish | several must resolve to nothing | ❌ `An unpublished or doubly published identity resolves to nothing` — the mutant picked `acme/tools` arbitrarily, which is precisely the guessed tap the spec forbids |
| **MN** | add `fact("License", "MIT")` to the pane | a field the inventory cannot know must be rejected | ❌ `theNameOnlyTapDetailComposesNothingItCannotKnow` only; the other 14 passed |
| **MP** | add a second `TapInventory` reference to `PackageDetailView` | the narrowed guard must not widen | ❌ `theTapSurfaceResolvesThroughTheSharedDetail` only; the other 14 passed |

**MO's output is the most telling**: the mutant returned a fully-formed detail naming `acme/tools` for an
identity two taps publish. **MP** is the one that matters for governance, because it tests the
compensating control on the only guard this round relaxed.

---

### Completeness

| Metric | Value |
|--------|-------|
| Task checkboxes total | 212 |
| Complete | **210** |
| Incomplete | **2** — `6.7` (round 1, **VOID**) and `6′.7` (open the PR) |

Round 6 declares **25 of 25**, but the ledger grew from 178 to 210 (**+32**). The seven-box difference
is not explained in the record; it is immaterial to correctness — every box is ticked and the two open
ones are the known pair — but it is a recording gap (**S11**).

---

### Build & Tests Execution — all four runners re-executed at `8aeb774`

**Build**: ✅ `** BUILD SUCCEEDED **`, exit 0.

| # | Runner | Exact result | Exit | Output sha256 |
|---|---|---|---|---|
| 1 | `xcodebuild test … -only-testing:cellarTests` | **`** TEST SUCCEEDED **`** — **261 distinct test ids** (see below), 0 failed | 0 | `d7b4f5bc…2c09` |
| 2 | `swift test --package-path Packages/CellarCore` | **1,878 tests / 218 suites passed, 1 known issue** (was 1,873/217; **+5 tests, +1 suite**) | 0 | `dba518b6…c472` |
| 3 | `xcodebuild build … -scheme cellar` | **`** BUILD SUCCEEDED **`** | 0 | `0978e7cc…ce6d` |
| 4 | `swift test -c release … --filter 'TapPackageSearchTests'` | **35 tests / 1 suite passed**, both latency rows passed | 0 | `1c537953…c737` |

The core `+5` and `+1 suite` are the new `TapInventoryDetailTests` (5 rows). Latency:
`theCatalogKeystrokeTurnIsUnchanged` 1.525 s, `theTapSurfaceKeystrokeTurnStaysUnderTheCeiling` 2.084 s —
**sixth** consecutive round under the 8 ms ceiling.

#### The 259/260 question — reconciled, and my own rule corrected

Apply's deviation 6 reports a `cellarTests` baseline of **259** at `cbd13cb` where round 5 recorded
**260**, by the same command, and declines to reconcile it. It reconciles cleanly, and the reconciliation
also **corrects the rule I stated in rounds 5 and 6**.

`git diff --name-only 3cc53a4..cbd13cb` touches only the verify report, so the baseline at `cbd13cb` is
the count at `3cc53a4`, which I measured as **260**. Apply's 259 is one low by the interleaving mechanism
apply itself discovered in round 4.

But this round's own log exposed a case my rule did not cover. I stated that an interleaved status block
costs an id **only when it breaks inside the quoted identifier**. The r7 log's mangled line is:

```
Test case 'BrewfileCompositionTests/aFileThatIsOnlySkipsIsStillAValidImport()' passe2026-08-25 14:00:48.229 xcodebuild[…]
```

The break lands **after** the closing quote but **inside the word `passed`**. The identifier is intact
and recoverable — so my round-5/6 rule says "no adjustment" — yet the counting pattern
`Test case '([^']+)' (passed|failed)` still fails to match, and the id is silently dropped. My first
count this round read 260 and was one low for exactly that reason.

**The correct rule is membership, not break position**: recover the id from every mangled line and add
one only when that id is absent from the cleanly-parsed set. Re-running all five retained logs under it:

| Log | Clean | Dropped | **True** |
|---|---|---|---|
| r3 `f98d9fa` | 257 | 0 | **257** |
| r4 `9894a6a` | 258 | 0 | **258** |
| r5 `c760d28` | 258 | 1 (break inside the id) | **259** |
| r6 `3cc53a4` | 260 | 0 (break in the tail) | **260** |
| r7 `8aeb774` | 260 | 1 (**break inside `passed`**) | **261** |

Progression **257 → 258 → 259 → 260 → 261**, exactly one unit-app test per round, no gaps. Round 7's id
delta confirms it independently: two ids added (`theNameOnlyTapDetailComposesNothingItCannotKnow`, new;
`theTapSearchSurfaceSelectsOnRoutabilityAlone`, the rename of `notInstalledTapRowsAreNotSelectable`) and
two removed (that old name, and the dropped `aFileThatIsOnlySkipsIsStillAValidImport` — which is not a
deletion but the corruption artefact).

So **apply is one low at both points**: the true baseline is 260 and the true count at `8aeb774` is
**261**, not 260. Recorded as **W4**, with the corrected rule as **S10**.

---

### Spec Compliance Matrix

**42 scenarios across 4 requirement blocks**, re-counted this session (`rg -c '^### Requirement:'` → **4**,
`rg -c '^#### Scenario:'` → **42**): PS8 **22** (+2), PD6 **5** (+1), TM5 **12** (+1), TM11 3.
`specs/README.md` now reads **27 new (19 `unit`, 8 `unit-app`)**, which I re-derived independently:
PS8 22 + PD6 2 + TM5 2 + TM11 1 = 27, and the class split matches.

#### The scenarios r7 added or amended

| Scenario | Requires | Test | Result |
|---|---|---|---|
| **ambiguity** (amended) | non-routable in **either** install state; and an unambiguous hit of **each** state reports its exact `PackageID`, so the rule is identity's alone | `TapPackageSearchTests > anAmbiguousHitIsNotRoutableWhateverItsInstallState` (`:807-864`) | ✅ COMPLIANT — non-vacuous by **MM** |
| **one publisher** (new, `unit`) | one ⇒ four names + two exact strings and nothing else; zero and several ⇒ nothing; a receipt-holding identity ⇒ nothing, incl. withheld-tap | `TapInventoryDetailTests` — 5 rows: one-tap formula, one-tap cask, unpublished/doubly-published, receipt-holding, and no-catalog-value/no-tap-source | ✅ COMPLIANT — non-vacuous by **MO** |
| **pane composition** (new, `unit-app`) | no forbidden field, no collision note, no trust presentation, no local verbs; both sentences projection-owned and absent from app sources; **third** branch order; `taps:` at the single site | `TapSearchCompositionTests > theNameOnlyTapDetailComposesNothingItCannotKnow` | ✅ COMPLIANT — non-vacuous by **MN** |
| **selection rule** (amended) | selectable on the projection's routability alone — ambiguous inert, unambiguous not-installed **not** inert | `> theTapSearchSurfaceSelectsOnRoutabilityAlone` (renamed) | ✅ COMPLIANT |
| **shared detail** (narrowed) | detail grows no arm for the tap **search** surface; one permitted inventory reference | `> theTapSurfaceResolvesThroughTheSharedDetail` | ✅ COMPLIANT — non-vacuous by **MP** |
| PD6 + TM5 (+1 each) | inventory-fed *rendering* on the same four negations; TM5's tap-source ban **reaffirmed** | shipped delta scenarios, green | ✅ COMPLIANT |

The pane's field scan is **case-insensitive** by design, with the reason recorded in the test: a fact has
two spellings here — the member `homepage` and a rendered label `"Homepage"` — and a case-sensitive scan
would catch the first while a hand-written label walked past it. That is deviation 2, and it was found by
a mutation rather than by review.

The copy claim is scoped correctly: `Not installed.` was *withdrawn from the row* in round 3 and is
*required on the pane* in round 6. The two scans are over different source sets — the row's withdrawal
over projection+surface, the pane's ownership over the app target only — so both hold simultaneously,
and the test says why.

**Compliance summary**: **42/42 compliant, 0 partial, 0 untested, 0 failing.**

---

### Invariants — re-run at `8aeb774`

| Path | Result |
|---|---|
| `cellar/Browse/BrowseView.swift` | ✅ **byte-identical to `main`** — seventh round running |
| `cellar/Activity/MutationMenu.swift` | ✅ ZERO-DIFF |
| `Packages/CellarCore/Sources/BrewClient/TapProjection.swift` | ✅ ZERO-DIFF — `TapProjection.publishes(_:in:)` at `:219` is a **shipped** API, not new |
| `cellar.xcodeproj/project.pbxproj` | ✅ ZERO-DIFF — two new files, still no edit |
| `openspec/specs/**` · `cellarUITests/**` | ✅ ZERO-DIFF |
| `PackageSearchIndex.swift` · `MutationCommand.swift` · `TapCommand.swift` | ✅ ZERO-DIFF |
| `cellar/Browse/PackageDetailView.swift` | **+37/−8**, limited to the parameter, the third branch and the optional `versionStory` — reviewed line by line above |

Apply records the detail diff as `+37/−9`; `git diff --numstat` reports `37 8`. A one-line
discrepancy in the record only (**S12**).

---

### Coherence — DD-21, DD-22

| # | Decision | Followed? |
|---|---|---|
| **DD-21** | third branch on the shared detail, resolved from the resident inventory, no acquisition | ✅ order asserted; nothing awaited or refreshed |
| **DD-22** | both sentences projection-owned; optional `versionStory` so an absent story takes its separator with it | ✅ both asserted; the header change is the minimum that serves a version-less caller |

---

### TDD Compliance

| Check | Result | Details |
|---|---|---|
| TDD Evidence reported | ✅ | Round-6 cycle table |
| RED confirmed | ✅ | New projection by compile failure; pane and guards by reversible mutation |
| GREEN confirmed | ✅ | 261 distinct cellarTests + 1,878 core + 35 release, all green this session |
| Triangulation adequate | ✅ | Resolution across one/zero/several publishers **plus** the receipt-holding and withheld-tap cases — distinct failure modes, not variations |
| Safety net | ✅ | 260 → 261 distinct (+1 net, one rename in/out); 1,873 → 1,878 (+5, one new suite) |
| Filter discipline | ✅ | Suite-level throughout; deviation 5 records the function-level trap catching apply again and being disbelieved |
| Mutations restored | ✅ | Apply's and my own four, all SHA-verified |

**TDD Compliance**: 7/7 checks passed.

### Test Layer Distribution

| Layer | Tests | Files | Tools |
|---|---|---|---|
| Unit (`unit`) | 35 `TapPackageSearchTests` + **5** `TapInventoryDetailTests` | 2 + 3 fixtures | Swift Testing |
| Unit-app (`unit-app`) | **15** in `TapSearchCompositionTests` (was 14) | 8 | Swift Testing + `#filePath` source scan |
| Integration / E2E | 0 | 0 | `cellarUITests` zero-diff |

### Assertion Quality

| File | Line | Assertion | Issue | Severity |
|---|---|---|---|---|
| `TapPackageSearchTests.swift` | ~1265 | `#expect([...8 string literals].count == 8)` | Tautology over a literal | SUGGESTION (**S1**) |

Round 6's new assertions are sound: the pane scan is anchored positively before every absence, the copy
absence is paired with a projection-presence check so deleting the copy would not pass, the branch order
is a range comparison, and the construction site is uniqueness-checked. One cosmetic nit: the renamed
`theTapSurfaceResolvesThroughTheSharedDetail` declaration is indented eight spaces instead of four
(**S13**).

**Assertion quality**: 0 CRITICAL, 0 WARNING, 1 SUGGESTION.

---

### Round-6 deviations, judged (seven recorded, not six)

| # | Deviation | Judgment |
|---|---|---|
| 1 | **`kind` computed, not stored; collision note not rendered** | **ACCEPT, both.** The `kind` reasoning correctly distinguishes itself from DD-19: that rule is about facts `Mirror` would miss, and `id` already carries the kind. The collision-note removal is the stronger call — it is applicable **never**, because a colliding token is carried by the catalog and resolves at branch one, so rendering it would be unreachable presentation. Asserting the absence is right. |
| 2 | **The first field scan was case-sensitive and a mutation walked past it** | **ACCEPT — the process working.** `fact("Homepage", …)` is not caught by a scan for `homepage`. Found by mutation, fixed by lowercasing both sides, re-run failed as it should. I re-proved the fixed scan independently with **MN** using a *different* field (`License`). |
| 3 | **`PackageMetadataSection` written into the pane, then removed** | **ACCEPT.** Mirroring the receipt pane by reflex, then recognising that PS8 **enumerates** what the pane presents and closes the list. Removed before commit with the reason recorded in the file. The favourite heart is correctly identified as arriving via the shared header the pane is required to reuse — an honest disclosure of a thing the enumeration does not name. |
| 4 | **The `TapInventory` guard was narrowed** | **ACCEPT**, and independently discharged. The three tap-search tokens stay banned; the one permitted reference is pinned positively and count-limited. **MP** proves it cannot widen. This is the round's one relaxed guard and it is the best-compensated. |
| 5 | **A function-level `-only-testing:` filter ran zero tests and reported success** | **ACCEPT.** The trap apply discovered in round 4 caught it again — and was disbelieved rather than trusted, which is the whole value of having recorded it. |
| 6 | **The `cellarTests` baseline measured 259 where round 5 recorded 260**, not reconciled | **ACCEPT the report, REJECT the non-reconciliation** — see **W4**. It is the round-4 interleaving again; the true baseline is 260 and the true count at `8aeb774` is **261**. Apply was right not to reconcile it away silently; it is now reconciled with evidence. |
| 7 | **Suite-level filters throughout** | **ACCEPT.** |

**Six accepted; one accepted as a report but its open question now answered.**

---

### Commit hygiene and branch size

- **38 commits**, all Conventional Commits, **no AI attribution**.
- Round 6's six are correctly ordered: two `docs(sdd)` amendments (the second a self-correction of the
  pane contract **before** any code), then `feat(search)` projection, `feat(browse)` app, `test(browse)`,
  `docs(sdd)` record. Correcting the contract before writing against it is the right order.
- `git diff --shortstat main...HEAD` → **30 files, +9,260/−64 = 9,324 authored lines**. Apply reports
  **9,256** measured before its own record commit. Under the accepted `size:exception`.
- Working tree clean at start; only this report modified at the end.

---

### Issues Found

**CRITICAL**: None.

**RESOLVED since round 6**: **W4 (round 6)** — the Engram `tasks` mirror is refreshed and now reads
"ROUND 6" against a canonical file of 1,309 lines, matching `tasks.md`. The hybrid contract is satisfied.

**WARNING** (4):

- **W1 — one task is open: `6′.7`, "Delivery — one PR".** Deferred again by instruction.
  **Remediation**: open the PR with the drafted body, now needing six corrections — line count
  **9,324**, app-target figure **261 distinct ids**, the two shared pill components, the offered-version
  fact, installed rows reaching the menu with their record, and the name-only detail. Then tick `6′.7`.

- **W2 — the latency scenario is not exercised by the spec's declared `unit` runner.** Both rows are
  `.enabled(if: isRelease)` and report **skipped** under `swift test`; covered only by the release
  runner, which this session ran. Mirrors the shipped PS6 precedent.

- **W3 — the exact latency figures remain unreproducible**, emitted only inside the `#expect` failure
  message. The binding clause — both turns under **8 ms** — is confirmed for the sixth round.

- **W4 (new) — apply's two `cellarTests` figures for round 6 are each one low.** The baseline is **260**,
  not 259 (`cbd13cb` is docs-only after `3cc53a4`, which I measured at 260), and the count at `8aeb774`
  is **261**, not 260. Both are the round-4 interleaving. Deviation 6 correctly declines to reconcile
  without evidence; the evidence is now in this report.
  **Remediation**: amend deviation 6 and the 6-series figures to 260 → 261, citing the membership rule in
  **S10**. No code change.

**SUGGESTION** (13):

- **S1 — a tautological assertion** in `TapPackageSearchTests.swift` (`[...8 string literals].count == 8`).
- **S2 — `AppSection.tapSearch.title == "Search taps"` is unreachable**; DD-14 wrongly calls it spec-pinned.
- **S3 — the zero-diff half of PS8 sc17 has no shipped enforcement.** Hand-verified **seven** rounds; a CI
  step would end the manual check.
- **S4 — correct the design's wiring table to ten sites.**
- **S5 — DD-17 still says "the four empty states" are pinned**; the spec pins two.
  `"Reading your taps"` (`TapSearchView.swift:229`) remains the only view-composed unpinned sentence.
- **S6 — non-building intermediate commits** in rounds 2–3 only; rounds 4–6 fixed the pattern.
- **S7 — seven branch-size figures now circulate.** The recurring cause is that apply measures before
  committing its own record. State the convention once at archive and quote only the final figure.
- **S8 — rename drift in the artifacts, now three tests**: `theBrowseTapSurfaceComposesNoTrustGate…`,
  `aHitCarriesItsFiveFacts…` and now `notInstalledTapRowsAreNotSelectable` all appear under pre-rename
  names in `design.md` and `tasks.md`.
- **S9 — round-3 deviation 3's "names no trust concept" is loose.**
- **S10 — the distinct-id rule needs correcting to membership.** An interleaved block costs an id
  whenever the counting pattern fails to match — which includes a break inside the trailing
  `passed`/`failed` keyword, not only inside the quoted identifier. Recover the id from each mangled line
  and add one only when it is absent from the clean set. Record this at archive; it has now bitten three
  different measurements.
- **S11 (new) — the round-6 ledger arithmetic does not foot.** The record declares 25 of 25 while the
  checkbox total grew from 178 to 210 (+32). Every box is ticked, so nothing is incomplete, but the
  seven-box difference is unexplained.
- **S12 (new) — the recorded detail-view diff is `+37/−9`; `git diff --numstat` says `37 8`.**
- **S13 (new) — cosmetic**: the renamed `theTapSurfaceResolvesThroughTheSharedDetail` declaration is
  indented eight spaces instead of four.

---

### Verdict

**PASS WITH WARNINGS.** 0 blockers, 0 CRITICAL, 4 WARNING, 13 SUGGESTION, requirements **4/4**,
scenarios **42/42**.

This round reverses a product decision and moves a file that had been invariant for five rounds, which is
exactly the shape of change that usually erodes a contract quietly. It does not. The reversal is argued
from what the earlier prohibition actually said — a claim about a *catalog* pane and a *tap-source* read,
both still forbidden — rather than waved through; the tap-source ban is **reaffirmed** in TM5 rather than
weakened; ambiguity still withholds the route in both install states; and the pane is an enumerated list
that the implementer twice trimmed back to, once by deleting a section added by reflex and once by
refusing to render a collision note that could never be reached.

The `PackageDetailView.swift` diff is three things and nothing else, and the clause it might have
violated survives literally because the new branch sits third — a position the spec requires and the test
pins by range comparison rather than by prose. The one guard that had to be relaxed was replaced by a
strictly stronger positive pin, and **MP** proves that pin holds.

My four mutations each failed precisely the intended target: **MM** made ambiguous hits routable and
tripped four rows; **MO** let a doubly-published identity resolve and produced a pane naming an
arbitrarily-chosen tap; **MN** rendered a licence the inventory cannot know; **MP** widened the narrowed
guard.

One correction is mine again, and it is the same one twice removed. Apply's unreconciled 259-vs-260
question is the round-4 interleaving — but resolving it exposed that the rule I published in rounds 5 and
6 was itself incomplete: a break inside the word `passed` drops an id just as a break inside the
identifier does, and my own first count this round was one low because of it. The correct test is
membership, not break position. Under it the five retained logs give **257 → 258 → 259 → 260 → 261** with
no gaps, apply's two round-6 figures are each one low, and the honest count at `8aeb774` is **261**.

**`m11-tap-search` is archive-ready.**
