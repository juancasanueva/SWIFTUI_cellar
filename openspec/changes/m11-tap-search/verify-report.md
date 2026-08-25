```yaml
schema: gentle-ai.verify-result/v1
evidence_revision: sha256:0d37b0e0126de73c4cbae1aa66bdb5d5dd67b0d68cdd0ab195fd53277d3fc40e
verdict: pass_with_warnings
blockers: 0
critical_findings: 0
requirements: 5/5
scenarios: 55/55
test_command: xcodebuild test -project cellar.xcodeproj -scheme cellar -destination 'platform=macOS,arch=arm64' -only-testing:cellarTests
test_exit_code: 0
test_output_hash: sha256:1e854542326006077a412faed5fa814687c123d9dd05cd3265cb28d2242001c8
build_command: xcodebuild build -project cellar.xcodeproj -scheme cellar -destination 'platform=macOS,arch=arm64'
build_exit_code: 0
build_output_hash: sha256:3767258fd147ccfafa87f0e4c930148547487f56d5a779520607f61dff924f05
```

## Verification Report — round 10 (supersedes rounds 1–9)

**Change**: `m11-tap-search`
**Version**: spec deltas **r9** — PS8 ADDED, PD6 MODIFIED, TM5 + TM11 MODIFIED, and a **new delta
capability**: `installed-inventory` **MODIFIED II15**
**Mode**: Strict TDD, coverage threshold 0
**Branch**: `feat/m11-tap-search` @ `5d8f659`, **51 commits** off `main` @ `edda9a5`, tree clean before
this run and carrying only this rewritten report after it
**Artifact store**: hybrid — this file is canonical; Engram topic `sdd/m11-tap-search/verify-report`
mirrors it. RDD disabled.
**Delivery**: `single-pr` with a maintainer-accepted `size:exception`. The branch measures **10,604**
changed lines — recorded, **not** a finding.
**Independence**: fresh context. All runners re-executed at `5d8f659`; four reversible mutations of my
own, none of them apply's two.

---

### History (superseded)

| Round | Verdict | Substance |
|---|---|---|
| 2 `36f1b8d` | **fail** (34/35) | PS8 sc15's trust scan missed the projection. |
| 3–7 | pass_with_warnings | Trust scan fixed; Installed pill; UPDATE pill; mutation handoff; name-only pane (42/42). |
| 8 `21956b0` | **fail** (42/43) | Colliding hits selectable. **W1**: the selection scenario's install-state clause was unenforced. |
| 9 `b93962d` | pass_with_warnings (43/43) | W1 closed by pinning the whole selection condition. |

---

### What round 8 of apply changed, and whether it is right

Maintainer UI feedback: the tap-backed detail panes hung the installed **row's** `⋯` menu in their
header, while the catalog pane answers the same question with a labelled **Actions section** at the foot.
Two detail panes offered one package's verbs in two shapes and two places. Round 8 gives both tap-backed
panes the catalog pane's **own** section and empties their header slot.

| Obligation | Delivered | Verified |
|---|---|---|
| Both tap panes present the **same** Actions section | `actionsSection(for:)` made `internal`, called from both extensions | ✅ **MU**, **MV**, **MW** |
| Header primary slot empty; no `MutationMenu` | `EmptyView()`; `MutationMenu(` absent from both panes | ✅ |
| Section sits **after** the pane's facts and footer | order asserted by range comparison | ✅ **MW** |
| No verb, argv, target or section copy re-implemented | 4 tokens + 7 complete verb literals asserted absent | ✅ **MV** |
| The shared menu untouched where it belongs | `MutationMenu.swift` **zero-diff**; `InstalledRow` still calls it | ✅ |
| Catalog pane behaviour-preserved | see below | ✅ |

**The `MODIFIED II15` delta is mandatory, and apply's reasoning for it is right.** II15 pinned the verbs'
**source** — *"the same mutation verbs the installed list row offers … obtained from the same shared
mutation surface"*. Changing the source contradicts that clause; it is not a re-styling. The verb sets
differ too (the section adds snooze, says `Pin version` where the menu says `Pin`, and shows a command
line rather than `Copy install command`). A change that alters what a promoted requirement pins needs a
delta, and this one has it.

#### II15 delta fidelity — checked against the promoted spec, not asserted

I compared the delta block against `openspec/specs/installed-inventory/spec.md` directly:

| Check | Result |
|---|---|
| Scenarios in the delta block | **12** |
| Appearing **verbatim** in the promoted spec | **11** |
| Replaced | **1** — `The surface offers the installed row's verbs and no trust control` → `The surface offers the catalog pane's Actions section and no trust control` |
| Prose edits | **exactly one bullet replaced** (the verbs clause) **plus its `(Previously: …)` line**; every other line of the requirement body is unchanged |

My first pass reported only 10 verbatim, which was **my** artefact: II15 is the last requirement in the
file, so my block extractor ran past its end and swallowed the archive notes into the final scenario.
Re-testing the real claim — does each delta scenario appear verbatim in the promoted file — gives 11 of
12. This is the same trailing-content trap apply itself recorded back in round 2, and it caught me here.

#### The catalog pane refactor is behaviour-preserving

`actionsSection(for package: CatalogPackage)` → `actionsSection(for entry: PackageEntry)`, `private` →
internal. Inside the body the diff is exactly `package.id` → `entry.id` (three sites) and the removal of
the now-redundant local `let entry = entry(for: package)`. All seven `detail-action-*` identifiers are
**unchanged from `main`**, so the shipped UI tests keep their handles.

The one substantive substitution is in `primaryCommand`, which read
`installed.inventory.package(package.id)` and now reads `entry.installed`. At the catalog call site these
are the **same value by construction**: `entry(for:)` is **unchanged vs `main`** and builds that member
from that exact lookup. Apply flags this as a genuine simplification rather than a no-op (deviation 4),
and that is the right characterisation — the new shape makes it impossible for the command line to
disagree with the buttons above it.

Exactly **one** visibility relaxation: `actionsSection`. `primaryCommand` stays `private`, and everything
the section calls stays `private` because those calls are in the same file.

---

### Non-vacuity — four reversible mutations, none of them apply's

Apply used "re-add `MutationMenu`" and a local `Button("Reinstall")`. I used four different probes. Each
applied, run, restored with `shasum -a 256` matching the pre-mutation digest; `git status --porcelain`
printed nothing after each. Suite-level `-only-testing:` filters throughout.

| # | Mutation | Expected | Observed |
|---|---|---|---|
| **MV** | reword a verb **inside** the shared section: `"Pin version"` → `"Pin"` | the exactly-once literal scan must bite | ❌ `theReceiptPaneOffersTheCatalogPanesActionsSection` only; other 6 passed |
| **MW** | move the Actions call **above** the pane's footer | the placement clause must bite | ❌ same single test; other 6 passed |
| **MU** | re-privatise `actionsSection` | the relaxation must be necessary | ❌ **compile error** — `'actionsSection' is inaccessible due to 'private' protection level` |
| **MS/MT** (round 9, re-confirmed) | tap-surface selection gates | still enforced | ✅ `TapSearchCompositionTests` green on the shipped tree |

**MV and MW** are clean assertion proofs. **MU** is a *necessity* proof rather than an assertion proof and
I record it as such: it demonstrates that the two extension panes genuinely cannot reach a file-private
declaration — which is DD-24's whole justification — while the test's
`contains("private func actionsSection") == false` additionally guards against a silent re-privatisation.

---

### Build & Tests Execution — re-executed at `5d8f659`

**Build**: ✅ `** BUILD SUCCEEDED **`, exit 0.

| Runner | Exact result | Exit | Output sha256 |
|---|---|---|---|
| `xcodebuild test … -only-testing:cellarTests` (run 1) | `** TEST SUCCEEDED **` — **261 distinct ids**, 0 failed | 0 | `1e854542…01c8` |
| `xcodebuild test … -only-testing:cellarTests` (run 2) | `** TEST SUCCEEDED **` — **261 distinct ids**, 0 failed | 0 | `3fd78d0c…4bba` |
| `swift test --package-path Packages/CellarCore` (**clean run**) | **1,879 tests / 218 suites passed, 1 known issue** | 0 | `ac4a8da9…3a5c` |
| `xcodebuild build … -scheme cellar` | `** BUILD SUCCEEDED **` | 0 | `3767258f…4f05` |
| `swift test -c release … --filter 'TapPackageSearchTests'` | **36 tests / 1 suite passed**, latency rows green | 0 | `6db43a16…2a68` |

Latency holds under the 8 ms ceiling for the **ninth** consecutive round.

#### A CellarCore run failed, and I identified it rather than re-running until green

My **first** `swift test` exited **1**: *"1879 tests in 218 suites failed … with 2 issues (including 1
known issue)"*. The failure is:

```
CatalogFootprintTests.swift:71:9: Expectation failed: (widened.residentBytes → -125015552) > 0
```

That assertion is a **sanity check on the measurement itself**, not on any behaviour: `residentBytes` is
a resident-memory delta between two samples, and a negative value is physically impossible as a
footprint — it means the process's resident set was reclaimed between the baseline and the widened
sample. Evidence that it is not ours:

- `Packages/CellarCore/Sources/Catalog/` and `Packages/CellarCore/Tests/CatalogTests/` are both
  **zero-diff** on this branch — the change touches neither the test nor its subject.
- Re-running that suite alone: **2 tests passed**, exit 0.
- Re-running the whole CellarCore suite with **no concurrent `xcodebuild`**: **1,879 / 218 passed**,
  exit 0.

The cause was my own method: I had run two full `xcodebuild test` passes and a build in the same job,
and the memory pressure from that is exactly the reclaim condition this measurement cannot survive. The
clean run is the authoritative evidence; the failed run is reported rather than discarded. This is a
**third** distinct flake identity for this branch, after `OperationCenterCancelTests:183` and
`MutationRefreshReceiptTests:214`, and it is a candidate identity for the unidentified transient apply
records at its own phase 0⁷ (deviation 5) — though I have no evidence the two are the same, and I do not
claim it. Recorded as **S12**.

#### Distinct ids — 261, by three methods

Run 1: 260 clean + 1 dropped = **261**. Run 2: 260 + 1 = **261**. Union of the two clean sets: **261**.
Against round 9's union the delta is exactly one rename in and one out —
`theReceiptPaneOffersTheSameVerbsAsTheRow()` → `theReceiptPaneOffersTheCatalogPanesActionsSection()` —
so the count is unchanged at 261, matching apply's ±0. Progression: **257 → 258 → 259 → 260 → 261 → 261
→ 261 → 261**.

---

### Spec Compliance Matrix

**55 scenarios across 5 requirement blocks** — the totals grow this round because a **new capability**
joins the delta set (`rg -c '^### Requirement:'` → **5**, `rg -c '^#### Scenario:'` → **55**):

| Capability | Requirements | Scenarios |
|---|---|---|
| `package-search` (PS8, ADDED) | 1 | 22 |
| `package-detail` (PD6, MODIFIED) | 1 | 6 |
| `tap-management` (TM5, TM11, MODIFIED) | 2 | 15 |
| **`installed-inventory` (II15, MODIFIED — new this round)** | **1** | **12** |

| Scenario | Test | Result |
|---|---|---|
| **II15: the surface offers the catalog pane's Actions section and no trust control** (replaced) | `ReceiptDetailCompositionTests > theReceiptPaneOffersTheCatalogPanesActionsSection` — call pinned **with its closing parenthesis**, placement by range comparison, `EmptyView()` header, `MutationMenu(` absent, 7 verb literals absent here and **exactly once** in the brace-matched section, plus the section's trust-freedom | ✅ COMPLIANT — **MV**, **MW** |
| **PS8: the pane's actions clause** (amended) | `TapSearchCompositionTests` item amended; suite green | ✅ COMPLIANT |
| II15's other 11 | verbatim from the promoted spec; shipped suites green | ✅ COMPLIANT |
| The other 42 | unchanged and green | ✅ COMPLIANT |

The new test's shape deserves note: it extracts the section by **brace matching** so that claims about
"the section" are scoped to the section — `PackageDetailView.swift` legitimately carries a trust marker
and a catalog type elsewhere, and a whole-file sweep would convict the section of both. And its verb
literals are complete Swift literals with the rationale recorded: `Uninstall` is a prefix of
`Uninstall and Zap…`, and `Install` is a substring of `Installed as`, so a bare substring scan would
produce both a false match and a false duplicate.

**Compliance summary**: **55/55 compliant, 0 partial, 0 untested, 0 failing.**

---

### Invariants — re-run at `5d8f659`

| Path | Result |
|---|---|
| `cellar/Browse/BrowseView.swift` | ✅ **byte-identical to `main`** — tenth round running |
| `cellar/Activity/MutationMenu.swift` | ✅ ZERO-DIFF — the menu was moved off two panes, never edited |
| `cellar.xcodeproj/project.pbxproj` · `openspec/specs/**` · `cellarUITests/**` | ✅ ZERO-DIFF |
| `PackageSearchIndex.swift` · `MutationCommand.swift` · `TapCommand.swift` · `TapProjection.swift` | ✅ ZERO-DIFF |
| `Packages/CellarCore/Sources/Catalog/**` · `Tests/CatalogTests/**` | ✅ ZERO-DIFF |
| `cellar/Browse/PackageDetailView.swift` | **+55/−18** vs `main` — round 6's branch hunks, this round's refactor, one relaxed `private` |

All seven `detail-action-*` accessibility identifiers are unchanged from `main`.

---

### Completeness

| Metric | Value |
|--------|-------|
| Task checkboxes total | 262 |
| Complete | **260** |
| Incomplete | **2** — `6.7` (round 1, **VOID**) and `6′.7` (open the PR) |

Round 8 added 26 boxes and completed all 26 (234 + 26 = 260).

---

### Round-8 deviations, judged

| # | Deviation | Judgment |
|---|---|---|
| 1 | **A `MODIFIED II15` delta was required on a reading the brief did not spell out** | **ACCEPT, and this is the round's most important call.** II15 names neither `MutationMenu` nor the header slot, so "no delta needed" was a reachable and wrong conclusion. What it pins is the verbs' **source**, and that is what changed — with the verb sets differing too. Apply recorded the wrong reading explicitly so the next reader does not re-derive it. |
| 2 | **The RED was genuine, not mutation-based — a change from rounds 3–7** | **ACCEPT.** Guards written and run before any production edit, failing on production that did not exist; the two mutations were then run as well, because a genuine RED proves the row bites on *absence* while mutations prove it bites on reintroduction. Both reported. The strongest evidence shape used on this branch so far. |
| 3 | **WU29 shipped as two commits; the intermediate one is green on its own terms** | **ACCEPT.** At `d1781a7` the panes still hang the menu and the guard rows were uncommitted, and the app suite passes. Test-first authoring and commit order are independent, and the record says which is which. |
| 4 | **`primaryCommand`'s source of truth narrowed** | **ACCEPT — and I verified the equivalence rather than taking it.** `entry(for:)` is unchanged vs `main` and builds `installed` from exactly the lookup `primaryCommand` used to perform, so the catalog pane's behaviour is preserved; and the new shape means the command line cannot disagree with the buttons for an entry built elsewhere. |
| 5 | **One transient CellarCore failure reported unidentified** | **ACCEPT as reported.** I hit one too and identified it (`CatalogFootprintTests:71`); I cannot show they are the same, and do not claim it. See **S12**. |
| 6 | **`specs/README.md`'s "activated, not changed" section was stale the moment the delta was written** | **ACCEPT.** II7 and II8 remain activation-only; II15 no longer is, and the section says so. Catching a summary that stopped being true in the same commit that falsified it is the discipline earlier rounds had to learn twice. |

**Six accepted, zero rejected.**

---

### Commit hygiene and branch size

- **51 commits**, all Conventional Commits, **no AI attribution**.
- Round 8's five are correctly ordered and correctly typed — notably `refactor(browse):` for the
  behaviour-preserving extraction, distinct from the `feat(browse):` that changes the panes.
- `git diff --shortstat main...HEAD` → **33 files, +10,511/−93 = 10,604 authored lines**, matching
  apply's figure exactly.
- Working tree clean at start; only this report modified at the end.

---

### Issues Found

**CRITICAL**: None. **Blockers**: None.

**WARNING** (3):

- **W1 — one task is open: `6′.7`, "Delivery — one PR".** Deferred again by instruction. The drafted body
  needs the final figures — **10,604** lines, **261** distinct ids — and a statement that both
  tap-backed panes now present the catalog pane's Actions section.
  **Remediation**: open the PR, then tick `6′.7`. No code changes.

- **W2 — the latency scenario is not exercised by the spec's declared `unit` runner.** Both rows are
  `.enabled(if: isRelease)` and report **skipped** under `swift test`; covered only by the release
  runner, which this session ran. Mirrors the shipped PS6 precedent.

- **W3 — the exact latency figures remain unreproducible**, emitted only inside the `#expect` failure
  message. The binding clause — both turns under **8 ms** — is confirmed for the ninth round.

**SUGGESTION** (12):

**S1** tautological assertion in `TapPackageSearchTests.swift` · **S2** `AppSection.tapSearch.title` is
unreachable and DD-14 wrongly calls it spec-pinned · **S3** PS8 sc17's zero-diff half has no shipped
enforcement, hand-verified **ten** rounds; a CI step would end the manual check · **S4** correct the
design's wiring table to ten sites · **S5** DD-17 says "the four empty states" are pinned where the spec
pins two · **S6** non-building intermediate commits in rounds 2–3 only · **S7** the branch-size figure
moves with the verify report and has moved both up and down; state the convention once at archive ·
**S8** rename drift in `design.md`/`tasks.md`, now four tests including
`theReceiptPaneOffersTheSameVerbsAsTheRow` · **S9** round-3 deviation 3's "names no trust concept" is
loose · **S10** record the distinct-id rule at archive: **membership**, plus the **two-run union** ·
**S11** the round-6 ledger arithmetic still does not foot (25 declared, +32 measured) · **S12 (new)**
`CatalogFootprintTests` measures a resident-memory delta and cannot survive concurrent `xcodebuild`
load; do not co-schedule `swift test` with `xcodebuild` runs, and record the identity so the next
transient is recognised rather than re-investigated.

---

### Verdict

**PASS WITH WARNINGS.** 0 blockers, 0 CRITICAL, 3 WARNING, 12 SUGGESTION, requirements **5/5**,
scenarios **55/55**.

The round's substance is a consolidation rather than a new capability: two detail panes stop hanging the
list row's menu in their header and call the catalog pane's own Actions section instead. What makes it
verifiable is the refactor underneath — `actionsSection` rebuilt to take a `PackageEntry` and relaxed to
internal, which is the minimum that makes "the same section" a claim about **one declaration reached from
two places** rather than about two things that look alike. I confirmed the catalog pane is behaviour-
preserved down to the one substitution that could have hidden a change, and that every accessibility
identifier survived.

The judgment I most expected to have to argue with — whether a `MODIFIED II15` delta was needed at all —
apply got right, and for the right reason: II15 pins the verbs' *source*, not their spelling, so changing
the source contradicts it. I checked the delta against the promoted spec directly and found 11 of 12
scenarios verbatim with the prose edit confined to that one clause and its provenance line. My own first
count said 10, and that was my extraction artefact, not apply's error.

Four mutations of my own hold the new guards: two clean assertion proofs on the verb literals and the
section's placement, and one compile-level demonstration that the visibility relaxation is necessary
rather than convenient.

One runner failed and I did not re-run until it went green. `CatalogFootprintTests` asserts its own
measurement is positive; under the memory pressure of my concurrently-scheduled `xcodebuild` runs it went
negative, which is impossible as a footprint and diagnostic of reclaim. The suite alone passes, the full
suite unloaded passes, and the branch touches neither the test nor its subject. The clean run is the
evidence; the failure is reported with its identity, which is one more than the branch had before.

**`m11-tap-search` is archive-ready.**
