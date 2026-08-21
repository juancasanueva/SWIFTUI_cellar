# Apply progress — `m6-tip-jar`

**Mode**: Strict TDD (`strict_tdd=true`, both runners present)
**Store**: hybrid — this file plus Engram `sdd/m6-tip-jar/apply-progress`
**Delivery**: `single-pr`, four internal work units, `review_budget_lines=4000`
**Branch**: `feature/m6-tip-jar` off `main` (not pushed, no PR opened)
**Status**: 29/29 tasks complete. Both halves green.

## Test results

| Suite | Command | Executed | Passed |
|---|---|---|---|
| `CellarCore` | `swift test --package-path Packages/CellarCore` | 1769 in 208 suites | 1769 (1 pre-existing known issue) |
| `TipJarTests` (new) | `swift test … --filter TipJarTests` | 37 in 4 suites | 37 |
| `cellarTests` | `xcodebuild test … -only-testing:cellarTests` | 206 | 206 |
| — `TipThankYouPreferenceTests` (new) | | 6 | 6 |
| — `StoreKitTipSourceTests` (new) | | 4 | 4 |
| — `TipCompositionTests` (new) | | 25 | 25 |

Baseline was 171 `cellarTests` (probe U21); 171 + 6 + 4 + 25 = **206**, so the
count is accounted for exactly rather than trusted. Executed counts are read from
`Test case '…' passed` lines, never from `** TEST SUCCEEDED **` — which this
change proved is not evidence (see finding 2). Three consecutive full
`cellarTests` runs: 206/206, 0 failures each.

## TDD cycle evidence

| Task | Test file | Layer | Safety net | RED | GREEN | Triangulate | Refactor |
|---|---|---|---|---|---|---|---|
| 1.1–1.2 | — | Manifest | 1732 pre-existing | ✅ empty-target build error | ✅ package resolves | ➖ structural | ➖ none needed |
| 2.1 | `TipFakes.swift` | Support | N/A (new) | ➖ no assertions | ➖ | ➖ | ✅ |
| 2.2 | `TipAvailabilityTests` | Unit | N/A (new) | ✅ `TipJar` target empty, nothing existed | ✅ 22/22 | ✅ 4 extra cases (second product, longer list, second failure reason, empty-catalog cycle) | ✅ |
| 2.3 | ↑ | Unit | — | ✅ | ✅ | ✅ | ✅ |
| 2.4 | `TipPurchaseTests` | Unit | N/A (new) | ✅ written before `TipPurchaseOutcome` existed | ✅ 22/22 | ✅ 4 extra (second reason, unrecognized, failed-load refusal, unsettled catalog) | ✅ |
| 2.5 | ↑ | Unit | — | ✅ | ✅ | ✅ | ✅ |
| 3.1 | `TipGratitudeTests` | Unit | ✅ 22/22 | ✅ `cannot find type 'TipStore' in scope` | ✅ 31/31 | ✅ parameterized over 4 outcomes + unset-launch control | ✅ |
| 3.2 | ↑ | Unit | — | ✅ | ✅ | ✅ | ✅ |
| 3.3 | `TipTransactionTests` | Unit | ✅ 31/31 | ⚠️ **see note A** — proved by planted mutation instead | ✅ 37/37 | ✅ unverified-alone + stream-control cases | ✅ |
| 3.4 | ↑ | Unit | — | ⚠️ note A | ✅ | ✅ | ✅ |
| 3.5 | `TipGratitudeTests` | Unit | ✅ | ✅ written before `TipStore` existed | ✅ | ✅ | ✅ |
| 3.6 | ↑ + sweep | Unit + structural | ✅ | ✅ | ✅ | ✅ | ✅ |
| 4.1 | `TipThankYouPreferenceTests` | Integration (real `UserDefaults` suite) | ✅ 171/171 | ✅ `cannot find 'TipThankYouPreference'` | ✅ 6/6 | ✅ untouched-store + second-tip cases | ✅ |
| 4.2 | ↑ | Integration | — | ✅ | ✅ | ✅ | ✅ |
| 4.3 | `Tip.storekit` | Fixture | — | ➖ resource | ✅ resolves via `SKTestSession` | ➖ | ➖ |
| 4.4 | `StoreKitTipSourceTests` | Behavioral (real local store) | ✅ | ⚠️ **declared inadmissible by design** — see note B | ✅ 4/4 | ✅ buy-twice case | ✅ |
| 4.5 | ↑ | Behavioral | — | ⚠️ note B | ✅ | ✅ | ✅ |
| 5.1–5.2 | `TipCompositionTests` | Structural | ✅ 181/181 | ⚠️ **see note C** — proved by planted-violation controls | ✅ 25/25 | ✅ 6 planted escapes, 4 ordinary lines, 8 price cases, 3 planted links | ✅ |
| 5.3 | ↑ | Structural | — | ➖ no violation found | ✅ | ➖ | ➖ |
| 6.1–6.2 | `TipCompositionTests` | Structural | ✅ | ✅ wiring guard failed before the wiring existed | ✅ | ✅ | ✅ |
| 6.3 | ↑ | Structural | ✅ 195/195 | ✅ **3 tests failed**: no purchase call site, no signpost row, no tip card | ✅ 25/25 | ✅ anchors + controls | ✅ |
| 6.4–6.5 | ↑ | Structural | — | ✅ | ✅ | ✅ | ✅ |
| 7.1–7.3 | — | Verification | ✅ | ➖ documentation | ✅ both halves green | ➖ | ➖ |

### Note A — task 3.3's RED

`TipTransactionTests` passed on first execution. The drain-then-observe sequence
already existed, because task 3.1's harness waits on the purchasing seam's
observation counter and therefore *demanded* it during 3.2's GREEN. Rather than
claim a RED that did not happen, the assertions were proved by **planting the
violation they forbid**: `start()` was inverted to observe before draining, and
5 assertions across 2 suites failed with the exact reordering in the message. The
inversion was then reverted and the suite returned to 37/37. The mutation and its
revert are both recorded here rather than only in the transcript.

### Note B — task 4.4's RED, as the design declared

`design.md` declares this suite's RED inadmissible: the StoreKit agent keeps
per-app state at `~/Library/Caches/com.apple.storekitagent/Octane/<bundle-id>/`
that outlives both the process and the `xcodebuild` invocation, so a red there can
come from leftover state rather than from missing code. Every assertion in the
suite is state-independent — each test resets, disables dialogs, clears
transactions, and then asserts only on the effect of an action it performed
itself. Nothing asserts "zero products without a configuration".

### Note C — tasks 5.1/5.2's RED

A structural sweep written against already-correct code passes immediately, and
an absence asserted against a scanner that sees nothing passes for free forever.
The RED equivalent here is executed rather than assumed: **6 planted StoreKit
escapes**, **3 planted external payment links** and **8 price-scanner cases**
(3 violations the scanner must catch, 5 ordinary lines including `$0` closure
shorthand it must not) all run as assertions, plus positive anchors requiring the
conformer to really name `Product` and `Transaction` and the manifest scanner to
tell an empty dependency list from a full one.

## Work unit evidence

| Unit | Focused command | Result | Runtime harness | Rollback boundary |
|---|---|---|---|---|
| 1 — `TipJar` core | `swift test --package-path Packages/CellarCore --filter TipJarTests` | 37/37 | N/A — pure values, no runtime boundary | Delete `Sources/TipJar/`, `Tests/TipJarTests/`, 3 manifest declarations |
| 2 — conformers | `xcodebuild test … -only-testing:'cellarTests/StoreKitTipSourceTests'` and `…/TipThankYouPreferenceTests'` | 4/4 and 6/6 | ✅ real `SKTestSession(configurationFileNamed: "Tip")`, headless, no scheme change | Delete `cellar/Support/{StoreKitTipSource,TipThankYouPreference}.swift`, `cellarTests/Tip.storekit`, revert 7 pbxproj lines |
| 3 — structural sweep | `xcodebuild test … -only-testing:'cellarTests/TipCompositionTests'` | 25/25 | N/A — file-text assertions | Delete `cellarTests/TipCompositionTests.swift` |
| 4 — wiring, surfaces, PRD | `xcodebuild test … -only-testing:cellarTests` | 206/206 | ✅ full app build + hosted test launch under the real composition root | Revert the 5 modified app files + `PRD.md` |

## Commits

| Commit | Unit |
|---|---|
| `0070264` | `feat(tip-jar): dependency-free TipJar core in CellarCore` |
| `69344a9` | `feat(tip-jar): StoreKit conformer and the one-boolean thank-you` |
| `3463707` | `test(tip-jar): structural sweep over the app target and its tests` |
| (this commit) | `feat(tip-jar): wire the tip store into both scenes and amend the PRD` |

### One repair, recorded rather than hidden

The maintainer's two pre-staged `cellar/Assets.xcassets/formula.imageset/` files
had to stay staged and uncommitted. Every `git add` used explicit paths and never
`-A`, but that was not sufficient: `git commit` writes **whatever is already in
the index**, and those two files were staged before this session began, so the
first commit swallowed them.

They were removed by rebuilding the four commits from their own trees minus that
one path (`read-tree` → `rm --cached` → `write-tree` → `commit-tree`) and moving
the branch with `reset --soft`, which leaves the index and working tree alone.
Verified afterwards: the rebuilt tip differs from the original tip by exactly
those two deletions and nothing else; the four messages and every other byte are
unchanged; and `git status` shows the two files staged as `A`, precisely as they
were found. Both halves were re-run on the repaired branch and are green.

The lesson for the next session: with a dirty index, explicit-path `git add` does
not scope a commit. `git commit -- <paths>` does.

## Findings the maintainer must decide on

### 1. `project.pbxproj` gained 7 lines — the one broken binding

`project.pbxproj` was a **not-touched binding**, and it is now `+7 −0`.

It is not absorbed silently, per `design.md`'s rollout note ("if `project.pbxproj`
or `cellar.xcscheme` shows any diff at apply time, report it before merge rather
than absorbing it").

**Why.** The design's no-pbxproj claim covers *file membership* — `cellar/Support/`
lands in the existing synchronized root group, which is true and held. It did not
account for **product linkage**. The app target links six package products
explicitly; `SecurityKit` is importable only because `Persistence` depends on it,
and `TipJar` has, by requirement 9, **no dependents at all**. Measured, not
assumed: with the manifest complete and the sources present, the build failed with
`unable to resolve module dependency: 'TipJar'`.

**What was added** — additive only, no deletion, no modification, same shape and
same sequential id scheme as the six existing entries:

- one `PBXBuildFile` line
- one entry in the app target's `PBXFrameworksBuildPhase`
- one entry in `packageProductDependencies`
- one four-line `XCSwiftPackageProductDependency` block

**Alternatives considered and rejected.** Making an already-linked target depend
on `TipJar` would make it importable with no pbxproj diff, but it inverts the
graph — the outermost node would depend on the tip jar — and turns a stated
architectural fact into a linkage trick. Moving the types into the app target
contradicts D-A and requirement 9 outright. There is no third route: a StoreKit
consumable behind a zero-dependency core target cannot reach the app without the
product being linked.

The other four bindings held at exactly **0 lines**: `AppSection.swift`,
`ContentView.swift`, `AppSectionPlacementTests.swift`, and every `.xcscheme`.

### 2. `** TEST SUCCEEDED **` was printed over a failing test

The shared scheme sets `parallelizable = "YES"`, and the scheme is a not-touched
binding, so `cellarTests` runs across two worker processes. Both talk to the
**same** StoreKit agent environment, and each worker's `clearTransactions()` was
deleting the leftover the other had just seeded. The drain test failed on the
second worker on every run — and `xcodebuild` still printed
`** TEST SUCCEEDED **`.

This is the silent false-green `probes.md` conclusion 4 warned about, arriving
through a different door than the missing `()`. It is the reason every count in
this document is read from `Test case '…' passed` lines.

Fixed inside the test target rather than by touching the scheme:
`StoreKitAgentLock` takes a bounded, non-blocking `flock` around each StoreKit
test, so a stuck peer costs one failed test rather than a hung suite.

A second, independent race in the same suite: `SKTestSession.buyProduct` returns
before `Transaction.unfinished` reflects the new transaction. It passed in
isolation and failed inside the full run at 0.03 s. The arrangement now waits for
the agent to catch up, bounded at 10 s, returning whatever it last saw so a
genuine failure still fails on its own assertion with the real value attached.

### 3. Copy is a spec-compliant placeholder awaiting the maintainer's wording

Every user-facing string in `TipJarCard.swift` and the `AboutView` signpost row
is written to the spec's rules — gratitude, no begging, no countdown, no claim
the app is at risk, no suggestion any feature depends on tipping, price rendered
only by interpolating `product.displayPrice` — but the **final phrasing is the
maintainer's to author**. It is flagged here and belongs in the PR body rather
than shipping as though it were settled.

Strings awaiting review:

- headline `"Say thanks"`
- explanation, both before and after a tip
- button verb `"Tip ·"` / `"Again ·"` (the price is appended from the product)
- the pending, unverified and failed notes
- the About row, `"Support"` → `"In Settings"`

### 4. `TipProduct.description` is carried but never rendered

The value maps StoreKit's `Product.description` faithfully, and
`StoreKitTipSourceTests` asserts it came from the store rather than from local
composition. The card does not render it — the explanation copy above is what
the surface shows. Worth a decision when the copy is authored: either render the
store's description or accept that the field exists for fidelity alone.

### 5. Deviations from the design

- **`TipCatalogLoader` and `TipPurchaseRunner` are new types** not named in
  `design.md`. Both were extracted from `TipStore` because the two hardest claims
  in the spec are otherwise unassertable: "loading is observable while it is in
  progress" describes a state that exists only between the call and the answer,
  and "a purchase with no product reaches the seam not at all" is an absence that
  needs a recorder. The store uses both; the signatures `design.md` fixes are
  unchanged.
- **`TipThankYouPreference`'s observable property is `isTipRecorded`**, not
  `hasTipped`: the seam requires `func hasTipped() async -> Bool`, and Swift will
  not allow a stored property and a method of the same name on one type.
- **Task 1.2's literal instruction is unsatisfiable.** SwiftPM refuses a package
  containing an empty target (`target 'TipJar' referenced in product 'TipJar' is
  empty`), so "create empty directories and confirm it still builds" cannot be
  run as written. The check it stands for was performed instead: `swift package
  describe` reports `TipJar deps= []`, and the full package suite is green.
- **One test assertion was corrected rather than the code.** `#expect(value as?
  Int == nil)` was written to mean "no tip count was stored", but a `Bool` in a
  defaults domain returns as an `NSNumber`, so `as? Int` succeeds for a flag as
  readily as for a counter and the assertion was factually wrong about Foundation
  rather than about the requirement. It now asserts the value is still `1` after
  **two** recordings, and that the stored type really is `CFBoolean`.

### 6. Still open

- **U22 — Mac App Store feasibility is unproven.** A StoreKit consumable only
  transacts in a MAS build; this slice's success is build plus local verification.
  Recorded openly in `PRD.md` lines 9, 10 and 186, and in open question 2.
- **No UI test was added.** The `AppTestTipSource` fixture exists to keep existing
  UI-test launches at zero StoreKit and zero egress, which is what the design
  asked of it — not to add coverage.
