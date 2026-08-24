# Apply progress: `m9-per-package-trust`

**Mode**: Strict TDD (`strict_tdd: true`, `openspec/config.yaml:38`). No fallback to standard mode.
**Artifact store**: hybrid (this file + Engram `sdd/m9-per-package-trust/apply-progress`, project `swiftui_cellar`).
**Delivery**: **single PR with `size:exception` recorded** (maintainer decision, Engram obs `#7768`).
No chain strategy applies; WU1–WU7 land on one branch, `feat/m9-per-package-trust`.
**Batch**: round 1 (WU1–WU7), **discharge round 1** (the two evidence gaps `verify-report.md` named),
and **discharge round 2** (the spec amendment the live ME2 run forced). See both sections below.

**78 / 85 tasks complete** (mechanical checkbox count; an earlier prose tally said 79/86). The seven that remain are not apply work: 8.7 (open the PR — the
orchestrator's) and 10.1–10.6 (archive-phase promotion, whose obligations are recorded below so
`sdd-archive` does not re-derive them). ME2 is **executed and discharged** (round 2).

## Baseline (task 0.1, measured — not inherited)

| Suite | Command | Result |
|---|---|---|
| Core | `swift test --package-path Packages/CellarCore` | **1,793 tests / 210 suites, 0 failures, 1 known issue** |
| App | `xcodebuild test … -only-testing:cellarTests` | **247 passing test results, TEST SUCCEEDED** |

The single known issue is shipped and pre-existing (`OperationCenterCancelTests.swift:183`,
`withKnownIssue`). One earlier baseline run reported a second, transient issue that did not reproduce
on re-run; it is recorded as an observation, not a defect of this change.

## Final results (tasks 8.1–8.3)

| Suite | Result | Delta vs baseline |
|---|---|---|
| Core | **1,824 tests / 215 suites, 0 failures, 1 known issue** | **+31 tests, +5 suites** |
| App (`cellarTests`) | **248 passing test results, TEST SUCCEEDED** | **+1** |
| `cellarUITests/PerPackageTrustUITests` | **TEST SUCCEEDED** | new |
| `xcodebuild build` | **BUILD SUCCEEDED** | — |

## Work Unit Evidence

| Unit | Focused command + exact result | Runtime harness + result | Rollback boundary |
|---|---|---|---|
| **WU1** artifacts | N/A — artifacts only | N/A — no behaviour changes | Revert `28f4fbf`; the tree returns to `main` |
| **WU2** read | `--filter 'TrustGrantDecodeTests\|TrustGrantSourceTests'` → **6 tests / 2 suites passed** | N/A — pure decode over the verbatim obs `#7764` payload; the live read is ME1 below | Delete `TrustGrantWire.swift` + `TrustGrantPayloadSource.swift`; nothing else referenced them |
| **WU3** store + refresh | `--filter 'TrustGrantStoreTests\|TrustGrantRefreshTests\|MutationRefreshReceiptTests\|TrustGrantSourceTests\|TrustGrantDecodeTests'` → **21 tests / 5 suites passed** | `xcodebuild build …` → **BUILD SUCCEEDED** with the default-`nil` `grants:` parameter | Delete `TrustGrantStore.swift`, revert the coordinator's one parameter |
| **WU4** attribution + accounting | `--filter 'TapProjectionTests\|TrustGrantAccountingTests\|TapShippingProofTests'` → **34 tests / 3 suites passed**; full core suite **1,820 / 215, 0 failures** | N/A — pure, total functions over synthesised values | Revert the `TapProjection.swift` additions; `trust(for:)` and `packageSummary(for:)` are untouched by construction |
| **WU5** guards | `--filter 'MutationCommandTests\|TapShippingProofTests'` → **30 tests / 2 suites passed** | N/A — source-scanning and enumeration absences | Revert the two ban-list tokens and the three new cases; C2 never moved |
| **WU6** surfaces + DI | `--filter 'TapShippingProofTests'` → **9 tests / 1 suite passed**; `-only-testing:cellarTests/PerPackageTrustCompositionTests` → **TEST SUCCEEDED** | `-only-testing:cellarUITests/PerPackageTrustUITests` → **TEST SUCCEEDED** (three launches, one per report state) | Revert the view commit; the stores stay, render nothing, every shipped surface is byte-unchanged |
| **WU7** doc sweep | N/A — prose; `git diff main -- README.md` is prose only | N/A | Revert one prose commit; the canonical three-line install block is byte-identical |

## TDD Cycle Evidence

RED was proved by execution for every behavioural task. "RED by construction" appears once, for the
XCUITest, and is stated rather than claimed as an executed failure.

| Task | Test file | Layer | Safety net | RED | GREEN | TRIANGULATE | REFACTOR |
|---|---|---|---|---|---|---|---|
| 2.1 | `TrustGrantDecodeTests.swift` | Unit | N/A (new) | ✅ `cannot find 'TrustGrantDecoder' in scope` | ✅ passed | ✅ verbatim payload + a sparse payload | ➖ none needed |
| 2.2 | `TrustGrantDecodeTests.swift` | Unit | N/A (new) | ✅ `cannot find 'TrustGrantError' in scope` | ✅ passed | ✅ 6 failure shapes + the reported-empty case | ➖ |
| 2.3 | `TrustGrantDecodeTests.swift` | Unit | N/A (new) | ✅ type absent | ✅ passed | ✅ 4 empty ledgers × 5 single-entry ledgers | ➖ |
| 2.4 | `TrustGrantDecodeTests.swift` | Unit | N/A (new) | ✅ type absent | ✅ passed | ✅ unmodelled list key, scalar key, declared-vs-absent `commands` | ➖ |
| 2.5 | `TrustGrantSourceTests.swift` | Unit | N/A (new) | ✅ `cannot find 'BrewTrustGrantPayloadSource'` | ✅ passed | ✅ argv value + spawned spec + source-literal shape | ➖ |
| 2.6 | `TrustGrantSourceTests.swift` | Unit | N/A (new) | ✅ files absent | ✅ passed | ✅ happy path and the unknown-command failure path | ✅ glob widened in WU3 to cover the store |
| 3.1 | `TrustGrantStoreTests.swift` | Unit | N/A (new) | ✅ `cannot find 'TrustGrantStore' in scope` | ✅ passed | ✅ coalescing + `invalidate()` defeating it | ➖ |
| 3.2 | `TrustGrantStoreTests.swift` | Unit | N/A (new) | ✅ store absent | ✅ passed | ✅ last-good retention **and** a first-ever failure | ➖ |
| 3.3 | `TrustGrantStoreTests.swift` | Unit | N/A (new) | ✅ store absent | ✅ passed | ➖ single ordering scenario | ➖ |
| 3.4 | `TrustGrantRefreshTests.swift` | Integration | ✅ 1,793/1,793 | ✅ store absent | ✅ passed | ✅ overlap proved by two live processes + argv set | ➖ |
| 3.5 | `TrustGrantRefreshTests.swift` | Integration | ✅ | ✅ store absent | ✅ passed | ✅ two arms: throws, and never answers | ➖ |
| 3.6 | `TrustGrantRefreshTests.swift` | Unit | ✅ | ✅ store absent | ✅ passed | ✅ 17 runtime declarations + the type's own member list | ➖ |
| 3.7 | `MutationRefreshReceiptTests.swift` (shipped, extended) | Integration | ✅ shipped suite green before the edit | ✅ store absent | ✅ passed, 4 terminals × 3 commands | ✅ parameterized over all four terminals | ➖ |
| 4.1 | `TapProjectionTests.swift` | Unit | ✅ | ✅ `TapProjection has no member 'grants'` | ✅ passed | ✅ prefix-only, publication-only, both, URL-shaped × 3 candidate taps | ➖ |
| 4.2 | `TapProjectionTests.swift` | Unit | ✅ | ✅ no member | ✅ passed | ✅ three refusals + one positive anchor | ➖ |
| 4.3 | `TrustGrantAccountingTests.swift` | Unit | N/A (new) | ✅ `no member 'accounting'` | ✅ passed | ✅ the spec's 7-entry fixture, every category asserted | ➖ |
| 4.4 | `TrustGrantAccountingTests.swift` | Unit | N/A (new) | ✅ no member | ✅ passed | ✅ measured payload + a one-namespace ledger + `nehir@rc` | ➖ |
| 4.5 | `TrustGrantAccountingTests.swift` | Unit | N/A (new) | ✅ no member | ✅ passed | ✅ commands-only, declared-empty, absent, unmodelled | ➖ |
| 4.6 | `TapProjectionTests.swift` | Unit | ✅ | ✅ no member | ✅ passed | ✅ plural and singular | ➖ |
| 4.7 | `TapProjectionTests.swift` | Unit | ✅ | ✅ no member | ✅ passed | ✅ three states × the whole rendered string set | ➖ |
| 4.8 | `TapProjectionTests.swift` | Unit | ✅ | ✅ no member | ✅ passed | ✅ two taps + an orphan + an unmatched entry | ➖ |
| 4.9 | `TapProjectionTests.swift` | Unit | ✅ | ✅ `no member 'unattributedSection'` | ✅ passed | ✅ four section states, byte-compared copy | ➖ |
| 4.10 | `TapProjectionTests.swift` | Unit | ✅ | ✅ no member | ✅ passed | ✅ four ledgers, including one naming that exact tap | ➖ |
| 4.11 | `TapShippingProofTests.swift` | Unit | ✅ shipped suite green | ✅ no member | ✅ passed | ✅ five report states, with the count line asserted to vary | ➖ |
| 4.12 | `TapProjectionTests.swift` | Unit | ✅ | ✅ `no member 'grantsIndividually'` | ✅ passed | ✅ 5 refusals + 1 match + 3 no-grant states | ➖ |
| 4.13 | `TapProjectionTests.swift` | Unit | ✅ | ✅ no member | ✅ passed | ✅ 22-field mirror + 6 forbidden field spellings | ➖ |
| 4.14 | `TapProjectionTests.swift` | Unit | ✅ | ✅ no member | ✅ passed | ✅ orphan tap grant **and** unmatched package grant | ➖ |
| 5.1 | `MutationCommandTests.swift` (shipped C1, extended) | Unit | ✅ shipped suite green | ✅ **executed**: 11 coverage failures with the two tokens removed | ✅ passed with them restored | ✅ 11 per-package names checked for coverage | ➖ |
| 5.2 | `MutationCommandTests.swift` | Unit | ✅ | ✅ same RED run | ✅ passed | ✅ 5 grant states × 4 mutation verbs | ➖ |
| 5.3 | `MutationCommandTests.swift` | Unit | ✅ | ✅ same RED run | ✅ passed | ✅ family enumeration + 3 source files × 4 forbidden symbols | ➖ |
| 6.1 | `TapShippingProofTests.swift` | Unit | ✅ | ➖ **absence guard, green on arrival** — it fails only if a control is added; anchored non-vacuously (8 produced strings, 2 exact copies) | ✅ passed | ✅ four entry points invoked | ➖ |
| 6.2 | `TapShippingProofTests.swift` | Unit | ✅ | ✅ **executed**: `PackageDetailView.swift passes judgement on a package: verdict` (my own comment) → reworded | ✅ passed | ✅ 3 report states × 10 negative words, 8 sources × 11 judgement words | ✅ comment reworded |
| 6.3 | `cellarTests/PerPackageTrustCompositionTests.swift` | Integration | N/A (new) | ✅ **executed**: `TEST FAILED` before the views read the projection | ✅ passed | ✅ three views × six structural claims | ➖ |
| 6.4 | `cellarTests/PerPackageTrustCompositionTests.swift` | Integration | N/A (new) | ✅ same RED run | ✅ passed | ✅ installed row **and** withheld-tap row, plus an unmarked triangulation | ➖ |
| 6.5 | `cellarUITests/PerPackageTrustUITests.swift` | E2E | N/A (new) | ➖ **RED by construction** — every identifier it queries (`tap-row-grant-count`, `tap-detail-grant-count`, `tap-grant-section-sentence`) was absent from the app when the file was written | ✅ passed, 3 launches | ✅ granted / reported-empty / unreported | ➖ |
| 7.1–7.2 | — | Doc | N/A | N/A — prose | ✅ `git diff main -- README.md` is prose only | ➖ | ➖ |

### Test summary

- **New tests written**: 16 core (`swift test`), 2 app-unit, 1 XCUITest — plus 2 shipped suites extended
  (`MutationCommandTests` C1 + 2 new cases; `MutationRefreshReceiptTests` + 1 parameterized case).
- **Core suite**: 1,793 → **1,824** (+31 counting parameterized cases), 210 → **215 suites**.
- **App suite**: 247 → **248** passing results. *(Round 1 reported 249; re-measured at 248 in both the
  verify phase and the discharge round below. Nothing regressed — the round-1 number was a miscount.)*
- **Layers**: Unit (core) 16, Integration (core + app) 5, E2E 1.
- **Approval tests**: none — no refactoring task in this change; `TapProjection` gained only additions.
- **Pure functions created**: 5 (`TrustGrantState.reported`, `.settled`, `TapProjection.grants`,
  `.grantsIndividually`, `.accounting`, plus the private `attribute`).

## Binding invariants — verified, not assumed

| Invariant | Verification | Result |
|---|---|---|
| `MutationCommand.swift` 0-line diff | `git diff --stat main -- …/MutationCommand.swift` | **empty** ✅ |
| `BrewMutating.swift`, `TapCommand.swift` untouched | same command | **empty** ✅ |
| `scripts/`, `.github/workflows/`, `project.pbxproj` untouched | same command | **empty** ✅ |
| C2 (`noPackagePositionEverCarriesAQualifiedToken`) byte-identical | `diff` of `main:482-613` against `HEAD:620-751` | **identical, 132 lines** ✅ |
| `MutationCommandTests.swift` diff is one hunk | `git diff main -- … \| rg -c '^@@'` | **1** ✅ |
| C1 ban list gains `TrustGrant` + `grantsIndividually` | `MutationCommandTests.swift:479`, asserted as *coverage* over 11 names | ✅ |
| No new `InvalidationScope` member | `rg 'InvalidationScope(rawValue:'` → 4 members; `noPerPackageInvalidationDomainExists` pins the union at `0b1111` | ✅ |
| No argv element carries ≥2 slashes | C2 unchanged + `theGrantReadIsAConstantArgvWithNoQualifiedToken` | ✅ |
| The read spine's argv is the compile-time constant `["trust", "--json", "v1"]` | asserted by value, by spawned `ProcessSpec`, and by the source declaration line | ✅ |
| Cellar never reads `trust.json` | `noPathReadsATrustFileFromDisk` scans every `TrustGrant*.swift` for 7 disk-access tokens | ✅ |
| `TapProjection.trust(for:)` / `packageSummary(for:)` unchanged | `git diff` on `TapProjection.swift` has **no deleted lines**; `theTapBadgeAndSummaryAreUnchangedByGrants` compares across 5 report states | ✅ |
| `TapManagementAction.allCases` and `staticButtonLabels` unchanged, `Button {` absent | `noNewControlSubmitsAnythingAndTheSurfaceIsDisplayOnly` + `assertBoundedUIControls()` | ✅ |

## Changed lines (task 8.6) — measured, split by bucket

| Bucket | Forecast | Measured | Verdict |
|---|---|---|---|
| Code + tests | 2,736 – 3,312 | **3,266** (3,248 + / 18 −) | inside the band, near the top |
| SDD artifacts | 1,900 – 2,300 | **2,139** (2,139 + / 0 −) | inside the band; the verify report will add ~250–450 |
| **PR total** | 4,636 – 5,612 | **5,405** (5,387 + / 18 −) | **under the 5,612 ceiling**, over the 5,000 budget → **`size:exception` applies as recorded** |

34 files changed. This is the m7 **learning-E** follow-through: the artifact bucket was forecast and
measured separately, with no code-derived correction, and both buckets landed inside their own band.

**One correction to that table, measured after this file was committed.** The forecast's artifact
bucket enumerated the four deltas, `design.md`, `tasks.md`, `proposal.md` and the verify report — it
did **not** include `apply-progress.md`, which is itself an artifact of ~300 lines. Counting it, the
branch stands at **5,709** authored lines (code + tests **3,266**, artifacts **2,443**), i.e. **97
lines over the 5,612 forecast ceiling**, and the whole overshoot is artifact, not code. The code+test
bucket is unchanged and still inside its band. This is information for the next forecast — the
artifact bucket must enumerate `apply-progress.md` and the verify report, not just the planning
artifacts — and it is reported rather than absorbed by trimming evidence to fit a number.

## Commits (one per work unit, conventional, no AI attribution)

| Unit | SHA | Subject |
|---|---|---|
| WU1 | `28f4fbf` | `docs(sdd): record the m9-per-package-trust proposal, spec deltas, design and tasks` |
| WU2 | `ce74d83` | `feat(taps): read the per-package trust report Homebrew already publishes` |
| WU3 | `3055b72` | `feat(taps): refresh the grant report alongside the tap snapshot` |
| WU4 | `3dcc99d` | `feat(taps): attribute per-package grants without ever splitting a token` |
| WU5 | `349480b` | `test(mutations): ban the per-package trust types from the mutation surface` |
| WU6 | `7bf6be9` | `feat(taps): show individual grants on the tap row, the detail and package detail` |
| WU7 | `808171c` | `docs(readme): describe qualified tokens without implying Cellar grants trust` |

Branch `feat/m9-per-package-trust`, off `main` at `e03c58f`. **Not pushed; no PR opened.**

## Files changed

| File | Action | What |
|---|---|---|
| `Packages/CellarCore/Sources/BrewClient/TrustGrantWire.swift` | **New** | `TrustGrantState` (+ `reported`, `settled`, `ledger`, `entryCount`), `TrustGrantLedger` (+ `unmodelled`, `declaredNamespaces`, `entryCount`), `TrustGrantError`, `TrustGrantDecoder` with a dynamic-key container |
| `.../BrewClient/TrustGrantPayloadSource.swift` | **New** | `TrustGrantSourcing`, `TrustGrantPayload`, `BrewTrustGrantPayloadSource` with the constant argv |
| `.../BrewClient/TrustGrantStore.swift` | **New** | `TrustGrantLoadState`, `@MainActor @Observable TrustGrantStore` (a `TapStore` clone) |
| `.../BrewClient/TapProjection.swift` | Modified (**additions only**) | `grantMarker`, `TapGrantPresentation`, `grants(for:in:)`, `grantsIndividually(_:publishedBy:in:)`, `accounting(of:taps:)`, `unattributedSection(in:taps:)`, private `attribute`, `UnattributedGrants`, `TrustGrantSection` |
| `.../BrewClient/TapRefreshCoordinator.swift` | Modified | `grants:` parameter (default `nil`); `async let` over both stores; `RefreshResult` decided from `store.state` **before** the grant read is awaited |
| `Tests/BrewClientTests/TrustGrantDecodeTests.swift` | **New** | PT1, PT4 decode |
| `Tests/BrewClientTests/TrustGrantSourceTests.swift` | **New** | PT1 argv + no-disk-read |
| `Tests/BrewClientTests/TrustGrantStoreTests.swift` | **New** | PT2.1–.3 |
| `Tests/BrewClientTests/TrustGrantRefreshTests.swift` | **New** | PT2.4–.6 |
| `Tests/BrewClientTests/TrustGrantAccountingTests.swift` | **New** | PT4.1–.4 |
| `Tests/BrewClientTests/Fakes/TrustGrantFixture.swift` | **New** | the **verbatim** obs `#7764` payload |
| `Tests/BrewClientTests/Fakes/FakeTrustGrantPayloadSource.swift` | **New** | gated doubles for both reads |
| `Tests/BrewClientTests/TapProjectionTests.swift` | Modified | 10 new cases (PT3, PT5, PT6, PT8, PD8) |
| `Tests/BrewClientTests/TapShippingProofTests.swift` | Modified | 3 new cases (D-d, PT7, PT6) |
| `Tests/BrewClientTests/MutationCommandTests.swift` | Modified | **one hunk**: C1 ban list + 2 new cases. C2 byte-identical |
| `Tests/BrewClientTests/MutationRefreshReceiptTests.swift` | Modified | 1 new parameterized case + its harness |
| `cellar/cellarApp.swift` | Modified | `TrustGrantStore(source:)`, passed to the coordinator and `ContentView` |
| `cellar/AppTestFixtures.swift` | Modified | three `--ui-testing-m9-per-package-trust*` flags + `AppTestTrustGrantPayloadSource` |
| `cellar/ContentView.swift` | Modified | threads the store to three views |
| `cellar/Taps/TapsListView.swift` | Modified | count line as an added `·` component; the "Other trusted packages" section |
| `cellar/Taps/TapDetailView.swift` | Modified | header count component; `Trusted individually` marker on package rows |
| `cellar/Browse/PackageDetailView.swift` | Modified | `trustGrants` store; marker beside the `Tap` fact; `#Preview` |
| `cellar/Security/SecurityPreviews.swift` | Modified | one line — the shell preview's new argument |
| `cellarTests/PerPackageTrustCompositionTests.swift` | **New** | one-projection + additive-marker composition |
| `cellarUITests/PerPackageTrustUITests.swift` | **New** | count line and section per report state |
| `README.md` | Modified | the qualified-token sweep (prose only) |

## Deviations from the design and the tasks — reported, not absorbed

1. **`TrustGrantLedger.isEmpty` is not package-scoped** (design DD-1 and task 2.8 both say it should
   ignore `taps`). Implemented as "no entry in **any** namespace", because reconciliation **B4** makes
   an *orphan tap grant* its own accounted **and shown** category (PT4 :219-244, PT8 :435-441). With
   the package-scoped rule, a ledger carrying only a `taps` entry collapses to `.noGrants` and that
   decoded entry disappears — the one thing PT4 forbids outright. The package-scoped notion survives
   where it belongs: as a count of zero *attributed* grants, which renders no count line (DD-7).
   Documented in the source with this reasoning.
2. **`TrustGrantSection` exposes `sentence` / `title` / `groups` rather than being switched over in the
   views.** Forced by a shipped guard: `TapShippingProofTests.listRowAndDetailHeaderReadOneTrustProjection`
   bans `case .unreported` in `TapsListView.swift` and `TapDetailView.swift`. Exposing the copy as
   values is also what keeps the exact strings (B1–B3) in the projection where PT6 puts them.
3. **The README sweep keeps the literal `juancasanueva/cellar/home-cellar`.** The first draft deleted
   it; that turned the shipped `CaskZapInventoryTests.theReadmeCarriesBothBrewCommandsAsWholeLines`
   red (it pins `readme.contains("juancasanueva/cellar/home-cellar")`, from `m8-bundle-rename`). WU5's
   C1 edit is the change's **one** deliberate shipped-guard edit, so the guard was left alone and the
   prose reframed instead: the token is now named as the shape Cellar never builds, not as the form to
   reach for. The canonical three-line install block is byte-identical.
4. **`package-mutation` delta arithmetic is off by one in two places** (spec defect to report, per task
   1.2 — **not** patched here). The delta header says "10 scenarios replace the 7", and its
   verification table says 8 `unit` + 2 `manual-evidence`. Counted: the shipped PM10 has **8**
   scenarios and the delta has **11** (9 `unit` + 2 `manual-evidence`). The stated end state is
   nevertheless correct: 60 − 8 + 11 = **63 scenarios / 10 requirements**. The other three deltas'
   arithmetic verified exactly: package-trust 8 req / 32 sc; tap-management 55 − 5 + 7 = 57 sc / 13
   req; package-detail 26 + 4 = 30 sc / 8 req.
5. **Design anchors all held** (task 0.2): `TapProjection.swift` :121/:166/:208/:219, `TapStore.swift`
   :26/:55, `TapRefreshCoordinator.swift` :11/:46, `MutationCommandTests.swift` :471/:501,
   `TapsListView.swift:52`, `TapDetailView.swift` :57-65/:149, `PackageDetailView.swift:557`,
   `README.md` :44-47. No anchor moved.
6. **Task 6.1 was green on arrival.** It is an absence guard over a surface this change deliberately
   gives no control; there is no honest RED for "no control exists" other than adding one. It is
   anchored non-vacuously (8 produced strings, two exact copies) and stated as such rather than
   claimed as a RED→GREEN cycle.

## The five binding reconciliations, as implemented (B1–B5)

| # | Where it landed |
|---|---|
| **B1** | `TrustGrantSection.noneRecorded.sentence == "Homebrew records no packages trusted individually."` — it renders a sentence, not nothing. `TapsListView` renders the section whenever `sentence != nil \|\| !groups.isEmpty` |
| **B2** | `.unreported.sentence == "This Homebrew does not report per-package trust."` — byte-compared in `theSectionCopyIsExactAndDistinguishesTheStates` |
| **B3** | `.unattributed(_).sentence` with a non-empty orphan set is exactly `"Homebrew still records these grants. Cellar shows them; it does not remove them."` |
| **B4** | `UnattributedGrants { orphanTapGrants, unmatchedFormulae, unmatchedCasks, other, attributed, excluded }` with `total == attributed + excluded + surfacedCount`, asserted equal to `ledger.entryCount` |
| **B5** | `TrustGrantLedger.unmodelled: [String: [String]]` filled by a dynamic-key container; its entries are counted as **other**; `declaredNamespaces` keeps present-and-empty distinguishable from absent |

## Manual evidence (Phase 9)

**ME1 (task 9.1, PT4.5) — CAPTURED on the maintainer's Mac, 2026-08-24.**

```
$ shasum -a 256 ~/.homebrew/trust.json   # before
63ed7c9db32e4912806350e82ff10feed843c0485e67ec465425e5738a233eee   553 bytes  mtime=1787510792
$ brew trust --json v1                   # run 1, exit 0
$ brew trust --json v1                   # run 2, exit 0
$ shasum -a 256 ~/.homebrew/trust.json   # after both
63ed7c9db32e4912806350e82ff10feed843c0485e67ec465425e5738a233eee   553 bytes  mtime=1787510792
```

Payload (both runs byte-identical to each other and to the apply fixture):

```json
{
  "taps": ["juancasanueva/cellar"],
  "formulae": ["gentleman-programming/tap/engram","gentleman-programming/tap/gentle-ai",
               "gentleman-programming/tap/gentleman-dots","gentleman-programming/tap/gga",
               "https://github.com/cloudmanic/spice-edit/spice-edit","jnsahaj/lumen/lumen",
               "kitlangton/tap/ghui","letstri/tap/druk","modem-dev/tap/hunk"],
  "casks": ["gentleman-programming/tap/engram","guria/tap/nehir","guria/tap/nehir@rc",
            "nkzw-tech/tap/codiff"],
  "commands": []
}
```

- Namespaces: `taps` 1 · `formulae` 9 · `casks` 4 · `commands` 0 → **14 entries**.
- Cellar's accounting: `theVerbatimHomebrewPayloadDecodesEveryNamespace` asserts
  `ledger.entryCount == 14` over these exact bytes, and
  `theSameIdentifierInTwoNamespacesIsTwoEntries` asserts `accounting.total == ledger.entryCount`.
  **The two counts are equal.**
- The ledger is **byte-identical before and after two reads**, so the read granted nothing. Design
  Open Question 2 stays cleared by measurement (obs `#7764`), now re-confirmed.
- **Open Question 3, answered opportunistically**: every entry in this payload is qualified — an
  unqualified entry remains theoretical. No extra section sentence is needed, and no code change.

**ME2 (task 9.2, PT8.3 + PT8.4) — EXECUTED by the maintainer, 2026-08-24** (see "Discharge round 2"
below). It was not executed *during apply*, because untapping a real tap on the maintainer's machine is
a mutation this run must not perform unasked. When it ran, **its premise proved false** and the
scenario was amended to the measurement. The behaviour the amended PT8.3 observes is still pinned by
`aGrantForAnUninstalledTapIsSurfacedNotDropped` and `theAccountingPartitionsTheDecodedSet`.

**Task 9.3** — `package-mutation` PM10's two `manual-evidence` scenarios (formula refusal wording; a
real refusal rendering the typed outcome) were captured in `m7-tap-trust` Phase 9, survive
byte-identical in this delta, and were **not re-executed** here.

**Task 9.4** — the probe blocking design Open Question 2 is **already CLEARED** by measurement (obs
`#7764`, 2026-08-24) and MUST NOT be re-run as a gate.

## Archive obligations, recorded now (Phase 10 — deliberately left unchecked; they are archive work)

- **10.1** `package-trust` is **established** by this change: create `openspec/specs/package-trust/spec.md`,
  promote the eight ADDED requirements in order as **PT1–PT8**, add the file header, the
  `## Requirements` wrapper and a `## Provenance` section recording this change, its binding decisions,
  and what each rejected: per-package grant/revoke controls; extending `tap-info`; a dedicated
  invalidation domain; any negative per-package copy.
- **10.2** Promote as **whole-block replacements**: TM12 → `tap-management` (13 req / **57** sc, TM1–TM11
  and TM13 untouched); PM10 → `package-mutation` (10 req / **63** sc, PM1–PM9 untouched); PD8 appended
  after PD7 in `package-detail` (8 req / **30** sc, PD1–PD7 byte-identical). See deviation 4 above:
  the delta's own scenario arithmetic is off by one, the end-state totals are right.
- **10.3** Record: the argv prohibition was **reaffirmed, not relaxed** (C2 byte-identical; the C1 ban
  list extended — the change's one deliberate guard edit); **DD-3** adds **no new invalidation domain**;
  **PD8 is expected to render nothing** on today's shipped surface (PD6), existing so the bare-name
  hazard is impossible to ship.
- **10.4** Record the measured payload facts PT4 rests on (obs `#7764`, re-confirmed by ME1 above):
  namespaces **not disjoint** (`gentleman-programming/tap/engram` in both `formulae` and `casks`), `@`
  in a package name (`guria/tap/nehir@rc`), a URL-shaped `formulae` entry, present-and-empty
  namespaces, and a side-effect-free read. The captured payload **is** the fixture, at
  `Tests/BrewClientTests/Fakes/TrustGrantFixture.swift`.
- **10.5** Record the deferrals: per-package grant/revoke controls stay out of scope until the
  `brew untrust --formula|--cask <qualified>` probe answers whether the revocation itself registers a
  grant through `explicitly_allowed?` before removing it; and `BrewfileDiff.isPresent` (**R15**) is
  deliberately not in this change.
- **10.6** Record **B1–B5** as design-vs-spec deviations resolved in the spec's favour, plus deviation 1
  above (`isEmpty` is not package-scoped), so a future reader does not mistake `design.md`'s superseded
  copy and three-category accounting for the shipped shape.

## Discharge round 1 (verify WARNING-1, -2, -3, -4 — maintainer-authorized `sdd-apply` unit)

Round-1 verification returned `fail` on **evidence completeness only**: 0 blockers, 0 CRITICAL, both
commands exit 0. This unit discharges the two items it named as actionable, and nothing else. It is
**not** a defect fix — there was no defect to fix.

| Item | What was done | Result |
|---|---|---|
| **WARNING-1** — PT1.2 covered by no task | Added `TapProjectionTests · aPackagesPerPackageStateReadsAsThreeDistinctAnswers` (tasks 11.1) | ✅ green, non-vacuity proven by two reverted mutations |
| **WARNING-2** — `package-mutation` delta header arithmetic | Corrected 7→**8** shipped, 10→**11** delta, class table 8→**9** `unit`, "seven"→"**eight**" surviving (task 11.2) | ✅ no scenario content changed; end state 63/10 was already right and is unchanged |
| **WARNING-3** — downstream totals | `tasks.md` inputs line 53→**54** (32 / 7 / **11** / 4) and the scenario map's `package-mutation` count 10→**11** | ✅ authoritative counts now agree with the delta files |
| **WARNING-4** — app-unit count | Re-measured; the tables above corrected 249→**248** | ✅ reconciled; nothing regressed |
| **WARNING-5** — ME2 (PT8.3) | Untouched. Task 9.2 / 11.4 stay open for the maintainer's Mac | ➖ out of this unit's scope |

### PT1.2 — why there is no RED, and what stands in for it

The scenario requires a *package's* per-package state to be three-valued with "no two of the three
compare equal". The shipped package-level API answers with a `Bool`
(`TapProjection.grantsIndividually(_:publishedBy:in:)`); the third value lives one level up, in the
`TrustGrantState` that answer is read against. That is the shape the design chose deliberately — PT6
:383-388 requires `noGrantRecorded` and `unreported` to contribute *nothing* for a package, so the two
are indistinguishable in rendering by design — and it is already correct. The only honest RED would be
to invent a package-level three-valued API, which is production surface this focused unit is not
authorized to add and which the spec does not require beyond the model it already has.

So the test follows the **task 6.1 house precedent**: green on arrival, disclosed as such, and anchored
so it cannot pass vacuously.

- **Positively anchored** — the fixture ledger really carries `acme/tools/widget` and really does not
  carry a formula, asserted before the three answers are read.
- **Mutation-proven** — production was temporarily broken twice and the test went red each time, then
  restored byte-identical (`git diff -- Packages/CellarCore/Sources` → empty):
  - `grantsIndividually` forced to always answer `false` → **2 failures**
  - `TrustGrantState.entryCount` for `.unreported` forced from `nil` to `0` → **1 failure**
- **Both halves pinned** — the test asserts that the `Bool` alone cannot separate the last two answers
  and the report alone cannot separate the first two, so dropping either half collapses the triple into
  the pair PT1 :62-73 forbids.

### Discharge round TDD Cycle Evidence

| Task | Test file | Layer | Safety net | RED | GREEN | TRIANGULATE | REFACTOR |
|---|---|---|---|---|---|---|---|
| 11.1 | `TapProjectionTests.swift` | Unit | ✅ 4/4 (`TrustGrantDecodeTests`) | ➖ **no honest RED exists** — behaviour already correct; substituted by 2 reverted production mutations, each observed red | ✅ passed | ✅ three staged answers + both single-half collapses | ➖ none needed |
| 11.2 | — | Doc | N/A — spec/task prose | N/A | ✅ counts re-derived independently from the delta and shipped spec files | ➖ | ➖ |

### Discharge round Work Unit Evidence

| Evidence | Value |
|---|---|
| Focused command | `swift test --package-path Packages/CellarCore --filter 'aPackagesPerPackageStateReadsAsThreeDistinctAnswers'` → **1 test / 1 suite passed** |
| Full core suite | `swift test --package-path Packages/CellarCore` → **1,825 tests / 215 suites, exit 0**, 1 known issue (pre-existing) — **+1 vs round 1's 1,824** |
| App-unit suite | `xcodebuild test … -only-testing:cellarTests` → **248 passing results, `** TEST SUCCEEDED **`, exit 0** |
| Runtime harness | N/A — the added test is a pure, total function over synthesised values; no runtime boundary exists for it. The capability's runtime paths were already exercised in WU3/WU6 and are untouched here |
| Rollback boundary | Revert the one test hunk in `TapProjectionTests.swift` and the header numbers in the `package-mutation` delta. **No production file was changed**, so nothing else can regress |

### Binding invariants re-confirmed after the discharge

`git diff --stat -- Packages/CellarCore/Sources` is **empty**: `MutationCommand.swift` stays a 0-line
diff, C2 stays byte-identical, `InvalidationScope` still has four members, and no shipped guard moved.
The whole discharge diff is one test hunk plus artifact prose.

## Discharge round 2 (ME2 executed; PT8 amended to measured reality)

The maintainer ran ME2 live on 2026-08-24 (Engram `#7775`; transcript at `evidence/me2-transcript.txt`).
**It falsified PT8.3's premise**, so the spec was amended to the measurement — the measurement is not
negotiable and the implementation is not at fault: Cellar rendered exactly what the report said and
refreshed the section through the `.taps` ride, as DD-3/DD-4 designed. **No code, no test and no other
delta was touched.** The edits are itemised in `tasks.md` Phase 12 and are not restated here.

Measured: `brew untrust <tap>` **cascades** to that tap's per-package grants, so an in-Cellar untap
leaves **no** orphan; the orphan is evidenced instead by `nkzw-tech/tap/codiff`, untapped **outside**
Cellar. The consequence is a **strengthening** — the cascade closes the dormant-grant hole at package
granularity too, better than `m7-tap-trust` recorded.

Core suite unchanged (**1,825 / 215, exit 0**); app suite not re-run because nothing executable moved.
Rollback: revert the PT8 block and the header paragraph. **Version note** — the transcript records
Homebrew **6.0.18-182-ga963211** (auto-updated to 6.0.19 during restoration); the brief and obs `#7775`
say 6.0.15, so the spec records the transcript's 6.0.18.

## Remaining

- [ ] **8.7** Open the PR — the orchestrator's step. The body must state: (a) this change **grants and
      revokes nothing**; (b) **corrected by measurement** — TM7's untap flow *does* remove that tap's
      per-package grants (the untrust cascades), so only an untap performed **outside** Cellar leaves an
      orphan, and Cellar shows those without claiming to close them; (c) on a Homebrew without the
      `trust` verb every surface renders **nothing**, never "0 grants" (R4). Label `size:exception`
      (5,405 authored lines vs the 5,000 budget, inside the 5,612 forecast ceiling).
- [ ] **10.1 – 10.6** archive-phase promotion; obligations recorded above.
