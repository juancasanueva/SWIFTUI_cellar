```yaml
schema: gentle-ai.verify-result/v1
evidence_revision: sha256:847976bc7aeb52d5b8807db26dceabad9db6e5081ce449efeef766bc4d410d13
verdict: pass_with_warnings
blockers: 0
critical_findings: 0
requirements: 4/4
scenarios: 38/38
test_command: xcodebuild test -project cellar.xcodeproj -scheme cellar -destination 'platform=macOS,arch=arm64' -only-testing:cellarTests
test_exit_code: 0
test_output_hash: sha256:c53b80bebb62636ab74af624049cf29f6137afe90ae157dc884d9faf85de72f8
build_command: xcodebuild build -project cellar.xcodeproj -scheme cellar -destination 'platform=macOS,arch=arm64'
build_exit_code: 0
build_output_hash: sha256:eee74860496231c133545e3c0405f0088b58c390db2fced7e3b0e25cff7537a9
```

## Verification Report — round 6 (supersedes rounds 1–5)

**Change**: `m11-tap-search`
**Version**: spec deltas **r6** — PS8 ADDED (mutation-handoff member and the rewritten verbs clause),
PD6 MODIFIED, TM5 + TM11 MODIFIED
**Mode**: Strict TDD, coverage threshold 0
**Branch**: `feat/m11-tap-search` @ `3cc53a4`, **31 commits** off `main` @ `edda9a5`, tree clean before
this run and carrying only this rewritten report after it
**Artifact store**: hybrid — this file is canonical; Engram topic `sdd/m11-tap-search/verify-report`
mirrors it. RDD disabled.
**Delivery**: `single-pr` with a maintainer-accepted `size:exception` (2026-08-25). The branch measures
**8,064** changed lines — recorded, **not** a finding.
**Independence**: fresh context. All four runners re-executed at `3cc53a4`; three reversible mutations
of my own.

---

### History (superseded)

| Round | Commit | Verdict | Substance |
|---|---|---|---|
| 1 | — | superseded | Tap results as a `Section` inside `BrowseView`; withdrawn by the scope change. |
| 2 | `36f1b8d` | **fail** (34/35) | PS8 sc15's trust scan missed the projection. |
| 3 | `f98d9fa` | **pass_with_warnings** | Trust scan fixed. |
| 4 | `9894a6a` | **pass_with_warnings** | Shared **Installed** pill; `Installed.`/`Not installed.` withdrawn. |
| 5 | `c760d28` | **pass_with_warnings** (37/37) | Shared **UPDATE** pill; offered version as a fact. |

---

### What round 5 of apply changed, and whether it is right

The maintainer found the `⋯` menu on an **installed** tap row offering only Install and Copy install
command, while the same package on the catalog and Installed surfaces offers Reinstall, Uninstall…,
Uninstall and Zap…, Upgrade and Pin/Unpin. The cause was a composition defect, not a missing verb: the
row handed the shared menu `PackageEntry(installed: nil, …)`, so the menu's installed branch could never
be taken however installed the package was. Rounds 3 and 4 made the row's **marks** truthful; round 5
makes its **verbs** agree with them.

| Obligation (PS8 r6) | Delivered | Verified |
|---|---|---|
| Hit carries this machine's installed receipt as a **mutation handoff**, not a seventh fact | `TapSearchHit.installed: InstalledPackage?` | ✅ |
| Resolved by the **same tap-aware handoff**, never a bare `PackageID` lookup | `installedReceipt(for:)` = `package.installedHandoff.flatMap { installed.package($0) }` | ✅ proven by **MJ** |
| Offered version derived from **that same receipt** | `Self.offeredVersion(of: receipt)` — one lookup, two readers | ✅ |
| Present in **both** installed states, absent when not installed | `installedHandoff` answers for both | ✅ |
| Surface hands the record over; **no catalog record** | `PackageEntry(installed: hit.installed, catalog: nil, id: hit.mutationTarget)` | ✅ proven by **MK** |
| Surface re-implements no verb, argv, target or command | 13 forbidden tokens asserted absent from the view | ✅ proven by **ML** |
| Six facts remain six | `Mirror` enumeration lists `installed` **by name** | ✅ |
| `MutationMenu` itself untouched | **zero-diff vs `main`** | ✅ |

**The single-lookup refactor is the quiet improvement of the round.** Round 4 derived the offered version
in its own function; round 5 resolves the receipt **once** and reads it twice, so the row's update pill
and its menu are the same record *by construction rather than by agreement*. The code comment says
exactly that, and it is the kind of change that removes a class of future bug rather than a bug.

**The six-facts claim survives honestly.** A stored `InstalledPackage` is a large value to hang on a type
whose requirement says "exactly six facts", and the temptation would be to leave it unlisted. Instead the
spec adds a paragraph explaining why a handoff is not a fact, and the `Mirror` assertion **enumerates it
by name** — so a later member that genuinely is tap-published metadata cannot slip in behind it. That is
the right shape: the enumeration is now a whitelist, not a token filter.

---

### Non-vacuity — three reversible mutations

Each applied, run, and restored with `shasum -a 256` matching the pre-mutation digest;
`git status --porcelain` printed nothing after each. All app-target runs used **suite-level**
`-only-testing:` filters.

| # | Mutation | Expected | Observed |
|---|---|---|---|
| **MJ** | `installedReceipt` keyed by bare `package.id` instead of `installedHandoff` | a foreign receipt must never attach | ❌ **2** tests failed — `aCollidingCatalogReceiptIsNeverAttachedToATapRow` showed `stray.installed` becoming the **`homebrew/core` `wget` receipt** on a third-party tap row, and `aReceiptFromAnotherTapOffersNoVersion` failed with `nextVersion → "9.9.9"` |
| **MK** | re-introduce the original defect: `PackageEntry(installed: nil, …)` | the defect must be caught | ❌ **2** tests failed — `anInstalledTapRowReachesTheMutationMenuWithItsRecord` and `theTapSearchSurfaceComposesNoTrustGateAndNoBadge` |
| **ML** | view reads the record itself: `hit.installed?.isOutdated` | the view must not re-derive | ❌ **2** tests failed — the same handoff test plus `bothSearchSurfacesDrawTheOneSharedUpdatePill` |

**MJ is the decisive one**, and its failure output is the clearest evidence in this whole change: keying
by bare identity attaches `homebrew/core`'s receipt to a row published by `acme/tools`, which would offer
to uninstall a package the row does not name. Every other test still passed under that mutation — it is
exactly the silent, plausible-looking wrong implementation that only a targeted assertion catches.

**MK and ML each tripped two independent guards**, so the round-5 obligations have defence in depth
rather than a single point of enforcement.

---

### Completeness

| Metric | Value |
|--------|-------|
| Task checkboxes total (five rounds) | 180 |
| Complete | **178** |
| Incomplete | **2** — `6.7` (round 1, **VOID**) and `6′.7` (open the PR) |

Round 5 added **19** boxes and completed all 19 (159 + 19 = 178), and correctly declares no delivery task
of its own.

---

### Build & Tests Execution — all four runners re-executed at `3cc53a4`

**Build**: ✅ `** BUILD SUCCEEDED **`, exit 0.

| # | Runner | Exact result | Exit | Output sha256 |
|---|---|---|---|---|
| 1 | `xcodebuild test … -only-testing:cellarTests` | **`** TEST SUCCEEDED **`** — **260 distinct test ids**, 0 failed | 0 | `c53b80be…72f8` |
| 2 | `swift test --package-path Packages/CellarCore` | **1,873 tests / 217 suites passed, 1 known issue** (was 1,872; **+1**) | 0 | `2d63ba98…ff34` |
| 3 | `xcodebuild build … -scheme cellar` | **`** BUILD SUCCEEDED **`** | 0 | `eee74860…37a9` |
| 4 | `swift test -c release … --filter 'TapPackageSearchTests'` | **35 tests / 1 suite passed** (was 34; **+1**), both latency rows passed | 0 | `9e09aafc…ca8a` |

Every figure apply reported reproduced: core **1,873/217**, app target **260 distinct**, release **35**.

**Latency**: `theCatalogKeystrokeTurnIsUnchanged` 1.504 s, `theTapSurfaceKeystrokeTurnStaysUnderTheCeiling`
2.081 s. Fifth consecutive round under the 8 ms ceiling.

#### The S10 counting rule, applied and validated end to end

Round 5 established that an interleaved xcodebuild status block costs an id **only when it breaks inside
the quoted identifier**. This round exercised both halves of that rule and it held exactly:

- The r6 log has **one** mangled line —
  `BrewfileCompositionTests/missingRowsArriveSelectedAndPresentRowsAreNot()` — but the break lands in the
  **tail**, after `' passed`, so the id is intact and already counted. **No adjustment: 260.**
- A naive `comm` against round 5's id set reports **two** additions:
  `TapSearchCompositionTests/anInstalledTapRowReachesTheMutationMenuWithItsRecord()` — genuinely new —
  and `AutomaticUpdateChecksTests/aFreshInstallReadsAsOff()`, which is **not** new: it is precisely the id
  round 5's log lost to an in-identifier break and which round 5's report recovered by the rule. Its
  reappearance in this round's clean set is independent confirmation that the round-5 count of 259 was
  right and the recovery was sound.

Progression: **257 → 258 → 259 → 260**, one unit-app test per round, no gaps.

---

### Spec Compliance Matrix

**38 scenarios across 4 requirement blocks**, re-counted this session (`rg -c '^### Requirement:'` → **4**,
`rg -c '^#### Scenario:'` → **38**): PS8 **20** (+1), PD6 4, TM5 11, TM11 3. Class tally 29 `unit` +
7 `unit-app` = 36 inline lines; the two unlabelled are PD6's reproduced scenarios.

#### The scenarios r6 added or amended

| Scenario | Requires | Test | Result |
|---|---|---|---|
| **six facts** (amended) | the one further member is the **mutation handoff**, absent for a not-installed hit, so the enumeration still exposes six facts and carries no tap-published value | `TapPackageSearchTests > aHitCarriesItsSixFactsAndItsCopyAndNothingElse` — `#expect(hit.installed == nil)` plus the `Mirror` label list naming **`installed`** explicitly (`:188-195`) | ✅ COMPLIANT |
| **offered version** (amended, +2 clauses) | each hit's handoff present for both installed states and the outdated withheld one, absent for not-installed, resolved by the tap-aware handoff; and a colliding hit whose only receipt belongs to the catalog's tap carries **no** record | `> onlyAnOutdatedInstalledHitOffersAVersion` (`:636`), `> aCollidingCatalogReceiptIsNeverAttachedToATapRow` (`:710`, **new**), `> aReceiptFromAnotherTapOffersNoVersion` (`:758`) | ✅ COMPLIANT — non-vacuous by **MJ** |
| **An installed tap row reaches the shared mutation menu with its installed record** (new, `unit-app`) | the surface hands over the projection's record and no catalog record; declares no verb, command, target, submission or kind-narrowing of its own | `TapSearchCompositionTests > anInstalledTapRowReachesTheMutationMenuWithItsRecord` — call-site scoped entry assertion, `installed: nil` absent from the whole file, four lookup routes forbidden, the menu positively anchored on `if entry.isInstalled {` with each of six verbs declared **exactly once**, and 13 tokens forbidden in the view | ✅ COMPLIANT — non-vacuous by **MK** and **ML** |
| **ps15** (amended wording) | "the **mutation affordances** are offered for every hit whatever the origin tap's trust state" | `> theTapSearchSurfaceComposesNoTrustGateAndNoBadge` — its entry pin moved to `installed: hit.installed` with `catalog: nil` still pinned | ✅ COMPLIANT |

The new `unit-app` guard's forbidden list carries a documented carve-out: `installed.inventory` is
**not** forbidden, because the view hands that whole inventory *to* the projection — the shipped
composition, and the opposite of resolving a record locally. What is forbidden is a lookup. That
reasoning is recorded in the test itself, which is where it belongs.

#### The other 34 scenarios

Unchanged and re-confirmed green: both pill contracts, the trust scan over projection and surface, the
withdrawn-copy literals, matching/order/collision/routability, empty states, latency, and the untouched
catalog surface.

**Compliance summary**: **38/38 compliant, 0 partial, 0 untested, 0 failing.**

---

### Invariants — zero-diff proof, re-run at `3cc53a4`

| Path | Result |
|---|---|
| **`cellar/Activity/MutationMenu.swift`** | ✅ **ZERO-DIFF vs `main`** — the round's load-bearing claim: the verbs were never missing, only unreachable |
| `cellar/Browse/BrowseView.swift` | ✅ **byte-identical to `main`** — sixth round running |
| `cellar.xcodeproj/project.pbxproj` · `openspec/specs/**` | ✅ ZERO-DIFF |
| `cellar/Browse/PackageDetailView.swift` · `cellarUITests/**` | ✅ ZERO-DIFF |
| `PackageSearchIndex.swift` · `MutationCommand.swift` · `TapCommand.swift` · `TapProjection.swift` | ✅ ZERO-DIFF |
| `cellar/Browse/PackageRow.swift` · `cellar/Browse/StatusPill.swift` | ✅ **ZERO-DIFF this round** (`2cba75b..HEAD`) |

Round 5 touched exactly **nine** files: the projection, two test files, the tap view, and five artifacts.
No new brew invocation — the receipt comes from the inventory the projection already holds.

---

### Coherence — DD-20

| # | Decision | Followed? | Notes |
|---|---|---|---|
| **DD-20 (new)** | carry the installed receipt as a mutation handoff, resolved once by the tap-aware handoff and read by both the offered version and the menu | ✅ | Both halves independently proven (**MJ**, **MK**/**ML**). The relationship to DD-19 is stated rather than glossed: DD-19 rejected replacing a *stored fact* with a computed one; DD-20 adds a member *alongside* it, so `Mirror` still enumerates the fact |

---

### TDD Compliance

| Check | Result | Details |
|---|---|---|
| TDD Evidence reported | ✅ | Round-5 cycle table in `apply-progress.md` |
| RED confirmed | ✅ | Projection rows by genuine compile failure; view rows by reversible mutation |
| GREEN confirmed | ✅ | 260 distinct cellarTests + 1,873 core + 35 release-filter, all green this session |
| Triangulation adequate | ✅ | Handoff asserted across all four install/outdated states **plus** the colliding-catalog-receipt case, which is a distinct failure mode rather than a fifth variation |
| Safety net | ✅ | 259 → 260 distinct (+1); 1,872 → 1,873 (+1) |
| Filter discipline | ✅ | Suite-level `--filter` and `-only-testing:` throughout, per the round-4 lesson |
| Mutations restored | ✅ | Apply's and my own three, all SHA-verified |

**TDD Compliance**: 7/7 checks passed.

### Test Layer Distribution

| Layer | Tests | Files | Tools |
|---|---|---|---|
| Unit (`unit`) | **35** in `TapPackageSearchTests` (33 debug + 2 release-gated) | 1 + 3 fixtures | Swift Testing |
| Unit-app (`unit-app`) | **14** in `TapSearchCompositionTests` (was 13) | 7 | Swift Testing + `#filePath` source scan |
| Integration / E2E | 0 | 0 | `cellarUITests` zero-diff, out of scope |

### Changed File Coverage

➖ Coverage analysis skipped — no coverage tool configured. Threshold is 0.

### Assertion Quality

| File | Line | Assertion | Issue | Severity |
|---|---|---|---|---|
| `TapPackageSearchTests.swift` | 1189 | `#expect([...8 string literals].count == 8)` | Tautology over a literal | SUGGESTION (**S1**) |

Round 5's new assertions are sound: the entry check is **call-site scoped** via `callSite("PackageEntry(")`
rather than a whole-file `contains`, each menu verb is asserted to appear **exactly once**, and the
`installed: nil` absence is asserted over the whole file rather than only at the call it was fixed in.

**Assertion quality**: 0 CRITICAL, 0 WARNING, 1 SUGGESTION.

---

### Round-5 deviations, judged

| # | Deviation | Judgment |
|---|---|---|
| 1 | **A stored member added to a type whose requirement says "exactly six facts"; spec amended to say why** | **ACCEPT.** The alternative — leaving it unexplained — would have made the requirement read as violated. Enumerating it by name in the `Mirror` assertion converts the enumeration into a whitelist, so the next member cannot hide behind this one. Stronger than before, not weaker. |
| 2 | **DD-19 rejected a computed `nextVersion` reading a stored receipt; DD-20 is not that** | **ACCEPT.** The distinction is real and correctly drawn: DD-19 refused to *replace* a stored fact with a computed one because `Mirror` would then deny it; DD-20 adds a member alongside, and `nextVersion` stays stored. |
| 3 | **The first draft of the new guard forbade `installed.inventory` and was wrong** | **ACCEPT, and this is good practice.** The over-broad token would have banned the shipped composition (the view hands the inventory *to* the projection). It was caught by a red run, narrowed to genuine lookups, and the reason recorded **in the test** so the next reader does not re-add it. Self-reported at the cost of one red run. |
| 4 | **`specs/README.md`'s totals line was already wrong and was corrected** | **ACCEPT — and I share the miss.** It read "20 new scenarios (15 `unit`, 5 `unit-app`)" from revision 3 onward while its own table summed to 22 and then 23. Rounds 3 and 4 amended the table without re-footing the summary. I verified the delta **files** every round and they were always right, but I never cross-footed the README's summary against its own table, so I did not catch it in round 4 or 5 either. Now **23 (16 `unit`, 7 `unit-app`)**, which I re-derived independently: PS8 20 + PD6 1 + TM5 1 + TM11 1 = 23, and 13+7 unit-app-split ⇒ 16 `unit` + 7 `unit-app`. Correction stated inline rather than applied silently. |
| 5 | **One core-suite flake, identified this time** — `MutationRefreshReceiptTests.swift:214`, `cancellationBeforeSpawn` | **ACCEPT**, and **this closes round 5's S11.** The branch touches no refresh terminal, `MutationRefreshReceipt` or `OperationCenter`; the suite alone re-ran 9/9 and two whole-suite runs passed 1,873/217. First flake in four rounds with an identity attached, and apply credits the "redirect, never `tee`" change for it — the remedy worked. |
| 6 | **Suite-level `--filter` for RED/GREEN, whole package for the gate** | **ACCEPT.** The round-4 function-level trap is being actively avoided rather than merely recorded. |

**Six accepted, zero rejected.**

---

### Commit hygiene and branch size

- **31 commits**, all Conventional Commits, **no AI attribution**.
- Round 5's four are correctly typed and ordered: `docs(sdd)` amendment, `feat(taps)` behaviour,
  `test(taps)` guard, `docs(sdd)` record.
- `git diff --shortstat main...HEAD` → **26 files, +8,009/−55 = 8,064 authored lines**. Apply reports
  **7,919**, measured before its own record commit; the difference is exactly the 145-line round-5
  section of `apply-progress.md` (7,919 + 145 = 8,064). Same pattern as round 3 — see **S7**.
- Split: **code+test ~3,300**, artifacts the remainder. Under the accepted `size:exception`.
- Working tree clean at start; only this report modified at the end.

---

### Out-of-scope tracked items

- The full `-scheme cellar` runner is red on `main` from two pre-existing `cellarUITests` Taps failures
  (`:209`, `:231`), tracked separately. `cellarUITests/**` zero-diff here.
- `PRD.md` §7 ends at **M6**; no PRD milestone closes with this change.

---

### Issues Found

**CRITICAL**: None.

**RESOLVED since round 5**: **S11** — the recurring core-suite flake now has an identity
(`MutationRefreshReceiptTests.swift:214`), obtained by the redirect-not-`tee` remedy.

**WARNING** (4):

- **W1 — one task is open: `6′.7`, "Delivery — one PR".** Deferred again by instruction.
  **Remediation**: open the PR with the drafted body, now needing five corrections — line count
  **8,064**, app-target figure **260 distinct ids**, the two shared pill components, the offered-version
  fact, and a statement that installed tap rows now reach the shared menu with their record. Then tick
  `6′.7`.

- **W2 — the latency scenario is not exercised by the spec's declared `unit` runner.** Both rows are
  `.enabled(if: isRelease)` and report **skipped** under `swift test`; covered only by the release
  runner, which this session ran. Mirrors the shipped PS6 precedent.
  **Remediation**: record the release invocation beside the `unit` runner at archive. No code change.

- **W3 — the exact latency figures remain unreproducible**, emitted only inside the `#expect` failure
  message. The binding clause — both turns under **8 ms** — is confirmed for the fifth round.

- **W4 (new) — the Engram `tasks` mirror is two rounds stale, breaking the hybrid-store contract.**
  Verified directly: obs **#7799** is titled "ROUND 3" and describes a canonical file of **1,022 lines**;
  `openspec/changes/m11-tap-search/tasks.md` is now **1,194 lines** and carries rounds 4 and 5. The
  `apply-progress` mirror (obs #7800) is current at round 5, so this is one topic, not a systemic failure.
  Hybrid requires **both** writes to succeed for an artifact to be complete, so a reader recovering from
  Engram alone would plan against a two-round-old task list.
  **Remediation**: re-`mem_save` `sdd/m11-tap-search/tasks` from the canonical file with
  `capture_prompt: false` before archive. No code change.

**SUGGESTION** (10):

- **S1 — a tautological assertion** at `TapPackageSearchTests.swift:1189`.
- **S2 — `AppSection.tapSearch.title == "Search taps"` is unreachable**; DD-14 calls it "pinned by spec"
  and the spec pins nothing for `title`.
- **S3 — the zero-diff half of PS8 sc17 has no shipped enforcement.** Hand-verified **six** rounds
  running; a CI step would end the manual check.
- **S4 — correct the design's wiring table to ten sites.**
- **S5 — DD-17 still says "the four empty states" are pinned**; the spec pins two.
  `"Reading your taps"` (`TapSearchView.swift:221`) remains the only view-composed, unpinned sentence.
- **S6 — non-building intermediate commits** in rounds 2–3 only; rounds 4 and 5 both fixed the pattern by
  adding rather than renaming. The round-4/5 approach is the one to keep.
- **S7 — six branch-size figures now circulate** (5,754 / 5,889 / 6,340 / 6,891 / 7,919 / **8,064**). The
  recurring cause is that apply measures before committing its own record; state the convention once at
  archive and quote only the final figure in the PR.
- **S8 — rename drift in the artifacts, two tests.** `design.md:271` and `:352` still name the pre-rename
  `theBrowseTapSurfaceComposesNoTrustGateAndNoBadge` and `aHitCarriesItsFiveFactsAndItsCopyAndNothingElse`.
- **S9 — round-3 deviation 3's "names no trust concept" is loose** (`StatusPill.swift` cites PT5 in a
  doc comment). Conclusion unaffected.
- **S10 — the distinct-id counting rule is now validated end to end** and should be recorded at archive:
  adjust only when the break lands inside the quoted identifier. This round proved both branches of it.

---

### Verdict

**PASS WITH WARNINGS.** 0 blockers, 0 CRITICAL, 4 WARNING, 10 SUGGESTION, requirements **4/4**,
scenarios **38/38**.

The defect was real and the diagnosis was better than the symptom suggested: the verbs were never
missing, only unreachable, because the row handed the shared menu an entry built with no installed
record. The fix hands the record over and changes nothing else — `MutationMenu.swift` carries a
**zero-line diff against `main`**, which is the cleanest possible evidence that no verb was
re-implemented, re-worded or re-ordered.

Two things raise this above a mechanical fix. The receipt is resolved **once** and read by both the
offered version and the menu, so the row's update pill and its verbs are the same record by construction
rather than by agreement. And the awkward part — a stored `InstalledPackage` on a type whose requirement
says "exactly six facts" — is handled by explaining it in the spec and **enumerating the member by name**
in the `Mirror` assertion, which turns that enumeration into a whitelist rather than leaving a large
unlisted member sitting inside a claim about counting.

I proved the three things most likely to be wrong. **MJ** re-keyed the lookup to bare identity and
produced the exact catastrophe the spec warns about: `homebrew/core`'s `wget` receipt attached to a row
published by `acme/tools`, which would offer to uninstall a package the row does not name — with every
other test still green. **MK** restored the original defect and **ML** let the view read the record
itself; each tripped two independent guards.

One correction is mine to make rather than apply's. Deviation 4 fixes a `specs/README.md` totals line
that has been wrong since revision 3. I re-counted the delta **files** every round and they were always
right, but I never cross-footed that summary against its own table — so it survived my round-4 and
round-5 reports too. It is right now, and I re-derived the 23 independently.

The four warnings are one deferred PR, two standing latency-measurement notes, and a stale Engram
`tasks` mirror that a one-call re-save fixes. **`m11-tap-search` is archive-ready** once that mirror is
refreshed.
