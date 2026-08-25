```yaml
schema: gentle-ai.verify-result/v1
evidence_revision: sha256:d5da6bec9671b69f28395a3436e143d3f420c8f8fdf6baefb7db66c33741c8ad
verdict: fail
blockers: 0
critical_findings: 0
requirements: 4/4
scenarios: 42/43
test_command: xcodebuild test -project cellar.xcodeproj -scheme cellar -destination 'platform=macOS,arch=arm64' -only-testing:cellarTests
test_exit_code: 0
test_output_hash: sha256:ec16ac110c054c2391955a9ef3d8dbd238b4a7423b71be735e27a342970173f3
build_command: xcodebuild build -project cellar.xcodeproj -scheme cellar -destination 'platform=macOS,arch=arm64'
build_exit_code: 0
build_output_hash: sha256:7e429715b3f72b63dd674404f3c810cc21b6fe66b02f8c9069b0b3d47bd7f2de
```

## Verification Report — round 8 (supersedes rounds 1–7)

**Change**: `m11-tap-search`
**Version**: spec deltas **r8** — PS8 ADDED (routable iff `PackageID` unique among emitted hits), PD6
MODIFIED (+1 clause, +1 scenario), TM5 + TM11 MODIFIED
**Mode**: Strict TDD, coverage threshold 0
**Branch**: `feat/m11-tap-search` @ `21956b0`, **43 commits** off `main` @ `edda9a5`, tree clean before
this run and carrying only this rewritten report after it
**Artifact store**: hybrid — this file is canonical; Engram topic `sdd/m11-tap-search/verify-report`
mirrors it. RDD disabled.
**Delivery**: `single-pr` with a maintainer-accepted `size:exception`. The branch measures **9,940**
changed lines — recorded, **not** a finding.
**Independence**: fresh context. All runners re-executed at `21956b0`; five reversible mutations of my
own, one of which found a gap.

---

### History (superseded)

| Round | Verdict | Substance |
|---|---|---|
| 2 `36f1b8d` | **fail** (34/35) | PS8 sc15's trust scan missed the projection. |
| 3 `f98d9fa` | pass_with_warnings | Trust scan fixed. |
| 4 `9894a6a` | pass_with_warnings | Shared **Installed** pill. |
| 5 `c760d28` | pass_with_warnings (37/37) | Shared **UPDATE** pill. |
| 6 `3cc53a4` | pass_with_warnings (38/38) | Mutation handoff to the shared menu. |
| 7 `8aeb774` | pass_with_warnings (42/42) | Not-installed hits selectable; name-only inventory-fed pane. |

---

### What round 7 of apply changed, and whether it is right

A maintainer product decision reverses the **collision** half of round 6's ambiguity rule. A hit whose
bare token the catalog also carries is now selectable and opens the **catalog's own detail**.

**The argument is correct, and it is the best-reasoned reversal in this change.** Round 1 withheld the
route because catalog-first resolution "would present a different package than the row chosen" — and the
spec now observes that this measured the destination against the wrong thing. The row's own pinned
collision note already says, in those words, that *Homebrew installs the catalog package*. So the catalog
pane is not a different package: it is precisely the one the row promises. Withholding it left the user
with a sentence naming a package and no way to look at it.

| Obligation (PS8 r8) | Delivered | Verified |
|---|---|---|
| Routable **iff** `PackageID` unique among emitted hits | `let routable = unique` | ✅ **MQ**, **MR** |
| Uniqueness counted over **emitted hits alone** | `occurrences` built from `matches`; a catalog record is never counted | ✅ **MQ** |
| Collision note **unchanged and still required** | `alsoInCatalog` / `collisionNote` untouched | ✅ |
| Colliding hit routable, resolves catalog-first | `routableID` = bare `PackageID`; branch 1 answers | ✅ |
| **No routing branch added** | `PackageDetailView.swift` **unchanged this round** | ✅ |
| Duplicate `PackageID` is the sole inert case | both such hits report `nil` | ✅ **MR** |
| PD6: the record returned is the catalog's own | new `unit` scenario asserts byte-identity against a no-tap-inventory lookup | ✅ |

**The change is a deleted conjunct and nothing else.** `collides == false &&` is gone from one
expression; `alsoInCatalog`, `collisionNote`, the receipt branch and the inventory branch are all
untouched. `TapSearchView.swift` was edited **comment-only** — no behaviour line moved — because the view
already gated on `hit.routableID` alone. That is the dividend of the earlier discipline: the projection
changed its mind and the surface needed no edit.

**PD6 adds a clarification, not a permission.** The new scenario proves the record a colliding selection
returns is **byte-identical to the record the same lookup returns with no tap inventory resident** —
the strongest available form of "the tap contributed nothing".

**The pane's absent collision note now rests on branch ordering alone**, and apply spotted that itself
(deviation 4): the paragraph previously gave two reasons and one of them is now false. The ordering is
asserted in `theNameOnlyTapDetailComposesNothingItCannotKnow`, so the single remaining guarantee is a
tested one.

---

### Non-vacuity — five reversible mutations, all restored SHA-verified, tree clean

| # | Mutation | Expected | Observed |
|---|---|---|---|
| **MQ** | restore `collides == false && unique` | the retired rule must not come back | ❌ **4** tests — incl. `A colliding hit is shown and is routable` and the new PD6 scenario |
| **MR** | `let routable = true` | uniqueness must still bar duplicates | ❌ exactly the **2** duplicate-identity rows |
| **MT** | view gates on `hit.alsoInCatalog == false` | the view must not re-derive the collision | ❌ `theTapSearchSurfaceSelectsOnRoutabilityAlone` only |
| **MS** | view gates on `hit.isInstalled` (**comma form**) | the view must not re-derive the install state | ⚠️ **`** TEST SUCCEEDED **` — nothing failed** |

**MQ and MR pin the rule from both sides**, which is the ideal shape: it cannot drift back to the retired
rule and cannot lose the guard that remains. **MT** independently re-proves apply's own app-source
mutation.

**MS is the finding.** See **W1**.

---

### The gap MS found

PS8's amended `unit-app` scenario requires: *"the surface consults neither the collision fact **nor the
install state** to decide selection, so the one rule stays the projection's."*

The collision half is enforced — `alsoInCatalog` is in the forbidden-token list, and **MT** trips it. The
**install-state half is not enforced in a reachable spelling.** `hit.isInstalled` cannot be blanket-banned
because the row legitimately reads it to draw the shared Installed pill, so the only guard is:

```swift
#expect(
    surface.code.contains(".selectionDisabled()")
        && surface.code.contains("hit.isInstalled ? ") == false, …
)
```

which catches the **ternary** spelling only. I changed the gate to the comma form:

```swift
if let routable = hit.routableID, hit.isInstalled {
```

This makes every unambiguous **not-installed** hit inert — silently reverting round 6's product decision
and disabling the name-only pane's only route — and **all 15 tests in the suite passed**.

The scenario has covering tests that pass, so this is **PARTIAL**, not UNTESTED: `scenarios: 42/43`.

**Remediation is one token.** The suite already asserts the gate's presence at `:261` and `:295`:

```swift
#expect(surface.code.contains("if let routable = hit.routableID"))
```

Append the opening brace so the binding must be the **whole** condition:

```swift
#expect(surface.code.contains("if let routable = hit.routableID {"))
```

I verified both directions: the shipped source contains that exact string (once), and under **MS** it does
not. No production line changes.

---

### Completeness

| Metric | Value |
|--------|-------|
| Task checkboxes total | 236 |
| Complete | **234** |
| Incomplete | **2** — `6.7` (round 1, **VOID**) and `6′.7` (open the PR) |

Round 7 declares 24 of 24 and adds no delivery task.

---

### Build & Tests Execution — re-executed at `21956b0`

**Build**: ✅ `** BUILD SUCCEEDED **`, exit 0.

| Runner | Exact result | Exit | Output sha256 |
|---|---|---|---|
| `xcodebuild test … -only-testing:cellarTests` (run 1) | `** TEST SUCCEEDED **` — **261 distinct ids**, 0 failed | 0 | `ec16ac11…73f3` |
| `xcodebuild test … -only-testing:cellarTests` (run 2) | `** TEST SUCCEEDED **` — **261 distinct ids**, 0 failed | 0 | `06c2c7f4…09df` |
| `swift test --package-path Packages/CellarCore` | **1,879 tests / 218 suites passed, 1 known issue** (+1) | 0 | `a8ff39e4…bb84` |
| `xcodebuild build … -scheme cellar` | `** BUILD SUCCEEDED **` | 0 | `7e429715…f2de` |
| `swift test -c release … --filter 'TapPackageSearchTests'` | **36 tests / 1 suite passed** (+1), latency rows green | 0 | `dbc16ae1…3006` |

Latency holds under the 8 ms ceiling for the **seventh** consecutive round.

#### Distinct ids — three independent confirmations of 261

Apply reports that two runs each lost a different id and that the sets union to 261. I reproduced the
phenomenon exactly, with two runs of my own:

| Method | Result |
|---|---|
| Run 1, membership rule | clean 260 + 1 dropped = **261** |
| Run 2, membership rule | clean 260 + 1 dropped = **261** |
| Union of the two clean sets | **261** |

The dropped ids differ per run — `skipsAreGroupedCountedAndNamed()` in run 1,
`aTrustedClaimIsSurfacedAndAttributed()` in run 2 — which is why the union works: the interleaving is
non-deterministic, so two runs almost never corrupt the same line. Apply's union technique and my
membership rule agree, and each cross-checks the other.

Against round 7's clean set the only apparent addition is
`BrewfileCompositionTests/aFileThatIsOnlySkipsIsStillAValidImport()`, which is the id round 7's log
dropped — not a new test. So the count is **unchanged at 261**, exactly as expected: round 7 amended its
scenarios **in place** and added no `unit-app` id. Progression: **257 → 258 → 259 → 260 → 261 → 261**.

---

### Spec Compliance Matrix

**43 scenarios across 4 requirement blocks** (`rg -c '^### Requirement:'` → **4**,
`rg -c '^#### Scenario:'` → **43**): PS8 **22** (unchanged — amended in place), PD6 **6** (+1), TM5 12,
TM11 3.

| Scenario | Test | Result |
|---|---|---|
| **collision reported, never suppressed, never withholds the route** (amended) | `TapPackageSearchTests > A colliding hit is shown and is routable` — note present **and** `routableID == mutationTarget` | ✅ COMPLIANT — **MQ** |
| **only a duplicated identity withholds the route** (amended `unit`) | `> Only a duplicated identity withholds the route` — duplicates inert; both colliding hits routable in either install state; note still carried; uncollided hits routable | ✅ COMPLIANT — **MQ**, **MR** |
| **PD6: a colliding selection resolves to the catalog's own record** (new `unit`) | byte-identity against a no-tap-inventory lookup, plus record count, search results and absence checks | ✅ COMPLIANT — **MQ** |
| **only its duplicated rows are inert** (amended `unit-app`) | `> theTapSearchSurfaceSelectsOnRoutabilityAlone` + the branch-order assertion | ⚠️ **PARTIAL** — **W1** |
| installed hit opens the receipt-backed detail (amended GIVEN) | unchanged, green | ✅ COMPLIANT |
| The other 38 | unchanged and green | ✅ COMPLIANT |

**Compliance summary**: **42/43 compliant, 1 partial, 0 untested, 0 failing.**

---

### Invariants — re-run at `21956b0`

| Path | Result |
|---|---|
| `cellar/Browse/BrowseView.swift` | ✅ **byte-identical to `main`** — eighth round running |
| `cellar/Browse/PackageDetailView.swift` | ✅ **unchanged this round** (`6f18d2d..HEAD` empty) — the "no new branch" claim, proven by absence |
| `cellar/Activity/MutationMenu.swift` · `project.pbxproj` · `openspec/specs/**` · `cellarUITests/**` | ✅ ZERO-DIFF |
| `TapProjection.swift` · `PackageSearchIndex.swift` · `MutationCommand.swift` · `TapCommand.swift` | ✅ ZERO-DIFF |

The catalog-first branch order is still pinned by
`theNameOnlyTapDetailComposesNothingItCannotKnow`'s range comparison — load-bearing this round, since it
is now the pane's sole guarantee.

---

### Round-7 deviations, judged

| # | Deviation | Judgment |
|---|---|---|
| 1 | **The design's mutation-honesty note was wrong and was corrected**: a CellarCore mutation cannot prove a `cellarTests` source scan | **ACCEPT — the best entry in this record.** It is a correction of *method*, not of code, and it is right: the scan reads app sources and is structurally blind to a package edit. Running it confirmed the claim was false, two mutations were run instead, and the design and tasks were fixed **before** the commit that depended on them. My **MS** finding is this same reasoning carried one step further — the app-source mutation apply chose is caught; a different one is not. |
| 2 | **`TapSearchView.swift` was edited though the brief said it might not need it** | **ACCEPT.** No behaviour line changed; the inert-row **comment** named the retired rule, and a comment asserting a rule the code no longer implements is exactly the drift these files are scanned for. |
| 3 | **Two `routableID == nil` assertions moved inside a DD-20 row** | **ACCEPT.** Verified: every assertion about receipt keying is byte-identical; only the lines pinning the retired routability rule moved, because they were the retired rule stated inside a row about something else. |
| 4 | **PS8's "unreachable collision note" paragraph contained a claim round 7 falsifies** | **ACCEPT, and important.** It gave two reasons; one is now false. Rewritten to rest on branch ordering alone, with an explicit note that the ordering is itself asserted. Catching a justification that quietly stopped being true is harder than catching a broken test. |
| 5 | **`specs/README.md` still excluded the name-only pane** — stale since round 6 | **ACCEPT**, and the handling is right: struck through and annotated rather than deleted, because that list records what each slice deliberately left out. Correctly flagged as a round-6 miss found in round 7 — which I did not catch in round 7 either. |
| 6 | **Suite-level filters throughout** | **ACCEPT.** |

**Six accepted, zero rejected.**

---

### Commit hygiene and branch size

- **43 commits**, all Conventional Commits, **no AI attribution**.
- Round 7's four are correctly ordered: `docs(sdd)` amendment first, then `feat(search)`, `test(taps)`,
  `docs(sdd)` record.
- `git diff --shortstat main...HEAD` → **30 files, +9,876/−64 = 9,940 authored lines**, matching apply's
  figure exactly this round — the first round where the two agree, because apply measured after its own
  record commit.
- Working tree clean at start; only this report modified at the end.

---

### Issues Found

**CRITICAL**: None. **Blockers**: None.

**WARNING** (4):

- **W1 — PS8's amended `unit-app` scenario is PARTIAL: the install-state half of its second AND clause is
  unenforced.** The clause requires that the surface consult *neither the collision fact nor the install
  state* to decide selection. `alsoInCatalog` is forbidden and **MT** trips it; but `hit.isInstalled` is
  legitimately needed for the Installed pill, so the only guard against selection use is a scan for the
  **ternary** spelling `hit.isInstalled ? `. **MS** used the comma form —
  `if let routable = hit.routableID, hit.isInstalled {` — which makes every unambiguous **not-installed**
  hit inert, silently reverting round 6's product decision, and **all 15 suite tests passed**.
  **Remediation (this is the finding that denies a passing verdict)**: at
  `cellarTests/TapSearchCompositionTests.swift:295` (and `:261`), append the opening brace so the binding
  must be the whole condition — `#expect(surface.code.contains("if let routable = hit.routableID {"))`.
  Verified both ways: the shipped source contains that exact string once; under **MS** it does not. Then
  re-run `xcodebuild test … -only-testing:cellarTests` and re-verify. No production line changes.

- **W2 — one task is open: `6′.7`, "Delivery — one PR"**, deferred again by instruction. The drafted body
  now needs updating to **9,940** lines, **261** distinct ids, and the colliding-row route.

- **W3 — the latency scenario is not exercised by the spec's declared `unit` runner** (both rows are
  `.enabled(if: isRelease)` and report skipped under `swift test`). Covered by the release runner, which
  this session ran; mirrors the shipped PS6 precedent.

- **W4 — the exact latency figures remain unreproducible**, emitted only inside the `#expect` failure
  message. The binding clause — both turns under 8 ms — is confirmed for the seventh round.

**SUGGESTION** (11):

- **S1** — tautological assertion in `TapPackageSearchTests.swift` (`[...8 literals].count == 8`).
- **S2** — `AppSection.tapSearch.title` is unreachable; DD-14 wrongly calls it spec-pinned.
- **S3** — PS8 sc17's zero-diff half has no shipped enforcement; hand-verified **eight** rounds. A CI step
  would end the manual check.
- **S4** — correct the design's wiring table to ten sites.
- **S5** — DD-17 still says "the four empty states" are pinned; the spec pins two.
- **S6** — non-building intermediate commits in rounds 2–3 only.
- **S7** — eight branch-size figures now circulate; this round's two finally agree. State the convention
  once at archive and quote only the final figure.
- **S8** — rename drift for three tests in `design.md` and `tasks.md`.
- **S9** — round-3 deviation 3's "names no trust concept" is loose.
- **S10** — record the distinct-id counting rule at archive: **membership**, not break position; and note
  the **two-run union** as the cheaper cross-check, since the interleaving is non-deterministic.
- **S11** — the round-6 ledger arithmetic still does not foot (25 declared, +32 measured).

---

### Verdict

**FAIL — on evidence completeness only. 0 blockers, 0 CRITICAL, 4 WARNING, 11 SUGGESTION.**

The change itself is in good shape, and the reversal is the best-argued of the seven. It corrects a
reason rather than bending a rule: the old prohibition measured the destination against the row's *token*
when the row's own pinned note already named the *catalog package* as what Homebrew installs — so opening
that pane is keeping the promise the row makes, not breaking it. The implementation is a single deleted
conjunct; `PackageDetailView.swift` is untouched this round, which is the cleanest possible proof that no
branch was added; and `TapSearchView.swift` changed only a comment, because the view had been gating on
the projection's answer all along.

**MQ** and **MR** pin the surviving rule from both sides, and **MT** re-proves the collision guard. One
fact denies a passing verdict, and it is the same shape as round 2's: a scenario clause with no assertion
behind it.

**W1** — PS8's amended `unit-app` scenario requires the surface to consult neither the collision fact nor
the install state when deciding selection. The collision half is enforced. The install-state half is
guarded only against the ternary spelling, and **MS** slipped past it with a comma-form guard clause that
makes every unambiguous not-installed hit inert — reverting round 6's product decision and disabling the
name-only pane's only route — while all fifteen tests passed. Nothing is broken in the shipped code; what
is missing is the assertion that would keep it that way.

The remedy is to append one brace, making the optional binding the whole condition. I verified it fails
under **MS** and holds on the shipped source. Re-run the scoped app-target runner and re-verify; nothing
else in this report changes.
