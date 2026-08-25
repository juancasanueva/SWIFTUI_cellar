```yaml
schema: gentle-ai.verify-result/v1
evidence_revision: sha256:e85270e4b7ccbae169fc4c5e96b420d3a6b7fb30ef27e21070ba4eb64aabadb2
verdict: pass_with_warnings
blockers: 0
critical_findings: 0
requirements: 4/4
scenarios: 43/43
test_command: xcodebuild test -project cellar.xcodeproj -scheme cellar -destination 'platform=macOS,arch=arm64' -only-testing:cellarTests
test_exit_code: 0
test_output_hash: sha256:922291ddd7f1fab2f356a525ce43292eeaf4c23cc14cfda3de12ba362b32b78a
build_command: xcodebuild build -project cellar.xcodeproj -scheme cellar -destination 'platform=macOS,arch=arm64'
build_exit_code: 0
build_output_hash: sha256:e16ff3dfbc50c4b11282ffe0f0db978ebfa57f546e88a0684158171646296747
```

## Verification Report — round 9 (supersedes rounds 1–8)

**Change**: `m11-tap-search`
**Version**: spec deltas **r8**, **unchanged** since round 8 — `openspec/changes/m11-tap-search/specs/**`
has a zero-line diff across the remediation
**Mode**: Strict TDD, coverage threshold 0
**Branch**: `feat/m11-tap-search` @ `b93962d`, **45 commits** off `main` @ `edda9a5`, tree clean before
this run and carrying only this rewritten report after it
**Artifact store**: hybrid — this file is canonical; Engram topic `sdd/m11-tap-search/verify-report`
mirrors it. RDD disabled.
**Delivery**: `single-pr` with a maintainer-accepted `size:exception`. The branch measures **9,853**
changed lines — recorded, **not** a finding.
**Independence**: fresh context. All five runners re-executed at `b93962d`; both round-8 mutations
re-run against the fixed assertions.

---

### History (superseded)

| Round | Verdict | Substance |
|---|---|---|
| 2 `36f1b8d` | **fail** (34/35) | PS8 sc15's trust scan missed the projection. |
| 3 `f98d9fa` | pass_with_warnings | Trust scan fixed. |
| 4 `9894a6a` | pass_with_warnings | Shared **Installed** pill. |
| 5 `c760d28` | pass_with_warnings (37/37) | Shared **UPDATE** pill; offered version as a fact. |
| 6 `3cc53a4` | pass_with_warnings (38/38) | Mutation handoff to the shared menu. |
| 7 `8aeb774` | pass_with_warnings (42/42) | Not-installed hits selectable; name-only inventory-fed pane. |
| 8 `21956b0` | **fail** (42/43) | Colliding hits selectable → catalog detail. **W1**: the amended `unit-app` selection scenario's install-state clause was unenforced. |

---

### Round 8's W1, and its remediation

Round 8 found that PS8's amended `unit-app` scenario — *"the surface consults neither the collision fact
**nor the install state** to decide selection"* — enforced only the collision half. `hit.isInstalled`
cannot be blanket-banned because the row legitimately reads it for the Installed pill, and the only guard
against selection use scanned for the **ternary** spelling. My **MS** mutation used the comma form,
making every unambiguous **not-installed** hit inert — silently reverting round 6's product decision —
while all fifteen tests passed.

`c930add` — *"test(taps): pin the whole selection condition, not just its binding"* — is exactly the
prescribed fix and nothing else:

```diff
-        #expect(surface.code.contains("if let routable = hit.routableID"))
+        #expect(surface.code.contains("if let routable = hit.routableID {"))
```

applied at **both** call sites (`:261` and `:295`). Appending the opening brace makes the optional
binding the **whole** condition, so any added conjunct fails the scan.

**Verified, not assumed:**

| Check | Result |
|---|---|
| Production lines changed since `21956b0` | **none** — `git diff 21956b0..HEAD -- cellar/ Packages/CellarCore/Sources/` is empty |
| Files changed at all since `21956b0` | exactly two: `TapSearchCompositionTests.swift` and this report |
| `TapSearchView.swift` SHA | `008c8f28…3c88` — **byte-identical to round 8's baseline** |
| The exact gate in the shipped view | present **once** |
| Assertions pinning it | **two** |
| My round-8 report committed unedited | ✅ committed file hashes `f3e06095…113a`, matching the bytes I persisted |

---

### Non-vacuity — both round-8 mutations re-run

Each applied, run, restored with `shasum -a 256` matching the pre-mutation digest;
`git status --porcelain` printed nothing after each. Suite-level `-only-testing:` filters throughout.

| # | Mutation | Round 8 | Round 9 |
|---|---|---|---|
| **MS** | `if let routable = hit.routableID, hit.isInstalled {` | ⚠️ **all 15 passed** | ❌ **`theTapSearchSurfaceSelectsOnRoutabilityAlone` failed — and only that test** |
| **MT** | `if let routable = hit.routableID, hit.alsoInCatalog == false {` | ❌ that test failed | ❌ unchanged — that test failed, and only that test |

**MS is the decisive one**: it is the exact regression that slipped through in round 8, and it now fails.
**MT** confirms the fix added no over-reach — the collision guard behaves exactly as it did, and the other
fourteen tests pass under both mutations, so the assertion is targeted rather than broad.

---

### Build & Tests Execution — re-executed at `b93962d`

**Build**: ✅ `** BUILD SUCCEEDED **`, exit 0.

| Runner | Exact result | Exit | Output sha256 |
|---|---|---|---|
| `xcodebuild test … -only-testing:cellarTests` (run 1) | `** TEST SUCCEEDED **` — **261 distinct ids**, 0 failed | 0 | `922291dd…b78a` |
| `xcodebuild test … -only-testing:cellarTests` (run 2) | `** TEST SUCCEEDED **` — **261 distinct ids**, 0 failed | 0 | `0f5b92d7…26aa` |
| `swift test --package-path Packages/CellarCore` | **1,879 tests / 218 suites passed, 1 known issue** | 0 | `8383b2f3…5246` |
| `xcodebuild build … -scheme cellar` | `** BUILD SUCCEEDED **` | 0 | `e16ff3df…6747` |
| `swift test -c release … --filter 'TapPackageSearchTests'` | **36 tests / 1 suite passed**, both latency rows green | 0 | `3f3509d6…1425` |

Latency holds under the 8 ms ceiling for the **eighth** consecutive round
(`theCatalogKeystrokeTurnIsUnchanged` 1.567 s, `theTapSurfaceKeystrokeTurnStaysUnderTheCeiling` 2.131 s).
The core suite is unchanged at 1,879/218 — a two-token assertion edit adds no test.

#### Distinct ids — 261, by three methods, and the id set is unchanged

| Method | Result |
|---|---|
| Run 1, membership rule | clean 260 + 1 dropped = **261** |
| Run 2, membership rule | clean 260 + 1 dropped = **261** |
| Union of the two clean sets | **261** |

`comm` against round 8's union reports **no additions and no removals** — the id sets are identical. That
is the expected signature of an assertion-only change, and it is a stronger statement than the count
alone: not merely the same number of tests, but the same tests.

Progression: **257 → 258 → 259 → 260 → 261 → 261 → 261**.

---

### Spec Compliance Matrix

**43 scenarios across 4 requirement blocks**, re-counted this session (`rg -c '^### Requirement:'` → **4**,
`rg -c '^#### Scenario:'` → **43**): PS8 22, PD6 6, TM5 12, TM11 3. The delta specs are **byte-identical**
to round 8 — the remediation touched no spec.

| Scenario | Test | Result |
|---|---|---|
| **only its duplicated rows are inert** (`unit-app`) — *"selectable on routability alone; consults neither the collision fact nor the install state"* | `theTapSearchSurfaceSelectsOnRoutabilityAlone` — collision half via the forbidden-token list (**MT**), **install-state half now via the whole-condition pin** (**MS**), plus the branch-order assertion | ✅ **COMPLIANT — was PARTIAL in round 8** |
| The other 42 | unchanged and green | ✅ COMPLIANT |

**Compliance summary**: **43/43 compliant, 0 partial, 0 untested, 0 failing.**

---

### Invariants — re-run at `b93962d`

| Path | Result |
|---|---|
| `cellar/Browse/BrowseView.swift` | ✅ **byte-identical to `main`** — ninth round running |
| `cellar/Browse/PackageDetailView.swift` | ✅ **unchanged since `6f18d2d`** — the "no new branch" claim, still proven by absence |
| `cellar/Activity/MutationMenu.swift` · `project.pbxproj` · `openspec/specs/**` · `cellarUITests/**` | ✅ ZERO-DIFF |
| `TapProjection.swift` · `PackageSearchIndex.swift` · `MutationCommand.swift` · `TapCommand.swift` | ✅ ZERO-DIFF |

`TapPackageSearch.swift` is SHA-identical to round 8 (`55796d93…4b98`) and the latency fixture is
unchanged, so the projection this round verifies is byte-for-byte the one round 8 verified.

---

### Completeness

| Metric | Value |
|--------|-------|
| Task checkboxes total | 236 |
| Complete | **234** |
| Incomplete | **2** — `6.7` (round 1, **VOID**) and `6′.7` (open the PR) |

Unchanged from round 8: a test-only remediation adds no task.

---

### Commit hygiene and branch size

- **45 commits**, all Conventional Commits, **no AI attribution**.
- `c930add` is correctly typed `test(taps):` — it changes only a test file — and its subject names the
  actual behaviour change ("pin the whole selection condition, not just its binding").
- `git diff --shortstat main...HEAD` → **30 files, +9,789/−64 = 9,853 authored lines**, **down 87** from
  round 8's 9,940. The reason is worth stating because it looks like an error and is not: the branch diff
  counts `verify-report.md`, and round 8's report is 87 lines shorter than round 7's, so committing it
  *reduced* the branch total. This is the clearest illustration yet of **S7** — the size figure moves with
  the verification artifact itself and can go down.
- Working tree clean at start; only this report modified at the end.

---

### Out-of-scope tracked items

- The full `-scheme cellar` runner is red on `main` from two pre-existing `cellarUITests` Taps failures
  (`:209`, `:231`), tracked separately. `cellarUITests/**` zero-diff here.
- `PRD.md` §7 ends at **M6**; no PRD milestone closes with this change.

---

### Issues Found

**CRITICAL**: None. **Blockers**: None.

**RESOLVED since round 8**: **W1** — the install-state half of PS8's amended `unit-app` selection
scenario is now enforced. Closed by `c930add`, verified here by re-running the exact mutation that
slipped through, which now fails that test and only that test.

**WARNING** (3):

- **W1 — one task is open: `6′.7`, "Delivery — one PR".** Deferred again by instruction. The drafted body
  needs the final figures: **9,853** lines, **261** distinct ids, and the colliding-row route.
  **Remediation**: open the PR, then tick `6′.7`. No code changes.

- **W2 — the latency scenario is not exercised by the spec's declared `unit` runner.** Both rows are
  `.enabled(if: isRelease)` and report **skipped** under `swift test`; covered only by the release runner,
  which this session ran. Mirrors the shipped PS6 precedent
  (`CatalogTests/SearchLatencyTests.swift:35`).
  **Remediation**: at archive, record the release invocation beside the `unit` runner. No code change.

- **W3 — the exact latency figures remain unreproducible**, emitted only inside the `#expect` failure
  message. The binding clause — both turns under **8 ms** — is independently confirmed for the eighth
  round.

**SUGGESTION** (11): carried unchanged from round 8, none newly introduced —

**S1** tautological assertion in `TapPackageSearchTests.swift` · **S2** `AppSection.tapSearch.title` is
unreachable and DD-14 wrongly calls it spec-pinned · **S3** PS8 sc17's zero-diff half has no shipped
enforcement, hand-verified **nine** rounds; a CI step (`git diff --quiet <base> -- cellar/Browse/BrowseView.swift`)
would end the manual check · **S4** correct the design's wiring table to ten sites · **S5** DD-17 says
"the four empty states" are pinned where the spec pins two · **S6** non-building intermediate commits in
rounds 2–3 only · **S7** the branch-size figure moves with the verify report and has now moved *down*;
state the convention once at archive and quote only the final figure · **S8** rename drift for three
tests in `design.md` and `tasks.md` · **S9** round-3 deviation 3's "names no trust concept" is loose ·
**S10** record the distinct-id rule at archive: **membership**, not break position, plus the **two-run
union** as the cheaper cross-check · **S11** the round-6 ledger arithmetic still does not foot (25
declared, +32 measured).

---

### Verdict

**PASS WITH WARNINGS.** 0 blockers, 0 CRITICAL, 3 WARNING, 11 SUGGESTION, requirements **4/4**,
scenarios **43/43**.

Round 8's single blocking finding is closed, and closed exactly as prescribed: two one-token edits that
make the optional binding the whole condition, applied at both call sites, with **no production line
touched**. I did not take the remediation on report — I re-ran the mutation that defeated the old
assertion, and it now fails `theTapSearchSurfaceSelectsOnRoutabilityAlone` and only that test, while
**MT** confirms the collision guard is unchanged and the fix is targeted rather than broad.

Everything else re-confirms. All five runners are green at `b93962d`; the id sets from two runs are
**identical to round 8's**, not merely the same size, which is the right signature for an assertion-only
change; the core suite, the release suite and the spec counts are unchanged; and every zero-diff
invariant holds, including `BrowseView.swift` byte-identical to `main` for the ninth round and
`PackageDetailView.swift` untouched since `6f18d2d`.

The three remaining warnings are one deferred PR and two standing notes about how latency is measured in
this repository. None blocks. **`m11-tap-search` is archive-ready.**
