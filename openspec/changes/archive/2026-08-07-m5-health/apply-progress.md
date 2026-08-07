# Apply Progress: `m5-health` — batches 1, 2, 3 and 4, merged

**Mode**: Strict TDD (`config.yaml` `testing.strict_tdd: true`), runner
`swift test --package-path Packages/CellarCore` plus `xcodebuild test` for the app target.
**Delivery**: `single-pr` with pre-accepted `size:exception` (obs #7532 decision 2).
**RDD**: disabled — no review started, no review referenced. Not committed; the orchestrator commits.

**70 / 71 tasks complete.** Batch 1 delivered Phases 0–8 (CellarCore, 46 tasks); batch 2 delivered
Phases 9–13 (app layer, E2E, close-out, 24 tasks).

**The one open task is 13.3 and it is open on purpose**: it surfaces every user-facing string to the
maintainer for a wording review, and an executor cannot close a task whose acceptance is somebody
else's. Every string is reproduced verbatim in the return summary.

## Baseline (Phase 0)

| Field | Value |
|---|---|
| Baseline commit | **`80b6036`** (`docs(sdd): archive m5-brewfile`) — **not** `7d48779` |
| CellarCore `@Test` count at baseline | 1,517 in 188 suites, all passing, 1 known issue |
| `cellarTests` `@Test` count | 93 |
| `cellarUITests` `func test` count | 28 |
| `ReleaseNotesUITests` pre-existing failure baseline | 4 cases / 7 failures — orchestrator-owned, untouched, subtracted at verify |

> **Deviation recorded, not absorbed.** `tasks.md` 0.1 names `7d48779` as the baseline. The
> repository's `main` is `80b6036`: the `m5-brewfile` slice landed and was archived between planning
> and apply. The baseline above is the real one, measured rather than inherited.

### Binding zero-line-diff list (0.2) — all seven re-verified at 13.2, **after** the app-layer work

`git diff --numstat` reports **nothing** for any of:
`Packages/CellarCore/Package.swift`, `cellar.xcodeproj/project.pbxproj`,
`Tests/CatalogTests/CatalogFootprintTests.swift`, `Sources/DiskUsage/HomebrewRoots.swift`,
`Sources/DiskUsage/DiskUsageModels.swift`, `Sources/DiskUsage/DiskUsageCache.swift`,
`openspec/specs/brew-execution/spec.md`.

`project.pbxproj` was the one at risk and it held: `cellar/Health/` landed as a **synchronized root
group** (the `cellar/Discover/` precedent), so five new app files cost zero project objects.
`BrewClientTests` already declared `resources: [.copy("Fixtures")]`, so `Fixtures/Doctor/` needed no
manifest edit — confirmed rather than assumed.

## Result

| Measure | Baseline | Batch 1 cut | Final | Delta |
|---|---:|---:|---:|---:|
| CellarCore tests | 1,517 | 1,654 | **1,655** | +138 |
| CellarCore suites | 188 | 198 | **198** | +10 |
| CellarCore known issues | 1 | 1 | **1** | 0 |
| CellarCore failures | 0 | 0 | **0** | — |
| `cellarTests` `@Test` | 93 | 93 | **134** | +41 |
| `cellarUITests` `func test` | 28 | 28 | **37** | +9 |

- `FAST` → **1,655 tests in 198 suites passed, 1 known issue, 0 failures**.
- `APP` (`-only-testing:cellarTests`) → **TEST SUCCEEDED**.
- `FULL` (whole scheme) → **exactly 4 failed cases / 7 error lines, all `ReleaseNotesUITests`** —
  byte-for-byte the recorded pre-existing baseline. **No other test failed anywhere.** Not
  diagnosed here; orchestrator-owned.
- `BUILD` → **BUILD SUCCEEDED**.

Authored size: batch 1 ~5,031 lines; batch 2 ~3,845 (950 tracked add+delete, 2,895 in new files),
excluding `openspec/` lifecycle artifacts. Within the pre-accepted `size:exception`.

## TDD Cycle Evidence

### Batch 1 — Phases 0–8 (CellarCore)

| Task | Test file | Layer | Safety net | RED | GREEN | TRIANGULATE | REFACTOR |
|---|---|---|---|---|---|---|---|
| 0.1–0.2 | — | — | ✅ 1517/1517 | ➖ bookkeeping | ➖ | ➖ | ➖ |
| 1.1–1.4 | fixtures | — | N/A (new) | ➖ inputs, not code | ➖ | ➖ | ➖ |
| 1.5 | `DoctorFixtureManifestTests.swift` | Unit | N/A (new) | ✅ loader absent | ✅ 7 passed | ✅ 6 streams + 2 markers + negative control | ➖ |
| 2.1 | `DoctorCommandTests.swift` | Unit | N/A (new) | ✅ `DoctorCommand` absent | ✅ 5 passed | ✅ argv + flags + `.read` + declaration scan | ✅ joined shipped argv guard |
| 2.2 | — | — | — | — | ✅ | — | — |
| 2.3–2.7 | `DoctorParserTests.swift` | Unit | N/A (new) | ✅ `DoctorDocumentStream` absent | ✅ 21 passed | ✅ 7 grammar rows + 3 fixtures + 5 stream cases | ✅ |
| 2.8 | — | — | — | — | ✅ | — | — |
| 3.1–3.2 | `DoctorSourceTests.swift` | Unit | N/A (new) | ✅ `BrewDoctorSource` absent | ✅ 14 passed | ✅ 6 exit statuses + 3 outcomes | ✅ `try` assertion tightened |
| 3.3 | — | — | — | — | ✅ | — | — |
| 3.4 | `DoctorSourceTests.swift` | Unit | ✅ | ✅ | ✅ | ✅ 2 runs + argv + spine scan | ➖ |
| 4.1–4.3 | `DoctorPayloadQuarantineTests.swift` | Structural | ✅ shipped code | ✅ **no GREEN step by design** | ✅ 7 passed **unchanged** | ✅ 3 sources × 4 statuses × both directions | ➖ |
| 5.1–5.3 | `HomebrewUpdateReaderTests.swift` | Unit | N/A (new) | ✅ `HomebrewLastUpdate` absent | ✅ 15 passed | ✅ both shapes + 4 cases + 3 non-answers | ✅ `FileManager` made computed |
| 5.4 | — | — | — | — | ✅ | — | — |
| 5.5 | `DiskRootsCompositionTests.swift` | Regression | ✅ 16/16 unedited | ✅ golden mismatch | ✅ 7 passed | ✅ 3 shipped files + decode + `==` control | ✅ golden narrowed to `roots` |
| 6.1–6.4 | `HealthScoringTests.swift` | Unit | N/A (new) | ✅ `HealthInput` absent | ✅ 32 passed (with 6.5–6.6) | ✅ 8 inputs × 11 reasons + 7 health values | ✅ 3 scans narrowed |
| 6.5–6.6 | `HealthWeightsTests.swift` | Unit | N/A (new) | ✅ | ✅ | ✅ 8 normalisations + monotonic sweeps | ✅ float tolerance |
| 6.7 | — | — | — | — | ✅ | — | — |
| 7.1–7.4 | `HealthProjectionTests.swift` | Unit | N/A (new) | ✅ `HealthRow` absent | ✅ 17 passed | ✅ 7 rows × 5 reasons + partial + remediation | ✅ scan narrowed to call shapes |
| 7.5 | — | — | — | — | ✅ | — | — |
| 8.1 | `BulkSelectionTests.swift` (**REWRITE**) | Unit | ✅ 12/12 | ✅ `.pin` absent | ✅ | ✅ | ➖ |
| 8.2 | `ServiceSubmissionTests.swift` (**REWRITE**) | Unit | ✅ | ✅ `.pin` absent | ✅ | ➖ two lines only | ➖ |
| 8.3 | `BulkSelectionTests.swift` | Unit | ✅ | ✅ | ✅ | ✅ 6 eligibility tests | ➖ |
| 8.4 | `ConfirmationDisclosureTests.swift` | Unit | ✅ | ✅ | ✅ | ✅ single + batch + control | ➖ |
| 8.5 | `BulkFanOutTests.swift` (**REWRITE**) | Unit | ✅ | ✅ | ✅ | ✅ 4 verbs + cask + no-confirmation | ➖ |
| 8.6 | `BulkSelectionTests.swift` | Structural | ✅ | ✅ | ✅ | ✅ by case **and** by title | ➖ |
| 8.7 | — | — | — | — | ✅ 43 in 4 suites, atomic | — | ✅ kind-safe `FormulaID` |

### Batch 2 — Phases 9–13 (app layer)

| Task | Test file | Layer | Safety net | RED | GREEN | TRIANGULATE | REFACTOR |
|---|---|---|---|---|---|---|---|
| 9.1 | `cellarTests/AppSectionPlacementTests.swift` | Unit | ✅ `cellarTests` green | ✅ `.health` absent → no compile | ✅ 5 passed | ✅ order + count + rawValue list + landing selection | ➖ |
| 9.2 | same file | Structural | ✅ | ✅ | ✅ | ✅ 4 real switches + **3-case control** (default arm / missing case / unrelated switch) | ✅ `default:` slicing bug in the detector, caught by its own control |
| 9.3 | — | — | ✅ | — | ✅ | — | — |
| 9.4 | — | — | ✅ | — | ✅ | — | — |
| 10.1 | `cellarTests/HealthCompositionTests.swift` | Unit | ✅ | ✅ `HealthComposition` absent | ✅ 8 mapping tests passed | ✅ all 8 sources × every non-answering shape, each asserted `!= .answered(1.0)` | ✅ `scanGap` extracted |
| 10.2 | same file | Unit + Structural | ✅ | ✅ `HealthStore` absent | ✅ 3 passed | ✅ per-instance launcher + 2 acquisitions + `.task` block scan with anchor **and** control | ✅ `.task` rule narrowed to acquisition (see F14) |
| 10.3 | — | — | N/A (new) | — | ✅ | — | — |
| 10.4 | — | — | ✅ | — | ✅ | — | — |
| 10.5 | `HealthCopy.swift` | — | — | ➖ content, not code | ✅ | ➖ | — |
| 10.6 | `HealthCompositionTests.swift` | Unit + Structural | ✅ | ✅ `HealthCopy` absent | ✅ 4 passed | ✅ literal extractor + anchor, forbidden-word sweep, complete/partial/unscorable score triple | ➖ |
| 11.1–11.2 | `cellarTests/BulkSnoozeTests.swift` | Unit | ✅ | ✅ `BulkSnoozeSelection` absent | ✅ 4 passed | ✅ 3 different versions + in-memory store cross-check + nothing-offered + eligibility matrix | ➖ |
| 11.3 | same file | Unit + Structural | ✅ | ✅ | ✅ 3 passed | ✅ recording launcher + real `OperationCenter` + 3-file source scan | ✅ token list narrowed off `snoozedVersion` collision |
| 11.4 | `cellarTests/BulkActionBarTests.swift` | Unit | N/A (new file, shipped view) | ✅ `BulkActionBarPresentation` absent | ✅ 4 passed | ✅ mixed selection 3/2/1/4 + all-cask + destructive role + unavailable centre | ➖ |
| 11.5 | same file | Structural | ✅ | ✅ | ✅ 3 passed | ✅ literal extractor + anchor + **violation control** + `ForEach` body scan | ➖ |
| 11.6 | `Tests/BrewClientTests/SnoozeGuardTests.swift` (**WIDENED**) | Structural | ✅ 7/7 unedited assertions | ✅ app path unreadable at old root | ✅ 8 passed | ✅ 7 in-package files + the app caller under **both** token sets | ✅ reader re-rooted, `packageRoot` derived |
| 11.7–11.8 | — | — | ✅ | — | ✅ | — | ✅ `Entry` struct replaced a tuple array |
| 12.1 | `cellarUITests/HealthSectionUITests.swift` | E2E | ✅ | ✅ identifiers absent | ✅ 5 passed | ✅ sidebar geometry + scored/unscorable launches + unanswered row + doctor copy | ✅ `.accessibilityElement(children: .contain)` |
| 12.2 | same file | E2E | ✅ | ✅ | ✅ 3 passed | ✅ mixed 2/1 + all-cask disabled + snooze copy | ✅ `label` not `title` |
| 13.1–13.5 | — | — | ✅ | ➖ close-out | ✅ | ➖ | — |

### Test summary

- New suites: **12** in `CellarCore` (batch 1) plus **4** in the app target (batch 2).
- New tests: **156** in the package (**+138** net), **+41** in `cellarTests`, **+9** in `cellarUITests`.
- Layers: Unit, Structural, Regression and — new in batch 2 — **Integration** (`MetadataStore` on an
  in-memory container) and **E2E** (`cellarUITests`).
- Approval tests: `DiskRootsCompositionTests` (7) — captures shipped encoding/decoding before HD4.
- Pure functions created: `DoctorParser.parse`, `HealthScoring.score`, all 8 `HealthThresholds`
  normalisations, `HealthProjection.build`, `HomebrewUpdateReader.lastUpdate`, all 8
  `HealthComposition` mappings, `HealthScorePresentation.init`, `BulkSnoozeSelection.init`,
  `BulkActionBarPresentation.init`.

### Work unit evidence

| Evidence | Value |
|---|---|
| Focused test command | `swift test --package-path Packages/CellarCore` → **1,655 passed, 198 suites, 1 known issue, 0 failures**; `xcodebuild test -only-testing:cellarTests` → **TEST SUCCEEDED**; `-only-testing:cellarUITests/HealthSectionUITests` → **9/9 passed** |
| Runtime harness | **Batch 1, U10 re-measured live**: `HOMEBREW_NO_AUTO_UPDATE=1 brew doctor` × 2 → exit 1 both, stdout **1 byte** (`0a`), stderr **622 bytes**, `cmp`-equal across runs. **U14 re-measured live**: `/opt/homebrew/.git/FETCH_HEAD` mtime `1786081527` identical before and after two doctor runs. **Batch 2**: the whole app launched nine times under `--ui-testing-m5-health`; the sidebar renders Health between Cleanup and Security by frame geometry, the score renders beside its caveat, the unscorable launch renders a sentence rather than `0` or `100`, the doctor row quotes Homebrew, and a mixed selection shows `Pin 2` / `Unpin 1` with an all-cask selection leaving both present-and-disabled |
| Rollback boundary | `Sources/BrewClient/Doctor*.swift`, `Sources/DiskUsage/{FileMetadataAccess,HomebrewUpdateReader}.swift`, `Sources/Catalog/Health*.swift`, `Tests/BrewClientTests/Fixtures/Doctor/` and **`cellar/Health/`** all delete cleanly — no existing type is widened, and `cellar/Health/` costs **zero** `project.pbxproj` objects to remove. `BulkSelection.swift` + `OperationCenterBulk.swift` revert **together** (a partial leaves `commands(for:over:)` non-exhaustive and uncompilable), and with them the II13 spec text and the three rewritten package tests. `Snooze` rows already written by a bulk action survive a revert and stay individually unsnoozable |

## Recorded rewrites — byte-sliced replaced ranges (13.1)

Measured against baseline `80b6036`. Each is a **rewrite, never a deletion**. `git diff -U0` over
`Tests/`, `cellarTests/` and `cellarUITests/` removes **exactly 8 assertion lines**, and all 8 are
accounted for below.

| File | Lines | Byte range | Length | SHA-256 of replaced slice |
|---|---|---|---:|---|
| `Tests/BrewClientTests/BulkSelectionTests.swift` | 66–79 | `[2541, 3339)` | 798 | `46a394c30876d5485add5817496df32440901adb1161bfc9f3138243ec255e83` |
| `Tests/BrewClientTests/ServiceSubmissionTests.swift` | 213–231 | `[8479, 9545)` | 1066 | `d99af52bd834cc59cd8965571e9b6c7318e823017fcf2f8decddadd9a200b98c` |
| `Tests/BrewClientTests/BulkFanOutTests.swift` | 114–137 | `[5120, 6313)` | 1193 | `2f4bef3396ee15a758c65d69656891a2fc7bbc21ca6c49a7db4e1e76ef2fbf5a` |
| **`cellarTests/BrewfileCompositionTests.swift`** (batch 2) | 549–563 | `[24642, 25249)` | 607 | `20e87487846a444dbeb3280ed3f607485a2f6e155b791232d41b8385d73da429` |

Removed assertion lines, itemised: three `allCases == [.upgrade, .uninstall]`, two
`allCases.count == 2`, the two `BulkFanOutTests` loop lines a stronger per-verb map replaced, and —
batch 2 — one `AppSection.allCases.count == 9`. **No unrelated assertion was removed anywhere.**

## Findings — recorded, not absorbed

### F1. A **third** shipped test pinned the two-case vocabulary (not identified in planning)

`BulkFanOutTests.noOtherVerbAcceptsASelection` asserted **both** `allCases == [.upgrade, .uninstall]`
**and** scanned `OperationCenterBulk.swift` for `.pin`/`.unpin` as forbidden strings. The proposal,
design and `tasks.md` all name only two tests. Rewritten under 8.5 with its intent exactly preserved:
`reinstall` and `zap` still have no selection form and are still scanned for; pin and unpin moved
from the prohibited list into the exhaustive one.

### F2. `MutationCommandTests`' shipped argv guard covers every `*Command.swift`

`DoctorCommand.swift` matched the glob and failed — correctly. Resolved by making `DoctorCommand`
**join** the guard rather than dodge it, and by turning the guard's single-member `namesNothing`
exemption into a `[String: [String]]` mapping each exempt file to the **exact** initialisers it may
offer. `DoctorCommand` maps to `[]`. The claim was **strengthened**, not relaxed.

### F3. A cask could have become `pin --formula <cask>` — caught before it shipped

`design.md` HD10's `MutationCommand.naming(id, MutationCommand.pin)` does not typecheck, and the
obvious repair rebuilds a cask's identity as a formula. Shipped as `FormulaID(id).map(MutationCommand.pin)`,
which checks the kind and returns `nil` for a cask.

### F4. `DoctorParser` needs one document-level rule HD2's per-line table does not contain

A clean run and a wholly unrecognised report both have zero `Warning:` blocks, so the per-line table
files both entirely as preamble. Resolved with one document-level rule and the named constant
`DoctorParser.readyStatement`. **Recorded in `design.md` at 13.4.**

### F5. `HD2`'s "detail-shaped" is load-bearing and now says so

Indentation, not position, is what makes a line detail-shaped. Documented in `DoctorParser`'s grammar
table.

### F6. Blank lines are the one thing the grammar drops, and the accounting rule says so

"Every line is accounted for" means every **non-empty** line, asserted against the real capture.

### F7. `tasks.md` 6.5 contradicted HD7's own table — **maintainer ruled: the tie stands**

HD7 proposes `cache 5` and `doctor 5`. The spec (SH10) requires only doctor < outdated. The
maintainer ruled the tie stands and the task text was wrong; **`tasks.md` 6.5 is reworded to
"doctor < outdated"** and the ruling is recorded in `design.md`. `HealthWeightsTests` asserts
`doctor == min(all weights)`, asserts `doctor <` every user-package signal, and asserts the `cache`
tie **explicitly and visibly**.

### F8. Eight inputs, seven rows — `advisoryCoverage` renders as the vulnerable row's other half

Documented on `HealthProjection.rowOrder` and asserted.

### F9. `HealthMeasurement` added so a row can state what it does not know

Without it, "never renders 0 vulnerable for an unanswered scan" would have been **vacuously** true.
**Recorded in `design.md` at 13.4.**

### F10. `DoctorOutcome`/`DoctorUnavailableReason` are `Equatable`, not `Hashable`

`BrewProcessError` is `Equatable` only. The new types were narrowed rather than a shipped
`BrewProcess` type widened.

### F11. `DoctorParser.parse` takes no `exit`

An `exit` in the parser's signature would let two byte-identical captures produce unequal evidence.

### F12. Pre-existing: `DiskUsageSnapshot` encodes non-deterministically

`[DiskArea: DiskRootState]` encodes as a flat JSON array and `.sortedKeys` does not sort array
elements. Not caused by this change and not fixed here — the fix would touch `DiskUsageModels.swift`,
a binding zero-line-diff file. **Recorded in `design.md` at 13.4 as an open follow-up.**

### F13. **`ContentView` has never landed on Home** — `tasks.md` 9.1 and 12.1 are both wrong about it

Both tasks ask for "Home is still the landing section, asserted over the shell's default selection".
The shipped value is `@State private var section: AppSection = .browse` and has been since M1, so
Home has never been the section the app opens on. Changing it would be a user-visible behaviour
change no requirement in this delta asks for, and `design.md` HD9 rules it out by name ("No new
`@State` selection. `HomeView` is not touched").

Shipped asserting what this change actually owes — **Health did not take the landing spot, and this
change moved nothing** — with the literal `browse` pinned in both the unit test and the UI test, so a
future silent move fails rather than passes. **Open for the maintainer**: making Home the landing
section is a one-line change and its own decision.

### F14. 10.2's `.task` rule, narrowed honestly rather than satisfied literally

The Health section carries exactly **one** `.task`, and it rebuilds the pure projection when the
inputs change. `HealthProjection.build` takes one value and a date, so there is no seam in its scope
to reach. The test forbids a `.task` that **acquires** — `runDoctor`, `readLastUpdate`, `startPreview`,
`refresh`, a scan, a measurement, a sync — rather than forbidding `.task` outright, and it carries
both a positive anchor (the one block is found and calls `health.project`) and a violation control.

Per SH7's own wording only the **doctor run** must be user-initiated; the invocation-free last-update
reading joins the app's existing launch-and-activation refresh in `cellarApp`, which is asserted never
to call `runDoctor`.

### F15. Two UI fixtures were reading the developer's own machine

`--ui-testing-m5-health-unscorable` scored **63** on a machine where nothing had been measured.
`DiskUsageStore` and `SecurityStore.start()` load their cache files with no consent and no network,
and both pointed at the real `~/Library/Caches/Cellar/` files. Both are now redirected to per-launch
temporary paths under the Health fixture. Without that, the test passes on a fresh CI box and fails
on every real one — the worst kind of green.

## The Phase 4 quarantine result (binding invariant 1c)

`DoctorPayloadQuarantineTests` has **no GREEN step by design** — it must pass against shipped code,
and a failure would be a finding rather than a task. **It passed on first run, unchanged.**
`InstalledPayload`, `ServicesPayload` and `TapPayload` each still refuse a non-zero exit (at statuses
1, 2, 42 and 127) and still refuse a document that arrived on stderr; `BrewDoctorSource` still accepts
both. `openspec/specs/brew-execution/spec.md` is a 0-line diff.

## The LPM5 guard option chosen (11.6)

**Option A: name the app surface in `capabilitySources`.** The alternative — proving the surface
records snoozes only through `Sources/Persistence/MetadataStore.swift` — is a claim about what a file
does *not* reach and would hold vacuously the day a second write path is added.
`cellar/Installed/BulkActionBar.swift` is now in scope and is held to **both** the forbidden
comparator tokens and the security tokens, by a new test
(`noSnoozeCallerOutsideThisPackageCanEvadeTheGuard`). The reader is re-rooted at the repository, every
existing path is prefixed, the per-file anchor assertion is kept (a re-rooted read that opens nothing
must fail rather than pass), both violation controls survive, and the `Sources/Persistence`
whole-directory scan and `PackageMetadata.isSnoozed`'s string equality are untouched.

## Rollback note (13.5)

Two pairs revert **together or not at all**:

- **(a)** the II13 spec text with `BulkSelectionTests` and `ServiceSubmissionTests` — a partial revert
  that restores the spec text without the tests leaves the suite red;
- **(b)** `BulkSelection.swift` with `OperationCenterBulk.swift` — a partial leaves
  `commands(for:over:)` non-exhaustive and uncompilable.

`cellar/Health/` reverts as **deletions with zero `project.pbxproj` objects to remove** (synchronized
root group). `BulkActionBar.swift` and `InstalledListView.swift` revert together with the
`SnoozeGuardTests` re-rooting, because the guard names a file that would no longer exist. `Snooze`
rows already written by a bulk action survive a revert, stay valid, and stay individually
unsnoozable. `ReleaseNotesUITests` (4 cases / 7 failures, reproduced exactly at 13.1) stays
orchestrator-owned, is subtracted at verify, and is **not** diagnosed here.

## Deviations from design

F3, F4, F9, F10, F11, F13 and F14 are the substantive ones; each is a recorded deviation with its
reason, and F4, F7, F9, F12, F13 and F14 are written into `design.md` under *Apply-Time Amendments*.
Everything else follows `design.md` as written: non-throwing `DoctorSourcing` (HD1); stderr as the
document with `documentStream` provenance (HD2); behavioural both-directions quarantine (HD3);
compose-never-widen with all four zero-line diffs held (HD4); one-operation `FileMetadataAccess`
(HD5); the score in dependency-free `Catalog` (HD6); the proposed weights (HD7); `unknownInputs`
structurally inseparable with `fileprivate init` (HD8); pure `@concurrent` projection and `.health`
after `.cleanup` (HD9); pin and unpin as two independently derived verbs (HD10); bulk snooze on its
own app-side path, absent from `BulkSelection.Action` and `OperationCenter` (HD11).

Per-instance spies only — **no `CompositionRequestSpy` call site was added anywhere**, including in
`HealthCompositionTests`, which composes SecurityKit and is exactly the suite that would have hit its
false zero.

## Remaining

- [ ] **13.3** — surface every user-facing string authored in 10.5 and 11.7 to the maintainer for a
      wording review before the PR opens. Every string is reproduced verbatim in the batch-2 return
      summary. An executor cannot close a task whose acceptance is somebody else's.

## Batch 3 — verify remediation (bounded, post-verify)

Closes verify's single CRITICAL and its WARNING 1. **No production behaviour changed**: the only
non-test edit is a doc comment. 71 tasks all remain valid and none was re-ticked.

| Item | Where | Lines |
|---|---|---:|
| SH11 sc1/sc3 behavioural test + source-scan guard (5 `@Test`) | `cellarTests/HealthRemediationTests.swift` (new) | 153 |
| D4 comment corrected per F13 (comment-only) | `cellar/Shell/AppSection.swift` | 13 |
| Assertion rewritten to pin the corrected record | `cellarTests/AppSectionPlacementTests.swift` | 17 |
| Apply-Time Amendment | `openspec/changes/m5-health/design.md` | 14 |

**183 lines** for the four mandated items, **197** including the design amendment — inside the 200
hard bound.

`HealthComposition.command(for:)` had no test at all, so SH11 sc3 had no covering test and sc1's
second half was partial. Now pinned: all five remediation→command mappings over `allCases`; each
cleanup remediation carries **Cleanup's own** `requiresConfirmation` and `disclosure` and upgrade-all
**Installed's own** gate — ownership, not a re-issued copy; and a comment-stripped guard over
`cellar/Health/` with an anchor on the shipped routing, a sweep for eight bypass tokens, and a
violation control.

**The tests were proven to bite.** They pass unchanged against shipped code (the
`DoctorPayloadQuarantineTests` precedent), so a temporary mutation — `cleanupCache` → `.full` and a
`requiresConfirmation` read in `HealthView` — was applied and failed all three real-code tests, then
reverted byte-for-byte (SHA-256 `8723d938…` / `3ff7a472…` restored).

WARNING 1: the D4 note claimed "Home keeps the landing spot", disproved by F13, and
`AppSectionPlacementTests:175` pinned that wrong string while `:75` pinned `landing == "browse"`. RED
first (assertion rewritten → FAIL), then GREEN (comment corrected → PASS). `:75` untouched.

**Results**: CellarCore 1,655 tests / 198 suites / 1 known issue, exit 0 (unchanged — no CellarCore
edit). `cellarTests` **139 `@Test`** (134 → +5), TEST SUCCEEDED. SwiftLint clean on all three files.

**Still open**: verify WARNING 2 (`cellarApp.swift` initializer 156 lines vs limit 100), SUGGESTION 1
(F12 follow-up), SUGGESTION 2 (`ReleaseNotesUITests` 4/7 baseline), and task 13.3 (maintainer copy
review).

**Rollback**: delete `cellarTests/HealthRemediationTests.swift` and revert the two edits above. No
production behaviour to restore.

## Batch 4 — SH4 sc3 integration test (bounded, post-verify-2)

Closes the **one PARTIAL scenario** verify rev 2 left: SH4 sc3, "running doctor does not move the
fetch marker". Rev 2 returned FAIL with **zero CRITICAL** purely on that evidence gap, and offered two
exits — a maintainer ruling that probe U14 discharges it as manual verification, or one integration
test. **The user chose the test.** No production change, no task re-ticked, 71 tasks all still valid.

| Item | Where | Lines |
|---|---|---:|
| SH4 sc3 observation (1 `@Test`) | `Packages/CellarCore/Tests/BrewClientTests/DoctorIntegrationTests.swift` (new) | +111 |
| Apply-Time Amendment | `openspec/changes/m5-health/design.md` | +12 |
| This section, and the title line | `openspec/changes/m5-health/apply-progress.md` | +67 / −1 |

**191 changed lines** (additions + deletions), inside the 200 hard bound. `git diff --stat` cannot
measure any of the three — the test file, `design.md` and this file are all untracked — so the count
is the batch-3 `diff -u /dev/null <file>` reconstruction.

### Why a test and not another assertion

`DoctorCommandTests` and `DoctorSourceTests` already pin the mechanism exhaustively — one literal argv
element, classified `.read`, no environment override, no spine collaborator — and **not one of them
can see the marker**. The marker would be moved by Homebrew's *own* auto-update, inside a process no
argv assertion reaches. Only a run can observe it, which is why U14 had to measure it by hand.

### What it does

Placed in `BrewClientTests` because it is the only target that sees both `BrewClient` (the shipped
`BrewDoctorSource` and the internal `DoctorCommand`) and `DiskUsage` (the shipped reader).

- **Marker resolved, never spelled out** — through the shipped `HomebrewRepositoryLocator.repository`
  + `fetchMarkerName`, so the test exercises the same two-candidate probe the app uses. The suite gate
  needs that resolution synchronously and `DefaultBrewLocator.detect` is `async`, so the gate builds
  roots from the binary at `/opt/homebrew/bin/brew`; the test then **re-resolves from the detected
  installation and asserts the two agree**, so the shortcut cannot widen what is observed.
- **The pin is asserted, not re-applied** — `BrewEnvironment.current(commandOverrides:)` is read with
  `DoctorCommand.command.environmentOverrides` and checked for `HOMEBREW_NO_AUTO_UPDATE == "1"`. A
  regression that dropped the pin fails here rather than being papered over by a test that set it.
- **Reading via the shipped reader** — `HomebrewUpdateReader.lastUpdate(roots:now:access:)` with a
  single `now` for both readings, because the reading's `futureDated` arm is a function of it.
- **Three vacuous passes refused** — an unresolved marker (`before.date != nil`), an `.unavailable`
  doctor outcome (`#require(outcome.evidence)`), and a completed run that wrote no bytes.
- **Skips, never fails** — `.enabled(if: hasRealBrew && fetchMarker != nil)` and the `.realBrew` tag,
  the idiom `BrewIntegrationTests` established, so a machine with no Homebrew or a fresh checkout that
  has never fetched skips rather than fails.

### RED evidence

Genuine RED → GREEN, not approval. The assertion was written **inverted** (`after != before`) and run
first: **FAILED** at `:109` — `(after → .read(2026-08-07 05:45:27 +0000)) != (before → .read(2026-08-07
05:45:27 +0000))`, after **2.453 s** (a real doctor spawn, matching probe U10's 2–3 s). Every other
assertion passed in that same run, so the failure was the marker comparison alone. Flipped to
`after == before`: **passed after 1.785 s**. The inversion is the mutation proof — the assertion is
discriminating, and both readings are real `.read` dates rather than a matching pair of non-answers.

**Results**: CellarCore **1,656 tests / 199 suites / 1 known issue, exit 0** (baseline re-measured this
batch at 1,655 / 198 / 1 → exactly +1 test, +1 suite). SwiftLint clean on the new file. No app-target
change, so no `xcodebuild` run was required.

**Still open**: verify WARNING 2 (`cellarApp.swift` initializer 156 lines vs limit 100), SUGGESTION 1
(F12 follow-up), SUGGESTION 2 (`ReleaseNotesUITests` 4/7 baseline), SUGGESTION 3 (a comment naming
which assertion carries the weight in `aCleanupRemediationKeepsItsOwnersConfirmation`), and task 13.3
(maintainer copy review).

**Rollback**: delete `Packages/CellarCore/Tests/BrewClientTests/DoctorIntegrationTests.swift` and
revert the design amendment. Zero production lines to restore. Batch 1/2/3 boundaries unchanged.
