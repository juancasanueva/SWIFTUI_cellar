```yaml
schema: gentle-ai.verify-result/v1
evidence_revision: sha256:dba16789581b7966a9d76a0983250582ed6773c5952e96aa9776eb2ebf9e793d
verdict: pass_with_warnings
blockers: 0
critical_findings: 0
requirements: 25/25
scenarios: 101/101
test_command: swift test --package-path Packages/CellarCore
test_exit_code: 0
test_output_hash: sha256:d1926f04482b2c0444f864a996624c33b4333caed3616ec38f1894541cd883b7
build_command: xcodebuild build -project cellar.xcodeproj -scheme cellar -destination 'platform=macOS,arch=arm64'
build_exit_code: 0
build_output_hash: sha256:20ee2b283e5016f53a0ab343507ec19af13e41d0c3c6ea4653aa776e3696e2ce
```

## Verification Report

**Change**: m2-local-metadata-history (M2-3)
**Branch / head**: `feature/m2-local-metadata-history` @ `743e739` (13 commits on `main` @ `8c9bc2a`; working tree clean, unmodified by this phase)
**Version**: 6 delta specs — 25 requirements / 101 scenarios (counted from the retrieved specs, not from the launch prompt)
**Mode**: Strict TDD

### Completeness

| Metric | Value |
|--------|-------|
| Tasks total | 90 |
| Tasks complete | 90 |
| Tasks incomplete | 0 |

`rg -c '^\s*- \[x\]'` → 90; `rg -c '^\s*- \[ \]'` → 0. Task 9.2's manual-verification evidence block is present in `tasks.md:488-502` and matches Engram `#7120` verbatim in substance.

### Build & Tests Execution

**Build**: PASSED

```text
xcodebuild build -project cellar.xcodeproj -scheme cellar -destination 'platform=macOS,arch=arm64'
** BUILD SUCCEEDED **
```

**Tests**: PASSED — 555 tests / 73 suites, 1 known issue

```text
swift test --package-path Packages/CellarCore
Test run with 555 tests in 73 suites passed after 5.306 seconds with 1 known issue.
```

The single known issue is the deliberate one from task 3.5, verified in the log:

```text
Test "Finishing a call that never launched fails this test instead of crashing the suite"
  recorded a known issue at OperationCenterCancelTests.swift:183:37:
  Expectation failed: launcher.launchedProcesses.indices.contains(index)
```

This is the harness proving it *fails* rather than traps. It is expected, matches the apply report, and is not a regression.

**Lint**: `swiftlint` → `Found 60 violations, 6 serious in 184 files` — byte-identical violation counts to the recorded `main` baseline (60 / 6). Zero new findings. The file count rose (151 → 184) only because `.build/` DerivedSources are now present; every violation in the tail is in generated `resource_bundle_accessor.swift`, not in authored code.

**Coverage**: not available — no coverage tool configured for this package. Not a failure.

### Spec Compliance Matrix

#### local-package-metadata — 7 requirements / 21 scenarios

| Requirement | Scenario | Test | Result |
|---|---|---|---|
| LPM1 keyed by (kind, name) | Metadata survives a relaunch | `SchemaTests > metadataSurvivesAReopen` (on-disk) | COMPLIANT |
| LPM1 | Kind is part of the key | `SchemaTests > kindIsPartOfTheKey` | COMPLIANT |
| LPM1 | Metadata outlives an uninstall | `SchemaTests > metadataOutlivesAnUninstall` | COMPLIANT |
| LPM2 favorite flag | The favorite flag round-trips | `MetadataStoreTests > theFavoriteFlagRoundTrips` | COMPLIANT |
| LPM2 | Toggling favorite spawns nothing | `MetadataStoreTests > togglingFavoriteSpawnsNothing` | COMPLIANT |
| LPM2 | An unknown package is not favorite | `MetadataStoreTests > anUnknownPackageIsNotFavorite` | COMPLIANT |
| LPM3 note verbatim, never searched | A note round-trips verbatim | `MetadataStoreTests > aNoteRoundTripsVerbatim` | COMPLIANT |
| LPM3 | An empty note is no note | `MetadataStoreTests > anEmptyNoteIsNoNote` | COMPLIANT |
| LPM3 | Search does not match note contents | `InstalledFilterFavoritesTests > noteTextIsNeverSearched` | COMPLIANT |
| LPM4 snooze scoped to a version | Snoozing records the version it applies to | `MetadataStoreTests > snoozingRecordsTheOfferedVersion` | COMPLIANT |
| LPM4 | A snooze carries no time component | `MetadataStoreTests > aSnoozeCarriesNoTimeComponent` | COMPLIANT |
| LPM4 | Re-snoozing replaces rather than accumulates | `MetadataStoreTests > reSnoozingReplaces` | COMPLIANT |
| LPM5 badge suppression | Suppressed while offered version unchanged | `SnoozeProjectionTests > theBadgeIsSuppressedWhileUnchanged` | COMPLIANT |
| LPM5 | A newer offered version revives the badge | `SnoozeProjectionTests > aNewerOfferedVersionRevivesTheBadge` | COMPLIANT |
| LPM5 | Revision-suffixed or older also revives | `SnoozeProjectionTests > anyDifferentOfferedVersionRevivesTheBadge` (5 args) + `noVersionComparatorExists` | COMPLIANT |
| LPM5 | Unsnoozing restores the badge immediately | `SnoozeProjectionTests > unsnoozingRestoresTheBadgeImmediately` | COMPLIANT |
| LPM5 | A snoozed package is still listed as installed | `SnoozeProjectionTests > aSnoozedPackageIsStillListed` | COMPLIANT |
| LPM6 cold store degrades | An empty store changes nothing | `SnoozeProjectionTests > anEmptyStoreChangesNothing` | COMPLIANT |
| LPM6 | An unreadable store does not break the inventory | `MetadataStoreTests > anUnopenableContainerDegrades` (real unopenable path) | COMPLIANT |
| LPM7 machine-local + migration | No sync or network surface exists | `MigrationTests > noSyncOrNetworkSurfaceExists`, `persistenceImportsNoNetworking`, `metadataWritesIssueNoRequest` (URLProtocol spy) | COMPLIANT |
| LPM7 | An earlier schema version migrates without data loss | `MigrationTests > aV1StoreMigratesToAVersionThatAddsAField` | COMPLIANT |

#### installation-history — 7 requirements / 21 scenarios

| Requirement | Scenario | Test | Result |
|---|---|---|---|
| IH1 one durable entry per mutation | A successful mutation writes one complete entry | `OperationCenterHistoryTests > aSuccessfulInstallSubmitsOneCompleteDraft` + `HistoryRecorderTests > aDraftMapsToACompleteRow` | COMPLIANT |
| IH1 | Failed and cancelled mutations are recorded too | `OperationCenterHistoryTests > everyTerminalOutcomeIsRecordedAsItself` (failed / busy / cancelled) | COMPLIANT |
| IH1 | Nothing is written before the terminal outcome | `OperationCenterHistoryTests > nothingIsWrittenBeforeTheTerminalOutcome` | COMPLIANT |
| IH1 | History survives a relaunch | `HistoryRecorderTests > recordedEntriesSurviveAReopen` (on-disk) | COMPLIANT |
| IH2 grouped vs fanned-out | Upgrade all is one grouped entry | `OperationCenterHistoryTests > upgradeAllWritesOneGroupedEntry` + `noInventoryDiffingProducesARecord` | COMPLIANT |
| IH2 | A bulk selection produces one entry per package | `BulkFanOutTests > aBulkUninstallFansOutInSelectionOrder` (3 drafts, in order) | COMPLIANT |
| IH3 Cellar-submitted only | An externally installed package is not logged | `OperationCenterHistoryTests > anExternalInstallIsNeverLogged` | COMPLIANT |
| IH3 | Read-only work writes nothing | `OperationCenterHistoryTests > readOnlyWorkWritesNothing` | COMPLIANT |
| IH4 append-only, keep-all | Nothing is evicted as entries accumulate | `HistoryStoreTests > nothingIsEvictedAsEntriesAccumulate` (750 entries / 3 sessions) | COMPLIANT |
| IH4 | A later mutation appends rather than amends | `HistoryStoreTests > aLaterMutationAppends` | COMPLIANT |
| IH4 | Retiring an execution record does not touch history | `HistoryRecorderTests > retiringAnExecutionRecordLeavesTheEntryIntact` (real `BrewRunner`) | COMPLIANT |
| IH5 searchable, newest first | Entries are ordered newest first | `HistoryStoreTests > anEmptySearchReturnsEverythingNewestFirst` | COMPLIANT |
| IH5 | Searching by package name narrows the list | `HistoryStoreTests > searchingByNameNarrows` (case-insensitive `WGET`) | COMPLIANT |
| IH5 | Searching by verb narrows the list | `HistoryStoreTests > searchingByVerbNarrows` | COMPLIANT |
| IH5 | A search matching nothing is empty and non-destructive | `HistoryStoreTests > aSearchMatchingNothingIsNonDestructive` | COMPLIANT |
| IH6 confirmed all-or-nothing clear | A confirmed clear empties the history | `HistoryStoreTests > clearingEmptiesOnlyTheHistory` + manual 9.2(d) | COMPLIANT |
| IH6 | Declining deletes nothing | manual 9.2(d-addendum), recorded 2026-08-03 (commit `3bf14fd`): with one history row present, Clear dialog opened, **Cancel** pressed, row remained | COMPLIANT |
| IH6 | Clearing history leaves local metadata intact | `HistoryStoreTests > clearingEmptiesOnlyTheHistory` (favorite/note/snooze re-read) + manual 9.2(d) | COMPLIANT |
| IH6 | No per-entry delete affordance exists | `HistoryStoreTests > noPerEntryDeleteControlExists` + `HistoryRecorderTests > theOnlyControlIsCopy` | COMPLIANT |
| IH7 recording failure is inert | An absent recorder does not affect the operation | `OperationCenterHistoryTests > aRecorderFailureNeverReachesTheOperation(.absent)` | COMPLIANT |
| IH7 | A failing recorder does not affect the operation | `OperationCenterHistoryTests > aRecorderFailureNeverReachesTheOperation(.failing)` vs `.working` | COMPLIANT |

#### installed-inventory — 4 requirements / 22 scenarios

| Requirement | Scenario | Test | Result |
|---|---|---|---|
| II8 filters composed (MODIFIED) | Installed filter narrows browse results | `InstalledFilterTests` / `InstalledFilterCompositionTests` (pre-existing, still green) | COMPLIANT |
| II8 | Not-installed filter is the complement | as above | COMPLIANT |
| II8 | Outdated filter excludes self-updating casks | as above | COMPLIANT |
| II8 | With no inventory the filters are disabled | as above | COMPLIANT |
| II8 | Catalog filter set declares no installed predicate | `InstalledFilterFavoritesTests > theCatalogFilterSetDeclaresNoMembershipPredicate` (Mirror over `SearchFilters`, incl. `favorite`) | COMPLIANT |
| II8 | No catalog control enabled but inert under installed mode | `InstalledFilterCompositionTests` (pre-existing) | COMPLIANT |
| II8 | The outdated mode obeys the same rule | as above | COMPLIANT |
| II8 | The favorites filter narrows the list | `InstalledFilterFavoritesTests > theFavoritesFilterNarrows` | COMPLIANT |
| II8 | The favorites filter composes with the others | `InstalledFilterFavoritesTests > theFavoritesFilterComposes` | COMPLIANT |
| II8 | With no metadata the favorites filter is disabled | `InstalledFilterFavoritesTests > withNoMetadataTheFilterIsDisabled` | COMPLIANT |
| II12 snoozed leave outdated | Absent from the set and the count | `SnoozeProjectionTests > aSnoozedPackageLeavesTheSetAndTheCount` | COMPLIANT |
| II12 | A changed offered version returns it | `SnoozeProjectionTests > aChangedOfferedVersionReturnsItToTheSet` (2 args) | COMPLIANT |
| II12 | The outdated browse filter agrees with the list | `SnoozeProjectionTests > theOutdatedFilterAgreesWithTheList` | COMPLIANT |
| II12 | A snooze does not hide the package | `SnoozeProjectionTests > aSnoozedPackageIsStillListed` | COMPLIANT |
| II13 multi-select ordered | Selection preserves order | `BulkSelectionTests > theSelectionPreservesOrder` | COMPLIANT |
| II13 | Deselecting removes exactly one package | `BulkSelectionTests > deselectingPreservesRelativeOrder` | COMPLIANT |
| II13 | A package that leaves the inventory leaves the selection | `BulkSelectionTests > aDepartedPackageLeavesTheSelection` + app `.onChange(of: entries)` intersection | COMPLIANT |
| II13 | Only upgrade and uninstall are offered | `BulkSelectionTests > onlyUpgradeAndUninstallAreBulkEligible` (`CaseIterable`, exhaustive) | COMPLIANT |
| II13 | An empty selection offers no enabled bulk control | `BulkSelectionTests > anEmptySelectionOffersNothing` + `anIneligibleControlIsUnavailable`; manual 9.2(c) saw "Upgrade 0" disabled | COMPLIANT |
| II14 label counts what it submits | Label matches submitted set under default filters | `BulkSelectionTests > theAnnouncedCountEqualsTheSubmittedSet` | COMPLIANT |
| II14 | Toggling the dependency filter moves both together | `BulkSelectionTests > theDependencyToggleMovesBothTogether` + `BulkFanOutTests > theCountEqualsTheSubmission` (4 combinations) | COMPLIANT |
| II14 | Snoozed packages excluded from label and submission | `BulkSelectionTests > aSnoozedPackageLeavesBothTheCountAndTheSubmission` | COMPLIANT |

#### package-mutation — 3 requirements / 13 scenarios

| Requirement | Scenario | Test | Result |
|---|---|---|---|
| PM3 confirmation gate (MODIFIED) | Uninstall asks first and shows the exact command | `OperationCenterProjectionTests` (pre-existing) | COMPLIANT |
| PM3 | Declining spawns nothing | `OperationCenterProjectionTests` (`decline(request)`, items empty) | COMPLIANT |
| PM3 | Zap is confirmed separately | `OperationCenterProjectionTests` (pre-existing) | COMPLIANT |
| PM3 | Non-destructive mutations run without confirmation | `BulkFanOutTests > aBulkUpgradeSubmitsDirectly` + pre-existing | COMPLIANT |
| PM3 | A bulk uninstall confirmation names every selected package | `BulkFanOutTests > oneConfirmationNamesEveryPackage` | COMPLIANT |
| PM3 | Declining a bulk uninstall submits none of it | `BulkFanOutTests > decliningSubmitsNoneOfIt` | COMPLIANT |
| PM8 bulk fan-out | A bulk uninstall expands to one invocation per package | `BulkFanOutTests > aBulkUninstallFansOutInSelectionOrder` (exact argvs, order, no argv names 2 packages) | COMPLIANT |
| PM8 | A mid-batch failure attributes to one package | `BulkFanOutTests > aMidBatchFailureStopsNothingElse` | COMPLIANT |
| PM8 | Cancelling one operation leaves the rest queued | `BulkFanOutTests > cancellingOneLeavesTheRestQueued` | COMPLIANT |
| PM8 | No other verb accepts a selection | `BulkFanOutTests > noOtherVerbAcceptsASelection` (+ structural scan of `OperationCenterBulk.swift`) | COMPLIANT |
| PM9 validated at construction | An empty or whitespace name is rejected | `MutationCommandTargetTests > anUnsafeNameProducesNoArgv` (10 hostile names × 3 ctors) | COMPLIANT |
| PM9 | A name that looks like an option is rejected | as above — `MutationName.isSafe` rejects `hasPrefix("-")`; see Correctness | COMPLIANT |
| PM9 | No construction path skips validation | `MutationCommandTargetTests > noEnumCaseTakesABarePackageID` + `theSafetyRuleIsDefinedOnce` | COMPLIANT |

#### operation-activity — 3 requirements / 14 scenarios

| Requirement | Scenario | Test | Result |
|---|---|---|---|
| OA1 queue enumerable (MODIFIED) | Pending operations visible before they run, in run order | `OperationCenterProjectionTests` (pre-existing) | COMPLIANT |
| OA1 | An operation's identity is stable across its states | as above | COMPLIANT |
| OA1 | Each enumerated operation carries the exact argv | as above | COMPLIANT |
| OA1 | Terminal operations remain enumerable for the session | as above | COMPLIANT |
| OA1 | **A retired execution record does not remove the queue item** | `OperationCenterRetentionTests > aTerminalItemSurvivesItsExecutionRecordNoLongerBeingReported` | COMPLIANT |
| OA3 cancel (MODIFIED) | Cancelling a pending operation spawns nothing | `OperationCenterCancelTests` + pre-existing | COMPLIANT |
| OA3 | Cancelling the running operation lets the queue proceed | pre-existing `OperationCenterTests` | COMPLIANT |
| OA3 | No reorder or remove affordance exists | pre-existing (`ActivityItem.Control` enumeration) | COMPLIANT |
| OA3 | **Cancelling while detached still stops the process** | `OperationCenterCancelTests > aDetachedCancelSignalsTheProcessAndSettlesOnlyAtTheRealTerminal` | COMPLIANT |
| OA3 | **A detached cancel does not release the gate early** | `OperationCenterCancelTests > aDetachedCancelStartsNothingAndForcesNoResnapshotBeforeTheTerminal` | COMPLIANT |
| OA6 one entry per terminal | A successful operation records once | `OperationCenterHistoryTests > aSuccessfulInstallSubmitsOneCompleteDraft` | COMPLIANT |
| OA6 | A cancelled operation records its cancellation | `OperationCenterHistoryTests > everyTerminalOutcomeIsRecordedAsItself` | COMPLIANT |
| OA6 | Nothing is recorded before the terminal outcome | `OperationCenterHistoryTests > nothingIsWrittenBeforeTheTerminalOutcome` | COMPLIANT |
| OA6 | A failing recorder does not change what the queue reports | `OperationCenterHistoryTests > aRecorderFailureNeverReachesTheOperation` (parameterised) | COMPLIANT |

#### brew-execution — 1 requirement / 10 scenarios

| Requirement | Scenario | Test | Result |
|---|---|---|---|
| BE1 serialized mutations (MODIFIED) | Two mutations never overlap | `SerializationTests` (pre-existing) | COMPLIANT |
| BE1 | Reads proceed during a mutation | `SerializationTests` (pre-existing) | COMPLIANT |
| BE1 | Cancelling a queued mutation spawns nothing | `CancellationTests` (pre-existing) | COMPLIANT |
| BE1 | Queued mutations are enumerable before they run | `QueueProjectionTests > queuedMutationsAreEnumerableBeforeTheyRunInFIFOOrderWithTheirArgv` | COMPLIANT |
| BE1 | Identity is stable and distinguishes identical submissions | `QueueProjectionTests` (pre-existing) | COMPLIANT |
| BE1 | Enumerating does not perturb scheduling | `QueueProjectionTests` (pre-existing) | COMPLIANT |
| BE1 | **Records stop accumulating** | `RetentionTests > drainedTerminalRecordsStopAccumulatingOnceTheirHandlesDie` | COMPLIANT |
| BE1 | **A terminal operation not yet drained is still answerable** | `RetentionTests > aTerminalRecordAnswersExitAfterItsExecutionResourcesAreReleased` + `aCompactedRecordStillAnswersFault` | COMPLIANT |
| BE1 | **Retirement never touches a pending or running operation** | `RetentionTests > retirementLeavesTheRunningAndPendingOperationsEnumeratedInOrder` + `aRetiredOperationIsNeverReportedPendingOrRunning` | COMPLIANT |
| BE1 | **An unchanged phase is not republished** | `QueuePublicationTests > repeatedPublicationOfTheSamePhaseYieldsNothingBetweenRealTransitions` | COMPLIANT |

**Compliance summary**: **100 / 101 scenarios COMPLIANT, 0 PARTIAL, 0 FAILING, 1 UNTESTED.**

### Correctness (Static Evidence — spot checks demanded by the launch brief)

| Check | Status | Evidence |
|---|---|---|
| G5: no version comparator anywhere | CONFIRMED | Independent repo-wide scan of `Packages/CellarCore/Sources` + `cellar/` for `versionCompare\|isNewer\|isOlder\|precedes\|.numeric\|NumericSearch\|compare(` returns only: `PackageMetadata.swift:37` (a *comment* explaining the absence), and two `precedes` functions — `PackageSearchIndex.swift:235` (install-count/name ranking) and `InstalledModels.swift:176` (`lhs.name < rhs.name`, then kind). **Neither compares versions.** No comparator exists. |
| G5 structural scan is not vacuous | CONFIRMED | `SnoozeProjectionTests > noVersionComparatorExists` reads two real source files, strips comments, asserts 9 forbidden tokens absent — **and carries a positive anchor**: `#expect(source.contains("snoozedVersion == candidate"))`. If the read returned empty or the rule were rewritten, the anchor fails. Not vacuous. |
| Spec-tightened validator: a name beginning with `-` is rejected | CONFIRMED | `MutationCommand.swift:104-107` — `MutationName.isSafe`: `guard !name.isEmpty, !name.hasPrefix("-") else { return false }; return !name.contains(where: \.isWhitespace)`. Matches the spec's three rejections (empty, whitespace-only, leading `-`) exactly, and `PackageTarget.init?` is the single gate `FormulaID`/`CaskID` are expressed over. |
| Threat row — user free text into the persisted store | CONFIRMED, genuinely asserts | `MetadataStoreTests > aHostileNoteReachesNoArgv`: stores `"; rm -rf / --force $(whoami) \`id\` && echo pwned"`, then **submits a real mutation alongside it** so "no argv" is asserted against argv that exists (`launchCount == 1`, `allArguments == ["install","--formula","wget"]`), then checks 7 distinctive fragments are absent. Not a vacuous negative. |
| Threat row — persisted argv is display-only | CONFIRMED, asserts | `HistoryRecorderTests > aStoredRowCannotBecomeACommand`: reads all three `Persistence` sources, strips comment lines, asserts `-> MutationCommand`, `MutationCommand(`, `brewCommand`, `PackageTarget(` all absent. Companion `theOnlyControlIsCopy` positively asserts `record.controls == [.copyCommand]` and `commandText == argv.joined(separator: " ")`. See SUGGESTION 1 on anchor symmetry. |
| D3 — no `fetchLimit` on the history query | CONFIRMED | Repo-wide `rg 'fetchLimit'` over `Sources` + `cellar/` returns exactly one hit: `HistoryStore.swift:117`, a **comment** stating why there is none. Enforced by `HistoryStoreTests > nothingIsEvictedAsEntriesAccumulate` on comment-stripped source. |
| D5 — equality rule | CONFIRMED | See G5 rows. |
| D6 — ownership-based retention, cap 200 | CONFIRMED | `BrewRunner.swift:17` `public static let defaultRetainedTerminalRecords = 200`, exactly D6 R3's pin. `release(_:)` is called from `BrewOperation.deinit` (ownership, not timing) and `evictRetiredRecords()` filters `isCompacted && isReleased`, sorts by `ordinal`, and drops only the overflow. Matches R1/R2/R3 as designed. |
| D7 — grouped `upgradeAll` + Cellar-only history | CONFIRMED | `upgradeAllWritesOneGroupedEntry` (packageID nil, verb `upgradeAll`, argv `["upgrade"]`), `noInventoryDiffingProducesARecord` (structural), `anExternalInstallIsNeverLogged` + live manual 9.2(c). |
| D8 — displayed-row-order selection | CONFIRMED | `InstalledListView.reconcileOrder(with:)` at lines 115-122 is the design's two-step diff verbatim: `order.removeAll { !current.contains($0) }` then `entries.map(\.id).filter { current.contains($0) && !order.contains($0) }` — appended in **displayed-row order**, never `Set` order. `BulkSelection` takes `[PackageID]` and publishes `[PackageID]`, never a `Set`. |
| Every changed `.swift` under 400 lines | CONFIRMED | Independently measured across all 67 changed files: zero exceed 400. |
| Architecture guards | CONFIRMED | `Package.swift`: `Persistence` depends on `BrewClient` and **nothing depends back on it**; `Catalog` declares no `BrewProcess` dependency. |

### Coherence (Design) — the six deviations, assessed

| # | Deviation | Verdict | Reasoning |
|---|---|---|---|
| 1 | `BrewRunner` retention cap is injectable, shipped default 200 | **Benign refinement** | The shipped default is `BrewRunner.defaultRetainedTerminalRecords == 200`, exactly what D6 R3 pins. The parameter is a test seam only — task 7.7 uses `retainedTerminalRecords: 0` to make retirement observable without a 260-operation loop. Shipped behaviour is unchanged. |
| 2 | `naming(_:_:)`'s closure parameter is `(PackageTarget) -> MutationCommand` | **Benign refinement** | Every call site is unchanged. This is precisely what makes D9's claim ("no enum case takes a bare `PackageID`") a compiler fact rather than a convention, and it is asserted by `MutationCommandTargetTests > noEnumCaseTakesABarePackageID`. |
| 3 | `ActivityItem` gained `versions: VersionTransition?` | **Benign — effectively required** | D7 mandates `submit(_:versions:)` and forbids snapshot diffing; the item is the only carrier from submission to the terminal funnel. One immutable `@ObservationIgnored` stored property. Proven by `theTransitionIsTheOneIntendedAtSubmission` and `anUnknownTransitionIsRecordedAsAbsent`. |
| 4 | `OperationCenter.swift` split at 408 lines into `OperationCenterBulk.swift` | **Benign — mandated elsewhere** | Not in design's File Changes, but `tasks.md` requires a 400-line check before each phase's verify step, and `type_body_length` (error severity, default 350) was already exceeded. Behaviour-preserving; validated by a full-suite run either side with no behaviour edit in the same step. Both files now 318 / 191 lines. Carries SUGGESTION 2. |
| 5 | `cellar/Browse/PackageMetadataSection.swift` is a new file | **Benign — mandated elsewhere** | Same 400-line rule; `PackageDetailView.swift` was already 330 lines and is now 336. Design says `PackageDetailView.swift \| Modify`, which the split honours in substance. |
| 6 | `confirm(_:)` returns `[ActivityItem]` rather than `ActivityItem?` | **Benign — effectively required by the spec** | PM3's amended requirement ("Confirming it MUST submit the whole selection") is not expressible with an `ActivityItem?` return over a three-package selection. `ConfirmationRequest` stores head + tail (`command` + `additional`), so non-emptiness is a **type fact** and every existing `request.command` call site compiles unchanged. |

**No deviation is contract drift.** All six either implement a spec clause the design under-specified, or were forced by a `tasks.md` gate the design did not anticipate. Each is documented in the apply report and in the code.

Additional coherence checks: D3 (`@MainActor @Observable` over `mainContext`, no `@Query`, no `@ModelActor`) — confirmed by `MetadataStore`/`HistoryStore` construction in the suites; D4 (degraded store is a state, never a crash) — confirmed by `anUnopenableContainerDegrades` against a genuinely unopenable path; D2 (three independent models, no relationships) — confirmed by `theModelsAreIndependent` and `metadataAndHistoryAreUnlinked`.

### TDD Compliance

| Check | Result | Details |
|-------|--------|---------|
| TDD Evidence reported | YES | Two full "TDD Cycle Evidence" tables in `apply-progress` (#7119), run 1 and run 2 |
| All tasks have tests | YES (with two declared exceptions) | Phase 8 (app-target UI) and phase 9 (docs/gates) are untested by design, per design's own "Testing Strategy"; task 9.2 is the substitute and was executed |
| RED confirmed (test files exist) | YES | Every test file named in both tables exists on disk and was executed in this run |
| GREEN confirmed (tests pass) | YES | 555/555 pass; every file named in the tables appears in the passing-test extraction |
| Triangulation adequate | YES | Parameterised suites throughout: 5 offered-version cases (G5), 4 dependency×snooze combinations (II14), 3 recorder worlds (IH7), 2 bulk `Action` cases, 10 hostile names × 3 constructors (PM9) |
| Safety Net for modified files | YES | Every run-2 unit records its pre-change full-suite count (527/535/542/544/553), matching the monotone progression to 555 |
| Genuine RED recorded | YES | Task 6.11-6.12 records a real RED that exposed a fixture gap (deps=false ∧ snoozed=true), fixed by adding a fourth always-eligible package — visible in `BulkFanOutTests > theCountEqualsTheSubmission` |
| Absence-proving tests hardened | YES | The two tests that could not go RED (7.6 / IH3) each first prove the path genuinely ran (inventory `[wget]`→`[curl, wget]`, `source.callCount == 2`), then submit a real mutation through the same wired centre and see exactly 1 draft |

**TDD Compliance**: 8/8 checks passed.

### Test Layer Distribution

| Layer | Tests | Files | Tools |
|-------|-------|-------|-------|
| Unit (`BrewClientTests`, `BrewProcessTests`, `CatalogTests`) | ~508 | 89 | Swift Testing |
| Integration (`PersistenceTests` — in-memory **and** on-disk SwiftData, real `BrewRunner`) | 47 | 7 | Swift Testing + SwiftData |
| E2E / UI | 0 | 0 | not installed (`cellarUITests` skipped by project convention) |
| **Total** | **555** | **96** | |

Cross-referenced against capabilities: no test uses a tool absent from the toolchain. The E2E gap is a declared design decision, not an oversight — see SUGGESTION 3.

### Changed File Coverage

Coverage analysis skipped — no coverage tool detected for this package. Not a failure.

### Assertion Quality

Audited every test file created or modified by this change (`BulkFanOutTests`, `BulkSelectionTests`, `HistoryRecordingTests`, `InstalledFilterFavoritesTests`, `MutationCommandTargetTests`, `OperationCenterCancelTests`, `OperationCenterHistoryTests`, `OperationCenterRetentionTests`, `SnoozeProjectionTests`, all six `PersistenceTests`, `QueuePublicationTests`, `RetentionTests`).

- **Zero tautologies.** No `#expect(true)` or equivalent anywhere.
- **Zero ghost loops.** Every loop asserting over a collection either iterates a `CaseIterable` (`BulkSelection.Action.allCases`, non-empty by type) or a literal array of file names / fragments.
- **Zero orphan empty-checks.** Every `isEmpty` assertion has a companion non-empty assertion in the same test — the pattern is explicit and repeated: `anExternalInstallIsNeverLogged` proves the inventory moved *and* a real submission writes 1 draft; `aHostileNoteReachesNoArgv` proves argv exists before proving the note is not in it; `noteTextIsNeverSearched` proves the same query by name still finds the package.
- **Zero type-only assertions used alone.** `try #require(...)` is always followed by value assertions.
- **Zero smoke tests.** No `render`-and-nothing test exists.
- **Zero mock-heavy tests.** Fakes are protocol-conforming test doubles (`SpyProcessLauncher`, `FakeInstalledPayloadSource`, `RecordingHistoryRecorder`), and assertion counts exceed double count everywhere.
- **No implementation-detail coupling.** The structural source scans assert *declarations* (comment-stripped) rather than prose, which is the correct form for an "this API must not exist" claim.

**Assertion quality**: all assertions verify real behaviour. 0 CRITICAL, 0 WARNING.

### Quality Metrics

**Linter**: `swiftlint` — 60 violations / 6 serious, identical to the `main` baseline. **Zero new findings**, and no finding in any file this change created.
**Type checker**: covered by `swift build` (Swift 6 language mode, `.v6`, all targets) and `xcodebuild build` — both clean.

### Issues Found

**CRITICAL**: none open.

1. **[RESOLVED 2026-08-03]** ~~IH6 scenario "Declining deletes nothing" is UNTESTED~~ — closed by
   remediation option (a) exactly as prescribed below: the manual observation was performed and
   recorded in task 9.2(d-addendum) (commit `3bf14fd`) — with one Cellar-submitted history row
   present, the Clear history dialog was opened, **Cancel** pressed, and the row remained; nothing
   was deleted (user-observed). Scenario evidence is now 101/101. The original finding is preserved
   below for the record.

   **Original finding:** IH6 scenario "Declining deletes nothing" was UNTESTED — no passing covering test and no recorded manual substitute. It is the only one of 101 scenarios with neither form of runtime evidence. An exhaustive search of the test suite (`decline`, `clearAll`, `confirmClear`, `pendingClear`) finds the decline path exercised only for *mutation* confirmations (`OperationCenterProjectionTests`), never for the history clear; and the recorded 9.2(d) manual evidence covers only the **confirmed** clear ("confirmed Clear emptied history while favorites, notes and snoozes stayed intact"), never the Cancel path.

   This project does permit manual verification to stand in for UI-only scenarios — that is exactly what task 9.2 exists for — but the substitute was not performed for this scenario, so the allowance does not rescue it. Per the verification contract, a required scenario with no passing covering test is CRITICAL/UNTESTED, and incomplete scenario evidence cannot support a passing verdict.

   **Assessed risk of an actual defect: low.** `HistoryView.swift:39-53` places `history.clearAll()` inside the `role: .destructive` button only, while `Button("Cancel", role: .cancel)` sets `isClearing = false` and does nothing else — so declining is structurally incapable of deleting. `HistoryStoreTests > noPerEntryDeleteControlExists` separately proves no `func delete(`/`func remove(` exists on the store, and `clearAll()` is the store's only deleting API. The gap is in **evidence**, not in implementation.

   **Remediation is small and does not require re-opening the implementation.** Either (a) one manual observation appended to task 9.2(d) — open the clear dialog, press Cancel, confirm every entry is still listed; or (b) one store-level test asserting that not calling `clearAll()` leaves `records` intact after a dialog dismissal, paired with the existing structural proof. Option (a) is the cheaper and more faithful match to the scenario, since the decline affordance is UI-only.

**WARNING**:

1. **The review budget was overrun substantially.** `git diff --shortstat main...HEAD` -> **67 files changed, 8,370 insertions(+), 324 deletions(-)** = 8,694 changed lines including `openspec/` (the apply report's 8,678 figure predates commit `743e739`, which added the 9.2 evidence block — the two reconcile). Excluding `openspec/`, the apply report's 6,425 authored lines stand against a 4,000-5,400 forecast (~1.19x the top of the band) and roughly 8x the configured 800-line review budget — ~21x the shared 400-line default. `size:exception` with `single-pr` was **pre-accepted by the user before apply started**, so this is not itself a blocker, but it is stated rather than absorbed, and it should inform the M2-4 forecast: the overrun is concentrated in tests for a brand-new target with a new framework and no in-repo scaffolding to calibrate against.

**SUGGESTION**:

1. **Give the display-only structural scan a positive anchor**, matching the G5 scan's pattern. `HistoryRecorderTests > aStoredRowCannotBecomeACommand` is a pure-negative source scan: if `declarations(of:)` ever returned an empty string it would pass vacuously. In practice `try String(contentsOf:)` throws on a missing file and comment-stripping cannot empty a non-empty file, so the risk is remote — but one `#expect(source.contains("commandText"))` would make it structurally impossible, exactly as `#expect(source.contains("snoozedVersion == candidate"))` does for G5.

2. **`OperationCenter.pendingConfirmation` widened from `public private(set)` to `public internal(set)`** as a side effect of the 408-line split. Nothing outside `BrewClient` can write it, so the *external* contract is unchanged and no spec clause is touched — but the invariant "only the confirmation flow writes this" is now enforced by convention within the module rather than by the compiler. If the two files stay split, consider a small `ConfirmationBox` type owning the property so `private(set)` can be restored.

3. **Phase 8 (app-target UI) carries the residual risk and has no automated coverage.** Every *rule* the views read is a pure function proven in phases 5-7, and `xcodebuild build`/`test` prove it builds and links — but no automated test exercises the ordered-selection `.onChange` diff, the note editor's focus-loss commit, or the History search field. Task 9.2's walkthrough covered all three live and passed, including the bonus external-scope check (`brew install hello cowsay` surfaced in Installed via FSEvents and wrote **no** history rows, verifying IH3 against live brew). A small XCUITest for ordered multi-select would convert that manual evidence into a regression gate.

4. **`HistoryDraft.date` is `Date()` at the terminal, not an injected clock.** Nothing is flaky today because no test asserts a wall-clock value and ordering is asserted through explicitly-dated drafts. A future slice that needs deterministic timestamps should add an additive `clock:` seam on the centre rather than reaching for `Date()` again.

### Verdict

**PASS_WITH_WARNINGS** — 0 CRITICAL (1 resolved), 1 WARNING, 4 SUGGESTION.

The substance of this change is in excellent shape: all 90 tasks are complete; 555/555 tests pass (1 deliberate, documented known issue) and both builds succeed with zero new lint findings; the G5 no-comparator rule, the tightened `-`-prefix validator, and both threat-matrix RED tests are independently confirmed genuine and non-vacuous; every assertion audited verifies real behaviour; and all six design deviations are benign refinements with none constituting contract drift.

The original FAIL verdict (first admitted 2026-08-03) turned on a single evidence gap: IH6's "Declining deletes nothing" had neither a covering test nor a recorded manual observation. That gap was closed the same day by the prescribed remediation — the manual observation was performed and recorded in task 9.2(d-addendum) (commit `3bf14fd`) — bringing scenario evidence to **101/101**. No source changed between the two admissions; the delta is evidence, not implementation.

The remaining WARNING (review-budget overrun, pre-accepted via `size:exception`) and the four SUGGESTIONS stand as recorded and do not block archive.
