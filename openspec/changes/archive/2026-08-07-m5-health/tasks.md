# Tasks: Health Dashboard, `brew doctor` & Bulk Pin/Snooze (`m5-health`)

## Review Workload Forecast

| Field | Value |
|-------|-------|
| Naive bottom-up estimate | ~5,300 authored source+tests (line-item sum over the design's File Changes table) |
| Measured correction applied | **1.9–2.3×** — slice 1 delivered 3,619 against 1,500–2,100; slice 3 delivered 9,736 against 3,700–4,700. Slice 4 (7,438 against 6,500–9,500) is the **only** in-band forecast, and it was already deliberately widened |
| Estimated changed lines | **8,100–11,900 authored source+tests**; **10,300–14,700** including this change's OpenSpec lifecycle markdown |
| Split | CellarCore source 1,600–2,300 · CellarCore tests 3,400–4,800 · app source (`cellar/`) 1,300–1,900 · app tests (`cellarTests` + `cellarUITests`) 1,600–2,400 · fixtures + README + manifest 200–450 · `openspec/` 2,200–2,800 |
| Session review budget | **5,000** lines (`config.yaml` `review_budget_lines`) |
| 5,000-line budget risk | **High** — exceeded by 2.1–2.9× on the authored figure alone |
| 400-line budget risk | High |
| Chained PRs recommended | Yes (honest technical recommendation at this size) |
| Suggested split | PR 1 = Phases 0–8 (all of CellarCore) · PR 2 = Phases 9–13 (app layer, bulk snooze surface, E2E, close-out) |
| Delivery strategy | single-pr |
| Chain strategy | size-exception |

Decision needed before apply: No
Chained PRs recommended: Yes
Chain strategy: size-exception
400-line budget risk: High

**Why the recommendation and the strategy differ, stated rather than reconciled away.** At
8,100–11,900 authored lines the honest recommendation is chained PRs. The maintainer has already
**pre-accepted `size:exception`** for this slice (obs #7532 decision 2) precisely so `sdd-tasks`
forecasts honestly without stopping to re-ask, as slices 3 and 4 did at this guard. So the recorded
chain strategy is `size-exception` and `Decision needed before apply` is `No`. The two-batch cut
below stays **pre-agreed as a mid-apply contingency**: if the real diff crosses the budget while
applying, cut at **Phase 9** — nothing in Phases 0–8 depends on the app layer.

One bottleneck the cut introduces, named rather than discovered later: the `installed-inventory`
delta spans **both** batches (II13's bulk pin/unpin in Phase 8, II13's bulk-snooze clauses in Phase
11). Cutting at Phase 9 means II13 is only fully satisfied once PR 2 lands, and the `local-package-metadata`
LPM5 guard widening (11.6) covers a surface that does not exist until PR 2. The delta must not be
archived between the two.

### Suggested Work Units

| Unit | Goal | Likely PR | Focused test command | Runtime harness | Rollback boundary |
|------|------|-----------|----------------------|-----------------|-------------------|
| 1 | All of CellarCore: doctor fixtures + command + evidence + parser + non-throwing source, the HD3 quarantine proof, the `FileMetadataAccess` seam + invocation-free update reader, the pure score, the projection, and the bulk pin/unpin widening with its two test rewrites (Phases 0–8) | PR 1 | `FAST --filter "Doctor\|HomebrewUpdateReader\|HealthScoring\|HealthWeights\|HealthProjection\|BulkSelection\|BulkFanOut\|ConfirmationDisclosure\|ServiceSubmission\|StoreCache\|CleanupParser"` | Replay the captured `warnings-run/` streams offline through `DoctorParser` and reproduce U10's grouping byte-for-byte; then one live `brew doctor` under `HOMEBREW_NO_AUTO_UPDATE=1` with `FETCH_HEAD` mtime compared before and after (re-runs U14's measurement against the shipped `.read` classification) | `git revert` the merge. `Sources/BrewClient/Doctor*.swift`, `Sources/DiskUsage/{FileMetadataAccess,HomebrewUpdateReader}.swift` and `Sources/Catalog/Health*.swift` delete cleanly — no existing type is widened. `BulkSelection.swift` + `OperationCenterBulk.swift` revert **together** (a partial leaves `commands(for:over:)` non-exhaustive and uncompilable), and with them the II13 spec text and the two rewritten tests |
| 2 | App layer: the `.health` placement obligations, `cellar/Health/`, the eight composition mappings, the bulk-snooze surface + `BulkActionBarPresentation` + the LPM5 guard widening, E2E and close-out (Phases 9–13) | PR 1 (or PR 2 if cut) | `APP --only-testing:cellarTests/HealthCompositionTests`, then `APP`, then `FULL` | Launch: the sidebar shows Health between Services and Security and **Home is still the landing section**; the score renders a number beside its `unknownInputs` (or "nothing could be scored" when nothing was answered, never a 0 and never a 100); "Run doctor" re-measures and the row claims no fix; a mixed pinned selection shows independent pin and unpin controls with their own counts, and a snooze control whose label implies no duration | Delete `cellar/Health/` — **zero** `project.pbxproj` objects to remove (synchronized root group, `cellar/Discover/` precedent). Revert `AppSection.swift`, `ContentView.swift`, `cellarApp.swift`, `BulkActionBar.swift`, `InstalledListView.swift`, and the `SnoozeGuardTests` re-rooting. `Snooze` rows already written stay valid and individually unsnoozable |

If cut, PR 2 base = PR 1 branch (feature-branch-chain).

### Legend

- Paths under `Packages/CellarCore/` unless prefixed with `cellar/`, `cellarTests/`, `cellarUITests/` or `openspec/`.
- `FAST` = `swift test --package-path Packages/CellarCore` (optionally `--filter <Suite>`).
- `APP` = `xcodebuild test -project cellar.xcodeproj -scheme cellar -destination 'platform=macOS,arch=arm64' -only-testing:cellarTests`.
- `FULL` = `xcodebuild test -project cellar.xcodeproj -scheme cellar -destination 'platform=macOS,arch=arm64'`.
- `BUILD` = `xcodebuild build -project cellar.xcodeproj -scheme cellar -destination 'platform=macOS,arch=arm64'`.
- Spec tags — **SH1**–**SH11** (`system-health`, ADDED-only, 11 req / 51 sc), **II13**/**II14** (`installed-inventory`, **DESTRUCTIVE**), **LPM4**/**LPM5** (`local-package-metadata`).
- Design tags **HD1**–**HD11** (`design.md` → Architecture Decisions).
- Threat-matrix tags — **TM1** subprocess integration, **TM2** argument composition, **TM3** untrusted subprocess payload, **TM4** filesystem path resolution, **TM5** irreversible mutation scope. Executable-file classification, VCS and PR automation are `N/A` and have no task.
- Strict TDD (`config.yaml` `testing.strict_tdd`): every `RED` task lands a failing test; the following `GREEN` task makes it pass. No production line without a red test.
- **D4 is carried here, not by a requirement.** The tenth `AppSection` case, Home's retention and the resolution of `cellar/Shell/AppSection.swift:17–20` were removed from the spec by orchestrator ruling (obs #7535 rev 2, brewfile/release-notes precedent). Phase 9 is their only home — nothing downstream will find them anywhere else.
- Binding: `@concurrent` goes on its **own line before** `public static func` on `DoctorParser.parse` and `HealthProjection.build` (M1 convention — the other order does not compile).
- Binding: `Package.swift` is a **0-line diff**. `BrewClientTests` already declares `resources: [.copy("Fixtures")]`, so `Fixtures/Doctor/` needs no manifest edit.
- Binding: **never** add a call site to `SecurityCompositionSupport.swift:181`'s `CompositionRequestSpy` — its `nonisolated(unsafe) static var count` + `install()` reset is the shipped false-zero shape. Per-instance UUID-tagged ledgers under `Mutex` only.

---

## Phase 0: Frozen baseline and the zero-line-diff contract

- [x] 0.1 Record the baseline at `main` `7d48779`: total `@Test` count across `Tests/`, `cellarTests/`, `cellarUITests/`; and the known pre-existing `ReleaseNotesUITests` failure baseline (**4 cases / 7 failures**). That baseline is **orchestrator-owned and diagnosed after this change closes** (obs #7532 decision 3) — verify subtracts it, this change does not touch it.
- [x] 0.2 Record the binding zero-line-diff list, checked again at 13.2: `Packages/CellarCore/Package.swift`, `cellar.xcodeproj/project.pbxproj`, `Tests/CatalogTests/CatalogFootprintTests.swift`, `Sources/DiskUsage/HomebrewRoots.swift`, `Sources/DiskUsage/DiskUsageModels.swift`, `Sources/DiskUsage/DiskUsageCache.swift`, `openspec/specs/brew-execution/spec.md`.

## Phase 1: Doctor fixtures (**SH3**, **TM3**)

- [x] 1.1 Create `Tests/BrewClientTests/Fixtures/Doctor/warnings-run/` from the **captured** probe (obs #7531, scratchpad `u10-probe/run1`): `stdout.txt` (1 B, a bare newline) and `stderr.txt` (622 B), byte-exact, neither trimmed nor re-wrapped.
- [x] 1.2 Create `Fixtures/Doctor/clean-run/` — **hand-authored** (exit 0, "Your system is ready to brew.") and **visibly marked as hand-authored in its own directory and in the README**. This machine has real warnings, so exit 0 could not be captured (U10). An unmarked hand-authored fixture is indistinguishable from a capture and must not ship.
- [x] 1.3 Create `Fixtures/Doctor/odd-grouping/` — **hand-authored hostile**: an empty `Warning: ` headline, an indented detail line before any warning, two adjacent warnings with no detail, and a non-UTF-8 byte run.
- [x] 1.4 Create `Fixtures/Doctor/README.md` to the `Fixtures/Bundle` standard exactly — capture date, Homebrew version, binary path, exact argv excluding `brew`, exit status, per-stream byte counts and provenance (captured vs hand-authored, per directory) — plus `probe-manifest.txt` with a SHA-256 per stream.
- [x] 1.5 RED create `Tests/BrewClientTests/DoctorFixtureManifestTests.swift` (+ fixture loading helper), the `SecurityKitTests/FixtureManifestTests` idiom: every stream named in `probe-manifest.txt` exists, loads from `Bundle.module`, and hashes to the recorded SHA-256; and the hand-authored marking for `clean-run/` and `odd-grouping/` is asserted **present**. A silently re-saved fixture fails the suite.

## Phase 2: Doctor command, evidence and parser (**SH1**, **SH3**, **SH4**, **HD1**, **HD2**, **TM2**, **TM3**)

- [x] 2.1 RED create `Tests/BrewClientTests/DoctorCommandTests.swift` (**TM2**, **SH4**): the argv is exactly `["doctor"]`, classified `.read`, a compile-time constant with no stored `String`, no parameter, no interpolation and no joining; never `/bin/sh -c`.
- [x] 2.2 GREEN create `Sources/BrewClient/DoctorCommand.swift` — `BrewCommand.read(["doctor"])`.
- [x] 2.3 RED create `Tests/BrewClientTests/DoctorParserTests.swift`, the HD2 grammar row by row over synthesised `Data`: preamble before the first `Warning: `; `Warning: <headline>` opens a block; other non-empty lines while a block is open append to that block's `detail` **in order**; an empty headline still records the block plus `.emptyWarningHeadline`; an orphan detail line lands in `unknownLines` plus `.orphanDetailLine`; non-UTF-8 bytes land in `unknownLines` **as `Data`** plus `.undecodableLine`.
- [x] 2.4 RED same file over `warnings-run/`: the preamble is captured, each warning carries its ordered detail lines, `warningCount` equals the number of blocks, and **every line is accounted for** — grouped or unknown, none dropped.
- [x] 2.5 RED same file over `clean-run/`: `warningCount == 0` **present, not absent**; groups empty; `isPartial == false`; no parse issue recorded.
- [x] 2.6 RED same file over `odd-grouping/`: an unrecognised report yields empty groups, the whole document in `unknownLines` and `isPartial == true` — **never a failure and never an empty document**; the unknown count is `0` present-not-absent when there is nothing unknown.
- [x] 2.7 RED same file, determinism and provenance (**SH3**): the evidence is derivable from the bytes alone — no process, no clock, no store in the signature; two byte-identical captures produce **equal** evidence; `rawStdout` and `rawStderr` stay separate `Data` fields and are **never concatenated, interleaved or trimmed**; `DoctorParserProvenance.documentStream ∈ {stdout, stderr, both, neither}` records where the payload actually arrived; `parserVersion == 1` travels with every value.
- [x] 2.8 GREEN create `Sources/BrewClient/DoctorEvidence.swift` (`DoctorEvidence`, `DoctorWarning`, `DoctorParseIssue`, `DoctorParserProvenance`, `DoctorOutcome`, `DoctorUnavailableReason`) and `Sources/BrewClient/DoctorParser.swift` (`@concurrent` on its own line before `public static func parse`, reusing `CleanupParser.lines(in:)`).

## Phase 3: The non-throwing doctor source (**SH1**, **SH4**, **HD1**, **TM1**)

- [x] 3.1 RED create `Tests/BrewClientTests/DoctorSourceTests.swift` over a per-instance `RecordingProcessLauncher`: `DoctorSourcing.run(using:)` has **no `throws` at all**; exit 1 → `.issues(evidence)`; exit 0 → `.clean(evidence)`; cancellation → `.unavailable(.cancelled)`; a spawn failure (`BrewProcessError`) → `.unavailable`. A **completed** non-zero run can never reach `.unavailable` — that is the whole inversion, and the signature is what enforces it.
- [x] 3.2 RED same file: the document is read from **stderr**; a newline-only stdout is **not** malformed; both raw streams reach the evidence separately and unconcatenated; exactly three typed outcomes exist (`clean | issues | unavailable`) and `unavailable` covers only no-document-at-all, never warnings.
- [x] 3.3 GREEN create `Sources/BrewClient/DoctorSource.swift` — a nonisolated `Sendable` struct over `any ProcessLaunching` with `withTaskCancellationHandler` (`CleanupPreviewSource` shape).
- [x] 3.4 RED same file (**SH4**, **TM1**): a doctor run submits **no** mutation, writes **no** history entry, invalidates **no** installed state and triggers **no** Homebrew update — recording seams for each; and the fetch marker must not move because doctor ran (U14 measured this live; this pins the shipped classification).

## Phase 4: The quarantine proof (**SH2**, **HD3**, **TM3**)

- [x] 4.1 RED create `Tests/BrewClientTests/DoctorPayloadQuarantineTests.swift`: for **each** of `InstalledPayload.payload`, `ServicesPayload.payload` and `TapPayload.payload`, a **non-zero** exit carrying a well-formed JSON document on stdout still throws `.commandFailed(status:message:)`. The doctor rule did not leak.
- [x] 4.2 RED same file, the other direction: for each of the same three, an **exit-0** run with blank stdout and the document on **stderr** still throws `.malformedPayload`/`.blankOutput`. stderr still never enters a JSON document.
- [x] 4.3 RED same file: the doctor source is not re-derived from the trio's template — both halves (the trio's two refusals and doctor's two acceptances) are asserted, so a "simplification" in **either** direction fails a test. Behavioural, not a text scan. `openspec/specs/brew-execution/spec.md` stays a 0-line diff; the licence lives in the new capability's Provenance (**D7**).

## Phase 5: The invocation-free last-update reading (**SH5**, **SH6**, **HD4**, **HD5**, **TM4**)

- [x] 5.1 RED create `Tests/DiskUsageTests/HomebrewUpdateReaderTests.swift` over a fake `FileMetadataAccess` with **no disk**: `HomebrewRepositoryLocator` probes `<prefix>/Homebrew/.git` **then** `<prefix>/.git`, in that order; the first resolving probe wins; a non-resolving probe is **not** an error. Both install shapes covered (U11: `/opt/homebrew` and the `/usr/local` shape).
- [x] 5.2 RED same file, the four typed cases: `read(Date)`, `absent`, `unreadable`, `futureDated(Date)`. **No placeholder, no `Date.distantPast`, no zero date, no negative age**; the reader never throws; age is derived only from `read`; `futureDated` is its own case and is **never clamped to zero** (a wrong clock must not read as perfectly fresh); all three non-answers reach the score as unanswered.
- [x] 5.3 RED same file (**TM4**): resolving and reading spawn **zero** processes, open no network, and trigger or schedule no update — asserted with a recording `ProcessLaunching`. The probe list is a closed two-element list under `HomebrewRoots.prefix`; no user-supplied path and no environment read.
- [x] 5.4 GREEN create `Sources/DiskUsage/FileMetadataAccess.swift` (`FileMetadataAccess`, `FileModificationDate`, `SystemFileMetadataAccess`) and `Sources/DiskUsage/HomebrewUpdateReader.swift` (`HomebrewRepositoryLocator`, `HomebrewLastUpdate`). It **composes** `HomebrewRoots` and widens nothing (**HD4**).
- [x] 5.5 RED regression (**HD4**): existing `StoreCacheTests` and `CleanupParserTests` run **unedited** and pass; a previously written `DiskUsageCache` file still decodes; `DiskRootsIdentity`'s stored-property set is unchanged and `DiskUsageSnapshot.roots` encodes identically; `CleanupParser.currentlyOnDiskBytes`'s `roots == expectedRoots` gate still attributes orphan bytes. Zero-line diffs on `HomebrewRoots.swift`, `DiskUsageModels.swift`, `DiskUsageCache.swift`.

## Phase 6: The score (**SH9**, **SH10**, **HD6**, **HD7**, **HD8**)

- [x] 6.1 RED create `Tests/CatalogTests/HealthScoringTests.swift`: `HealthScoring.score(_:)` is a pure function of one `HealthInputs` value — **no** store, clock, filesystem, network or subprocess in the signature **or** the implementation — and is deterministic across repeated calls.
- [x] 6.2 RED same file, answered-inputs-only (**D3**): an unanswered input contributes **neither penalty nor credit** — it leaves **both** sums in `Σ_answered wᵢ·hᵢ / Σ_answered wᵢ` — and is recorded in `unknownInputs`. Verified by holding one input constant and flipping another between `.unknown` and each of its answered ends.
- [x] 6.3 RED same file, structural inseparability: `HealthScore` is unrepresentable without `unknownInputs`; its memberwise initialiser is **not public**, so `HealthScoring` is the only producer; **no accessor yields the number alone**; and any unknown means the value is never reported clean or complete — **including a 100**.
- [x] 6.4 RED same file: nothing answered → `.unscorable(unknownInputs:)`, which is **neither 0 nor 100** and carries no number at all; otherwise the value is in `0...100` inclusive.
- [x] 6.5 RED create `Tests/CatalogTests/HealthWeightsTests.swift` (**SH10**): each `HealthContribution` names its input, its weight and its resulting points; every weight is **readable from the value**, not implicit in the arithmetic; the contributions account for the number by the stated rule; the weights sum to 100; `doctor` is **lower than `outdated`** — and lower than every signal describing the user's own packages — which is what **SH10** actually requires ("the doctor contribution's weight is readable AND it is lower than the weight applied to the user's own outdated packages"); and an unknown input is **never** a weighted contribution. *(Reworded at 13.4 after apply. The original said "strictly the lowest", which HD7's own table contradicts: `cache` and `doctor` both weigh 5. The maintainer ruled the tie **stands** and the task text was wrong; `doctor == min(all weights)` and the `cache` tie are both asserted explicitly and visibly in `HealthWeightsTests` rather than left to be discovered — finding F7.)*
- [x] 6.6 RED same file: each `HealthThresholds` normalisation endpoint is a named constant and behaves linearly between its two ends (outdated 0 → 25% of installed; vulnerable 0 → 5% of **answered**; advisoryCoverage all-answered → 50%; lastUpdate ≤1 day → 30 days; orphans and duplicateVersions 0 → 20; cache ≤1 GiB → 20 GiB; doctor 0 → 10 warnings); monotonic per input.
- [x] 6.7 GREEN create `Sources/Catalog/HealthInputs.swift` (`HealthInput`, `HealthSignal`, `HealthUnknownReason`, `HealthRemediation`) and `Sources/Catalog/HealthScore.swift` (`HealthWeights`, `HealthThresholds`, `HealthScore`, `HealthScoreState`, `HealthScoring`). Structural: `Sources/Catalog/Health*.swift` imports **no** `BrewClient`, `SecurityKit`, `DiskUsage` or `Persistence` — the build graph is the proof (**HD6**).

## Phase 7: The projection (**SH7**, **SH8**, **SH11**, **HD9**)

- [x] 7.1 RED create `Tests/CatalogTests/HealthProjectionTests.swift`: `HealthProjection.build(inputs:now:)` spawns no process, triggers no sync, scan, measurement or refresh, and starts **no timer and no polling loop**; it is computable off the main actor from its inputs alone.
- [x] 7.2 RED same file (**SH8**): **seven** rows — outdated, vulnerable, orphans, duplicate versions, cache size, Homebrew staleness, doctor. Each states what it does not know and **names its reason**: `notCovered`/`unavailable`/partial coverage is never "0 vulnerable"; unknown orphans is never "0 orphans"; an incomplete disk or a failed root is never a complete size; absent/unreadable/future-dated is never an age. A partially answered signal reports **both halves**.
- [x] 7.3 RED same file (**SH11**): `HealthRemediation` is exactly `{upgradeAll, autoremove, cleanupCache, runDoctor, none}` — **no new mutating verb**, no `brew update` remediation, and no repair offered for a doctor warning. A row with no remediation offers `none` rather than an inert control, and each offered verb comes from the row that motivated it.
- [x] 7.4 RED same file: the score and its caveat are read off **one value** — the surface cannot render the number without `unknownInputs` in hand; unmeasured signals stay unmeasured (no computed default, no triggering the measurement).
- [x] 7.5 GREEN create `Sources/Catalog/HealthProjection.swift` — `HealthContent`, `HealthRow`, and `@concurrent` on its own line before `public static func build` (`DiscoverProjection` idiom).

## Phase 8: Bulk pin and unpin (**II13**, **II14**, **HD10**, **TM5**) — the destructive pair

- [x] 8.1 RED **REWRITE** `Tests/BrewClientTests/BulkSelectionTests.swift:70–79` (never delete): `allCases == [.upgrade, .uninstall, .pin, .unpin]`, `count == 4`, and the title scan keeps the three verbs still prohibited — `["snooze", "favorite", "note"]`. The title scan is the sharp edge: `case pin` with `title == "Pin"` fails the loop even after the count is fixed. Record the byte-sliced replaced range in the delta.
- [x] 8.2 RED **REWRITE** `Tests/BrewClientTests/ServiceSubmissionTests.swift:213–231` (never delete): **only** the two `allCases ==` / `count ==` lines change. Its load-bearing half at `:225–228` — looping `allCases` against `ServiceCommand.allVerbs` to prove no **service** verb entered the package vocabulary — and `ServiceRowControl.allCases.count == 5` survive **verbatim**. SM4 sc5's intent is the point of the test and is what must be kept.
- [x] 8.3 RED `BulkSelectionTests`, the new eligibility: `pinnable` and `unpinnable` are derived **independently**; a mixed pinned/unpinned selection offers **both** verbs with honest counts and guesses about neither (II13 sc5); casks **never** enter either set; an all-cask selection leaves both **unavailable rather than inert**; an empty eligible set is unavailable; a non-empty set acts on exactly that set. `anEmptySelectionOffersNothing` (`:83–95`) needs **no edit** and must still pass.
- [x] 8.4 RED `ConfirmationDisclosureTests`: bulk pin and bulk unpin raise **no confirmation** — `request(_:)` already returns `nil` for both, so `submitBulk` submits directly and DD1's `first.disclosure` fix is untouched.
- [x] 8.5 RED `BulkFanOutTests`: `commands(for:over:)` fans out `MutationCommand.naming(id, MutationCommand.pin)` and its `.unpin` twin over exactly the eligible set, never over ineligible members.
- [x] 8.6 RED structural (**II13**): the bulk mutation vocabulary is **exactly** upgrade, uninstall, pin and unpin, enumerated **by case and by title** — no snooze, favorite, note or service verb. This is the assertion both rewritten tests answer to.
- [x] 8.7 GREEN `Sources/BrewClient/BulkSelection.swift` **and** `Sources/BrewClient/OperationCenterBulk.swift` in one step (they revert together or not at all): two `Action` cases, `pinnable`/`unpinnable` stored id lists, two arms each in `ids(for:)`/`isAvailable(_:)`/`label(for:)`, two arms in `commands(for:over:)`, and **both** doc comments' "exactly two cases" reasoning rewritten. `BulkActionBar` iterates `allCases`, so both buttons appear with zero structural edit.

## Phase 9: The `.health` placement obligations (**D4** — carried by tasks, not by a requirement)

- [x] 9.1 RED create `cellarTests/AppSectionPlacementTests.swift`: `AppSection.allCases.count == 10`; `.health` sits **after `.cleanup` and before `.security`**, which places it between Services and Security in sidebar order as PRD §5 requires; and **`.home` is still `allCases.first` and still the landing section** — asserted over the shell's default selection, not merely over case order.
- [x] 9.2 RED same file: every exhaustive `AppSection` switch covers `.health` **without a `default` arm** — a structural scan (comments stripped, positive anchor + violation control, `SnoozeGuardTests` idiom) over `cellar/ContentView.swift`'s two switches and every other `switch` over an `AppSection`. A `default:` in an `AppSection` switch fails the test, because a `default` is what would let the eleventh case ship unrendered.
- [x] 9.3 GREEN `cellar/Shell/AppSection.swift`: add `case health` after `.cleanup` and before `.security`, with its title, `heart.text.square` symbol and `sidebar-health` identifier. **REWRITE the deferred-decision comment at `:17–20` as the resolved decision** — "Home keeps the landing spot; settled in slice 5 as D4, Health is its own section and Home is not folded into it" — and **do not delete it**. A silent deletion is indistinguishable from never having decided.
- [x] 9.4 GREEN `cellar/ContentView.swift`: a `.health` arm in **both** switches — content = `HealthView`, detail = `HealthBreakdownPanel`. No new `@State` selection; `HomeView` untouched.

## Phase 10: The Health section and its composition (**SH7**, **SH8**, **SH11**, **HD9**)

- [x] 10.1 RED create `cellarTests/HealthCompositionTests.swift` with a **per-instance UUID-tagged ledger under `Mutex`**: every app-side mapping into `HealthSignal` (`DoctorOutcome`, `CoverageTotals`, `SecurityScanState`, `CleanupOrphans`, `CleanupReportedTotal`, `DiskUsageSnapshot`/`DiskRootState`, `InstalledBrowse`, `HomebrewLastUpdate`) sends `notCovered`, `unavailable`, `.partial`, `.failed`, `.cancelled`, `.unknown` and `isComplete == false` to `.unknown(reason)` — **never** to `.answered(1.0)`. **Do not** add a call site to `SecurityCompositionSupport.swift:181`'s `CompositionRequestSpy`.
- [x] 10.2 RED same file (**SH7**): rendering Health launches no brew process and triggers no sync; Health owns **exactly two** acquisitions (the doctor run and the last-update reading), both explicitly initiated; **no view `.task` calls `HealthStore.refresh()`**; the other six inputs are read from resident state.
- [x] 10.3 GREEN create `cellar/Health/` as a **new synchronized root group** (0-line `project.pbxproj` diff, `cellar/Discover/` precedent): `HealthView.swift`, `HealthRowView.swift`, `HealthBreakdownPanel.swift`, `HealthStore.swift` (`@MainActor @Observable`, the two acquisitions only, explicit `refresh()`, no timer), `HealthComposition.swift` (the eight mappings and the `HealthRemediation` → `MutationCommand.upgradeAll` / `CleanupCommand(.autoremove)` / `CleanupCommand(.global)` / doctor re-run map).
- [x] 10.4 GREEN `cellar/cellarApp.swift`: construct and inject the doctor source and the update reader once.
- [x] 10.5 Author the **user-facing copy** as named constants (`SecurityConsentSheet` precedent): the score-breakdown labels (each input's name, weight, points and the visible `answeredWeight` denominator, plus the "nothing could be scored" phrasing); the doctor row's de-emphasis copy reflecting Homebrew's own "just used to help the maintainers with debugging"; and the **"Run doctor" copy stating it re-measures and makes no fix, repair or resolve claim** (**SH4**). This task authors content, not code; 10.6 proves its shape and 13.3 reviews its wording.
- [x] 10.6 RED same file: each string is a **named constant, not a body literal**; the "Run doctor" constant contains none of `fix`, `repair`, `resolve`; and the rendered score and its `unknownInputs` come from **one value**, so the caveat cannot be dropped in the view layer.

## Phase 11: The bulk-snooze surface and the LPM5 guard (**LPM4**, **LPM5**, **II13**, **HD11**, **TM5**)

- [x] 11.1 RED create `cellarTests/BulkSnoozeTests.swift` (**LPM4**): snoozing N packages records **one snooze per package, each naming that package's own offered version** (`installed.catalogVersion`) — no shared version, no reuse across packages, no batch identity and no group record; the result is **indistinguishable from individual snoozes performed in any order**.
- [x] 11.2 RED same file: a package with **no offered version records nothing** — no placeholder, no empty string, no borrowed version; and the action compares, orders or ranks nothing. `createdAt` is provenance only and reaches no suppression projection.
- [x] 11.3 RED same file (**II13**, **HD11**): bulk snooze appears **nowhere** in `BulkSelection.Action` or `OperationCenter`; it submits no operation, writes no history entry and spawns no process; its eligibility is outdated ∧ not already snoozed at the offered version; an empty eligible set leaves it **unavailable rather than inert**; and `BrewClient` still does not link SwiftData.
- [x] 11.4 RED create `cellarTests/BulkActionBarTests.swift`, part (a) — extract `BulkActionBarPresentation` so labels, counts, roles and enablement are provable **without rendering** (`PackageInspectionRow` idiom). **II14**: each verb's label counts **its own** eligible set (pin 2/2, unpin 1/1, snooze 4/4 over one mixed selection), each count derived from the same projection that verb's action submits.
- [x] 11.5 RED same file, part (b) — a `TapShippingProofTests`-style **bounded-control guard** over `cellar/Installed/BulkActionBar.swift`: enumerate the expected button labels and assert **no unbulked verb string** appears (`favorite`, `note`, and every `ServiceCommand` verb). Include a positive anchor and a violation control, or the scan passes loudest when it reads nothing at all.
- [x] 11.6 RED **WIDEN** `Tests/BrewClientTests/SnoozeGuardTests.swift` (**LPM5**): the guard's enumerated scope must follow **every** snooze caller, including the new app-side surface. Its `source(at:)` reader is rooted at `Packages/CellarCore` (`:55–58`) and **cannot open `cellar/Installed/BulkActionBar.swift`** — re-root it at the repository root and then either name the app surface in `capabilitySources`, or prove the surface records snoozes **only** through `Sources/Persistence/MetadataStore.swift` (already in scope). Keep the per-file **anchor** assertion so a re-rooted read that opens nothing fails instead of passing; keep both violation controls; leave the `Sources/Persistence` whole-directory scan and `PackageMetadata.isSnoozed`'s string equality untouched. Record the chosen option in `design.md` at 13.4.
- [x] 11.7 GREEN `cellar/Installed/BulkActionBar.swift`: the `BulkActionBarPresentation` value, plus the snooze button **beside** — never inside — the `ForEach(BulkSelection.Action.allCases)`, calling `MetadataStore.snooze(id, offering:)` once per package. The copy names the count and **never a duration, period, expiry or interval**; it says the badge stays hidden **until a different version is offered**.
- [x] 11.8 GREEN `cellar/Installed/InstalledListView.swift`: pass `metadata` and the snooze handler through to the bar. No other call site changes.

## Phase 12: End-to-end

- [x] 12.1 RED then GREEN in `cellarUITests`: the sidebar shows `sidebar-health` **between Services and Security**, and **Home is still the section the app lands on**; the score renders beside its `unknownInputs` (and "nothing could be scored" renders instead of a number when nothing was answered); the "Run doctor" control claims no fix. Identifiers on **leaf views, never a container root** (A9).
- [x] 12.2 RED then GREEN in `cellarUITests`: a mixed pinned selection shows independent pin and unpin controls carrying their own counts; an all-cask selection shows both **unavailable, not inert**; the bulk snooze control's label implies no duration.

## Phase 13: Close-out

- [x] 13.1 Run `FAST`, `APP`, `FULL` and `BUILD` green. The `@Test` count is strictly above the 0.1 baseline, and `git diff -U0` over `Tests/`, `cellarTests/` and `cellarUITests/` removes **no** assertion line except the two recorded II13 rewrites (8.1, 8.2) whose byte-sliced replaced ranges are in the delta.
- [x] 13.2 `git diff --numstat` proves every path in 0.2 is still a **zero-line diff**: `Package.swift`, `project.pbxproj`, `CatalogFootprintTests.swift`, `HomebrewRoots.swift`, `DiskUsageModels.swift`, `DiskUsageCache.swift`, `openspec/specs/brew-execution/spec.md`.
- [x] 13.3 **Surface every user-facing string authored in 10.5 and 11.7 to the user for a wording review before the PR opens** (slice-2/3/4 precedent): the score-breakdown labels and the "nothing could be scored" phrasing, the doctor de-emphasis and "Run doctor" copy, and the bulk-snooze no-duration copy. The tests prove shape; they do not prove the wording is honest enough.
      Presented verbatim to the user 2026-08-07 (score surface, breakdown, signal names, unknown
      reasons, doctor copy, rows/remediation, summaries, bulk-snooze copy); **accepted as-is** with no
      rewording. Same round ruled F13: **Browse remains the landing section** — the D4 record corrects
      to "Home remains a section; Browse remains the landing" (obs #7532).
- [x] 13.4 Record in `design.md` under *Apply-Time Amendments*: the LPM5 guard option chosen in 11.6, the resolution of the two recorded Open Questions (the HD7 weights stand as proposed, and `.health`'s exact neighbour), and any other evidence-forced change — recorded, never absorbed silently.
- [x] 13.5 Record the rollback note: the two pairs that revert **together or not at all** — (a) the II13 spec text with `BulkSelectionTests` and `ServiceSubmissionTests`; (b) `BulkSelection.swift` with `OperationCenterBulk.swift`. `cellar/Health/` reverts as deletions with **zero** pbxproj objects. `Snooze` rows already written survive a revert and stay individually unsnoozable. `ReleaseNotesUITests` (4 cases / 7 failures at `7d48779`) stays orchestrator-owned, is subtracted at verify, and is **not** diagnosed here.
