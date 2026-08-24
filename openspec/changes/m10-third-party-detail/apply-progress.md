# Apply progress — `m10-third-party-detail`

Session preflight (cached, forwarded verbatim): `execution_mode=interactive`, `artifact_store=hybrid`
(OpenSpec canonical, Engram topic `sdd/m10-third-party-detail/apply-progress` mirrors),
`delivery_strategy=single-pr`, `chain_strategy=pending`, `review_budget_lines=5000`, `strict_tdd=true`,
`size:exception` **not in use**. RDD disabled — no review lifecycle, no receipts, ordinary repository
policy. One writer, five work units, executed sequentially in one run.

**Branch**: `feat/m10-third-party-detail` (from `main` at `5a0860b`). Not pushed; no PR opened.
**Mode**: Strict TDD (RED → GREEN → REFACTOR), no fallback taken.
**Status**: **51 / 52 tasks complete.** Only `6.7` (open the PR) is open, and only because the launch
brief forbids pushing and opening PRs in this run. Everything 6.7 asks the body to state is drafted
below.

## Commits

| Hash | Subject | Unit |
|---|---|---|
| `38f1f90` | `docs(sdd): record the m10-third-party-detail proposal, spec deltas, design and tasks` | WU1 |
| `1aedbf7` | `refactor(browse): share the detail header helpers across both panes` | WU2 |
| `3d2527e` | `feat(installed): derive a reduced detail from one installed receipt` | WU3 |
| `e3cab43` | `test(installed): pin that a receipt-backed detail never touches the catalog` | WU4 |
| `65a65cb` | `feat(browse): show a receipt-backed detail for packages the catalog does not carry` | WU5 |

No `Co-Authored-By` and no AI attribution on any commit.

## Phase 0 — the measured baseline (task 0.1)

Measured on `main` at `5a0860b`, before any edit. Counted as **distinct test ids**, never a bare
success line.

| Runner | Baseline | After | Delta |
|---|---|---|---|
| `swift test --package-path Packages/CellarCore` | **1,825 tests / 215 suites**, 0 failures, 1 known issue | **1,837 tests / 216 suites**, 0 failures, 1 known issue | **+12**, +1 suite |
| `xcodebuild test … -only-testing:cellarTests` | **239 distinct**, 0 failures | **245 distinct**, 0 failures | **+6** |

The same known issue is present before and after; it is not this change's.

**Measurement gotcha, recorded**: `xcodebuild`'s concurrent stdout truncates the leading characters of
exactly one `Test case '…' passed` line per run, so a naive `sort -u | wc -l` under-counts by one. The
counts above are reconciled against the `' passed on'` line count (249 → 255, **+6**) and against a
set difference of test ids, which showed exactly the six new cases and no removals.

### Anchors confirmed (task 0.2)

Every anchor the design pins was found where it says. `PackageDetailView.swift`: `uncatalogedContent`
:370, `EmptyView()` slot :378, footer :384, `header(id:…)` :396, `versionStory(installed:)` :463,
inline homepage block :569-577, `Updates itself` :579, `fact(_:_:mono:note:)` :586, `sizeOnDisk` :629,
`installedAs` :640. `PerPackageTrustCompositionTests.swift`: sorted-name anchor :30-32,
`PerPackageTrustSources.views()` :186-190. `InstalledModels.swift` :29-97 and `InstalledFixture.swift`
:79-103 as described. **No anchor moved — nothing to report as a deviation.**

### Forecast band collapsed (task 0.4)

`git log --oneline -- openspec/changes/m10-third-party-detail` is **empty** and every artifact was
untracked, so the **1,621 artifact lines are new to this branch**, not already on `main`. The band
collapses to its **high end**. Recorded once, not re-estimated at 6.6.

## TDD Cycle Evidence

| Task | Test file | Layer | Safety net | RED | GREEN | TRIANGULATE | REFACTOR |
|---|---|---|---|---|---|---|---|
| 2.1–2.5 | — (pure refactor) | — | ✅ 239/239 | ➖ **no RED by design** — a visibility relaxation adds no behaviour (tasks.md :157-160) | ✅ 239/239, identical id set | ➖ n/a | ✅ `factLink` extracted, one duplication removed |
| 3.2 | `InstalledDetailProjectionTests.swift` | Unit | N/A (new file) | ✅ `cannot find 'InstalledDetailProjection' in scope` | ✅ passed | ✅ group order + values | ✅ copy helpers extracted |
| 3.3 | same | Unit | N/A | ✅ same | ✅ passed | ✅ formula **and** cask, positions asserted | ✅ |
| 3.4 | same | Unit | N/A | ✅ same | ✅ passed | ✅ both kinds + `Mirror` structural proof | ✅ |
| 3.5 | same | Unit | N/A | ✅ same | ✅ passed | ✅ 3 cases, pairwise distinguishable | ✅ |
| 3.6 | same | Unit | N/A | ✅ same | ✅ passed | ✅ 3 kegs, linked | ✅ |
| 3.7 | same | Unit | N/A | ✅ same | ✅ passed | ✅ 2-keg unlinked **and** 1-keg unlinked | ✅ |
| 3.8 | same | Unit | N/A | ✅ same | ✅ passed | ✅ both link states, 3 pin states | ✅ |
| 3.9 | same | Unit | N/A | ✅ same | ✅ passed | ✅ withheld **vs** reported | ✅ |
| 3.10 | same | Unit | N/A | ✅ same | ✅ passed | ✅ 7 shapes enumerated, absence set complete | ✅ |
| 4.1 | same | Unit | ✅ 1,835/1,835 | ✅ **proved** — source file moved aside, 504 × `cannot find 'InstalledDetailProjection' in scope` | ✅ passed, **zero production lines** | ✅ positive anchor: `curl` **is** found | ➖ none needed |
| 4.2 | same | Unit | ✅ same | ✅ same | ✅ passed, **zero production lines** | ✅ handoff value equals the no-tap-record value | ➖ none needed |
| 5.1–5.6 | `cellarTests/ReceiptDetailCompositionTests.swift` | Unit-app | ✅ 239/239 | ✅ all six failed: the pane file did not exist | ✅ all six passed | ✅ each absence paired with a positive anchor | ✅ scanner extracted, `AppSecuritySources` stripper reused |
| 5.7 | `cellarTests/PerPackageTrustCompositionTests.swift` | Unit-app | ✅ 2/2 | ✅ **both shipped tests failed** on the added path | ✅ both passed | ➖ shipped guard | ➖ none needed |

**No task was completed without its test written first.** `4.1`/`4.2` were authored against a tree that
had the projection (WU3 had already landed), so RED was proved explicitly by moving
`InstalledDetailProjection.swift` aside, running the two cases, observing the compile failure, and
restoring the file. `2.1–2.5` is the one unit with no RED row, exactly as `tasks.md` :157-160 pins:
`strict_tdd` sequences RED before GREEN for **behavioural** tasks, and a visibility relaxation is not
one. Its guard is the identical 239-id set before and after.

### Test summary

- Tests written: **18** (12 `unit` in `InstalledDetailProjectionTests`, 6 `unit-app` in
  `ReceiptDetailCompositionTests`).
- Tests passing: **18 / 18**. Suite totals 1,837 core + 245 `cellarTests`.
- Layers: Unit (12), Unit-app (6), E2E (0 — `cellarUITests` is byte-untouched, per task 6.2).
- Approval tests: **1** — WU2's whole guard is the unchanged 239-id set for `PackageDetailView.swift`.
- Pure functions created: `InstalledDetailProjection.init`, `installStateFacts`, `orderedFacts`, and
  four private copy helpers — all total, all `nonisolated`, all I/O-free.

## Work Unit Evidence

| Unit | Focused command and exact result | Runtime harness | Rollback boundary |
|---|---|---|---|
| **WU1** | N/A — artifacts only | N/A — no behaviour | Revert `38f1f90`; the tree returns to `main` |
| **WU2** | `xcodebuild test … -only-testing:cellarTests` → **239 distinct, 0 failures, TEST SUCCEEDED**, id set identical to baseline | Build compiles (the test build is the build) | Revert `1aedbf7`; five `private` keywords return, `factLink` re-inlines |
| **WU3** | `swift test … --filter 'InstalledDetailProjectionTests'` → **10 tests / 1 suite passed**; full core **1,835 / 216, 0 failures** | N/A — a total, pure `init` over one resident record; there is no runtime to exercise | Delete `InstalledDetailProjection.swift`, `InstalledDetailProjectionTests.swift`, and the `receipt(…)` fixture |
| **WU4** | same filter → **12 tests / 1 suite passed**; full core **1,837 / 216, 0 failures** | N/A — `BrewClient` imports `Catalog`, so a real `PackageSearchIndex` is constructible in-suite | Delete the two test cases; no production line is theirs |
| **WU5** | `xcodebuild test … -only-testing:cellarTests` → **245 distinct, 0 failures, TEST SUCCEEDED** | Full `xcodebuild test -scheme cellar` — **290 passing**, the only 2 failures pre-existing (below) | Delete `PackageDetailView+Receipt.swift` and `ReceiptDetailCompositionTests.swift`, revert the DD-11 anchor; `uncatalogedContent`'s `ContentUnavailableView` returns with WU2's revert |

## Files changed

| File | Action | What was done |
|---|---|---|
| `Packages/CellarCore/Sources/BrewClient/InstalledDetailProjection.swift` | Created | The value, the `KindState` sum type, the derived `installStateFacts` and `orderedFacts`, one total `public init(_ package: InstalledPackage)` |
| `Packages/CellarCore/Tests/BrewClientTests/InstalledDetailProjectionTests.swift` | Created | 12 `unit` cases — II15 sc1, sc3–sc8 plus PD6 sc3 and TM5 sc10 |
| `Packages/CellarCore/Tests/BrewClientTests/Fakes/InstalledFixture.swift` | Modified | New `receipt(…)` builder: multi-keg, unlinked, tri-state, `tap: nil`, `desc`/`homepage` nil, pin with and without a version. Shipped signatures untouched |
| `cellar/Browse/PackageDetailView.swift` | Modified | WU2: five helpers internal + `factLink` extracted. WU5: `uncatalogedContent(for:)` removed (the extension supplies it) |
| `cellar/Browse/PackageDetailView+Receipt.swift` | Created | The pane body — header + `MutationMenu` slot, description, fact grid, marker beside the origin fact, `PackageMetadataSection`, footer |
| `cellarTests/ReceiptDetailCompositionTests.swift` | Created | 6 `unit-app` cases — II15 sc2, sc9–sc12 — plus the `ReceiptDetailSources` scanner |
| `cellarTests/PerPackageTrustCompositionTests.swift` | Modified | DD-11: the new path in `views()` and the extended sorted-name anchor |
| `openspec/changes/m10-third-party-detail/**` | Created | proposal, three deltas + README, design, tasks, this file |
| `cellar.xcodeproj/project.pbxproj` | **Untouched** | **0-line diff**, as the file-system-synchronized-group assumption predicted |

## Bindings proof (task 6.3)

```
git diff --stat main -- cellar.xcodeproj/project.pbxproj scripts/ .github/workflows/ \
  …/MutationCommand.swift …/TapCommand.swift …/InstalledDecoder.swift …/InstalledModels.swift
```
→ **empty output**. The pbxproj assumption held; nobody "fixed" the epoch defect DD-6 defers.
`cellarUITests/` is byte-untouched, so the change adds no new UI-test-flagged store (task 6.2).

## Regression guards (task 6.4)

All green, unchanged in meaning: `PerPackageTrustCompositionTests` (2/2, 2-line edit only),
`TapProjectionTests`, `TapShippingProofTests`, `MutationCommandTests`, `InstalledDeriveTests`,
`InstalledFilterCompositionTests` (**82 tests / 5 suites passed** in one focused run),
`SecurityCompositionTests` (13), `BrewfileCompositionTests` (17), `HomeCompositionTests` (3),
`HealthCompositionTests` (19).

## Pre-existing failures — reported, NOT fixed

The full `xcodebuild test -scheme cellar` run ends `** TEST FAILED **` on **two `cellarUITests`
cases**:

- `cellarUITests.testTapDetailFilteringInstalledHandoffAndForceDisclosure` — `cellarUITests.swift:231`,
  *"Failed to get matching snapshot: Find single matching element. Multiple matching elements found."*
- `cellarUITests.testTapsNavigationOfficialSourcesAndAddConfirmation` — `cellarUITests.swift:209`,
  `XCTAssertTrue failed`.

**Both reproduce identically on unmodified `main`** (`5a0860b`, clean tree, same two files, same two
line numbers, same two messages), verified by checking `main` out and re-running exactly those two
tests. They are **not** caused by m10, they are in the Taps section rather than on any surface this
change touches, and `cellarUITests/` has a zero-line diff. Not fixed here, per the launch brief.

Everything else in that run passes: **290 passing cases, 2 failures, both the ones above.**

## Spec-delta self-check (task 6.5)

Arithmetic re-counted from the files, not from the plan:

| Capability | Main | Delta | Result |
|---|---|---|---|
| `installed-inventory` | 14 req / 67 sc | 1 ADDED, 12 sc | **15 req / 79 sc** ✓ |
| `package-detail` | 8 req / 30 sc | 1 MODIFIED, 3 sc replacing 2 | **8 req / 31 sc** ✓ |
| `tap-management` | 13 req / 57 sc | 1 MODIFIED, 10 sc replacing 9 | **13 req / 58 sc** ✓ |

Shipped-scenario byte-identity was checked by extracting each `#### Scenario:` block from both the
main spec and the delta and diffing them: **PD6's 2 and TM5's 9 are byte-identical.** The single
reported difference on TM5's last scenario is an artifact of the extractor — the main spec carries the
next requirement's `<!-- TM6 -->` marker on the line after that scenario, which the delta (ending in
`## Notes for archive`) has no reason to carry. The scenario text itself is identical.

All **14** new scenarios have a task naming them, and **no delta introduces a new verification class**:
only the established `unit` and `unit-app` appear. **No `manual-evidence` scenario exists in this
change** — `sdd-verify` must not wait for a manual harness.

## Line accounting (task 6.6)

| Bucket | Measured | Forecast | Verdict |
|---|---|---|---|
| Code + tests (`cellar/`, `cellarTests/`, `Packages/`) | **1,280** (1,239 + / 41 −) | 1,201–2,167 | **Inside the band**, near its low end |
| SDD artifacts (`openspec/`) | **1,621** (+0 −) | band fixed at the high end by task 0.4 | As fixed |
| **Branch total** | **2,901** changed lines | ~4,130 at the collapsed high end | **Under** |
| Governing budget | **5,000** | — | **58 %** — Low, no `size:exception`, no chain |

`verify-report.md` will add ~250–450 at verify time, landing the PR near **3,150–3,350 / 5,000**.

## Delivery (task 6.7 — drafted, PR not opened)

`single-pr`, `chain_strategy: pending`, no `size:exception`. **The PR was deliberately not opened and
nothing was pushed**: the launch brief for this run forbids both. Task 6.7 is the only open task.

PR title: `feat(installed): detail a package the catalog does not carry from its receipt`.

The body states up front:

- **(a)** The pane **adds no brew invocation and no store**. It composes data already resident: one
  decoded receipt plus the six stores `ContentView.swift:533-544` already wires. Asserted by
  `composingTheReducedDetailReachesNoProcessLayer` and by `theHandoffLandsOnAReceiptBackedDetail`.
- **(b)** It **grants and revokes nothing**. The marker is display-only, resolved by exact identity
  through `TapProjection.grantsIndividually(_:publishedBy:in:)` and carrying
  `TapProjection.grantMarker` — the one `package-trust` projection that owns the copy. The pane
  contains no trust control, no `TapCommand`, and no marker literal of its own.
- **(c)** It makes **no claim about a third-party tap**. The footer stays the shipped, byte-identical
  statement about Cellar's catalog, U+2019 included, and the phrase `third-party` is absent from the
  pane.
- **(d)** **R4** — brew's interactive trust prompt when upgrading a package from a tap that is not
  trusted — is **inherited unchanged** from `InstalledRow`, which already ships the identical
  `MutationMenu`. m10 neither creates nor widens it, and did not "fix" it here.

## Deviations from design

Three, all additive, none contradicting a recorded decision:

1. **`orderedFacts` added to the projection.** The design's interface listing has `identity`,
   `tapOfOrigin` and `installStateFacts` as separate members, so "the groups keep their order" would
   otherwise be an order the *test* assembles rather than one the *type* exposes — a weak assertion
   for II15 sc1's central clause. `orderedFacts` is a computed concatenation in the requirement's
   order; it stores nothing and changes no other member.
2. **Comment updated in `PerPackageTrustCompositionTests.swift`.** DD-11 pins "exactly 2 lines". The
   real diff is **3 additions / 2 deletions**: the anchor line, the new path line, and a comma the
   preceding array element needs — plus one word in the comment above the anchor, which said "all
   three files" beside an assertion that now names four. Leaving a shipped guard's comment
   contradicting the line under it seemed worse than the extra line. **Reported, not absorbed.**
3. **Fact labels chosen where the spec pins only values.** II15 and the design pin the *values*
   (`Linked`, `Not linked`, `N other versions installed`, `Updates itself`, `Updated by Homebrew`) but
   not every label. Chosen, all unique: `Type`, `Homepage`, `Tap`, `Version`, `Link state`,
   `Other versions`, `Pin state`, `Updates`. `Pin state` reuses `InstalledRow.swift:189`'s shipped pin
   copy (`Pinned at 1.2.3` / `Pinned`) so the two surfaces say the same thing; the label is
   `Pin state` rather than `Pinned` only so a label never equals its own value.

Presentation question the design left open (task 7.4): **`MutationMenu` sits in the header's
primary-button slot, to the left of the heart** — the slot `EmptyView()` occupied, unchanged in
position. No requirement depends on it.

## Archive obligations recorded (phase 7)

- **7.1** Promote the ADDED block as **II15**, appended after `installed-inventory`'s current last
  requirement (→ 15 req / 79 sc; II1–II14 byte-identical). Promote PD6 and TM5 as **whole-block**
  replacements (→ 8 req / 31 sc and 13 req / 58 sc), TM5 under its existing `<!-- TM5 -->` marker
  (`openspec/specs/tap-management/spec.md:118`). **Promote no verification-class table** — none of the
  three main specs carries one; only the inline `- Verification:` lines promote.
- **7.2** Record: **no `package-trust` delta** — PD8, PT3, PT5, PT6, PT7 were **activated, not
  amended**. And record the **TM1 → TM5 provenance correction**: the m9 archive cites TM1 in at least
  three places (`archive-report.md:440`, `tasks.md:72`, `specs/package-detail/spec.md:20`) for a
  "no third-party detail fallback" clause that is **TM5's**
  (`openspec/specs/tap-management/spec.md:147-149`). TM1 is a one-invocation rule about *tap* detail
  acquisition; its genuine constraint on m10 — no additional brew invocation to complete a detail —
  is honoured and asserted by II15 sc2 and TM5 sc10.
- **7.3** Record the deferrals so nobody "completes the grid": the **install-date fact** is blocked on
  an `InstalledDecoder` epoch-collapse fix (a follow-up delta against `installed-inventory`, not a
  rendering choice); **no "latest version" fact** may be added while `catalogVersion` falls back to the
  installed keg's version (DD-5); receipt-backed **release notes** stay `release-notes` D4 territory;
  **Approach C** (synthesizing a `CatalogPackage`) is now explicitly forbidden by PD6's modified text.
- **7.4** The open presentation question is **closed by what shipped**: `MutationMenu` in the header
  slot, left of the heart. Named above.

## Issues found

None beyond the two pre-existing `cellarUITests` failures above, which are reported and untouched.
