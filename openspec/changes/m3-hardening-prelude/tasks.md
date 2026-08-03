# Tasks: M3-0 — Hardening Prelude

Sources: `proposal.md` (ten items), `design.md` (D1–D9, 13 RED rows), `specs/` (5 MODIFIED
requirements / 24 scenarios). Baseline: `main` @ `3562cd1`. Artifact store: hybrid — this file wins;
Engram `sdd/m3-hardening-prelude/tasks` is an index.

**Strict TDD is active.** Every behavioural task is preceded by its RED test task. Inner loop:
`swift test --package-path Packages/CellarCore`. App-target wiring is proven by `xcodebuild build`
plus the reserved manual task 9.1 — never by a cross-target source scan.

## Review Workload Forecast

> Forecast against **2,000** — the session's declared `review_budget_lines`. `openspec/config.yaml:7`
> still reads `800` at the time this plan was written; **task 0.2 in this slice is what fixes it.**
> The `400-line budget risk` line below is the SDD default metric, not this project's budget.

| Field | Value |
|-------|-------|
| Estimated changed lines | **~1,480–1,930** (validator-corrected, measured spec deltas) |
| Against project budget (2,000) | Low–Medium — fits, with **no headroom** |
| 400-line budget risk | High (vs the SDD default 400 only) |
| Chained PRs recommended | No |
| Suggested split | Single PR, nine work-unit commits |
| Delivery strategy | single-pr |
| Chain strategy | pending (no chain selected — none is needed) |

Decision needed before apply: No
Chained PRs recommended: No
Chain strategy: pending
400-line budget risk: High

**Why no decision is owed.** `single-pr` normally forces a `size:exception` when the candidate is
over budget. This candidate is **under** the project's declared 2,000-line budget, so no exception is
requested and none should be granted. `Chain strategy: pending` means no chain strategy was selected,
not that one is outstanding.

Bucket split: src ~250 · tests ~450–650 · spec deltas **331 measured** · SDD markdown ~450–700.

**Drop-first order if the candidate approaches 2,000**: drop item **#7** (Phase 7, bulk displayed
order) first, then item **#8** (task 8.1, scan anchor). **Never #4** (Phase 5, single container) — it
carries the data-integrity tail. A `size:exception` request is the signal that scope leaked, not a
remedy.

### Suggested Work Units

| Unit | Commit | Goal | Focused test command | Runtime harness | Rollback boundary |
|------|--------|------|----------------------|-----------------|-------------------|
| 0a | `chore(sdd): reconcile the review budget to 2000` | config says what the session uses | N/A — config only | N/A — no runtime surface | `openspec/config.yaml` alone |
| 0b | `chore(sdd): archive the m2-mutations-installed exploration` | no M2 artifact outside `archive/` | N/A — file move | N/A — no runtime surface | the moved dir + one citation line |
| 1 | `fix(catalog): discard an older snapshot arriving after a newer one` | revision-ordered adoption | `swift test --package-path Packages/CellarCore --filter CatalogAdoptionTests` | 9.1 N/A — headless-provable | `CatalogStore.swift` guard + its suite |
| 2 | `fix(brew-process): answer an unknown operation with a typed unknown result` | no fabricated success | `swift test --package-path Packages/CellarCore --filter "ExitTests|ClassificationTests"` | 9.1 N/A — headless-provable | `BrewExit`/`BrewRunner`/`MutationOutcome` hunks |
| 3 | `fix(brew-client): record one entry when a submit has no runner` | one funnel, one entry | `swift test --package-path Packages/CellarCore --filter OperationCenterTests` | 9.1 N/A — headless-provable | `OperationCenter.submit` hunk |
| 4 | `fix(persistence): keep every entry and report why a clear failed` | failure survives reload | `swift test --package-path Packages/CellarCore --filter HistoryStoreTests` | 9.1 step (d) — inline surface, no alert | `HistoryStore` clear seam + `clearAll` |
| 5 | `fix(persistence): open one container and inject it into both stores` | one container | `swift test --package-path Packages/CellarCore --filter LocalStoresTests` | **9.1 step (a)** — mandatory | `LocalStores.swift` + `cellarApp` wiring |
| 6 | `fix(browse): commit an uncommitted note before switching packages` | no lost draft | `swift test --package-path Packages/CellarCore --filter NoteDraftTests` | **9.1 step (b)** — mandatory | `NoteDraft.swift` + `PackageMetadataSection` |
| 7 | `fix(installed): enter a bulk selection in displayed order` | submission matches what is seen | `swift test --package-path Packages/CellarCore --filter InstalledSectionsTests` | **9.1 step (c)** — mandatory | `InstalledSections.swift` + `InstalledListView` |
| 8 | `test(persistence): anchor the history structural scan` | scan cannot pass vacuously | `swift test --package-path Packages/CellarCore --filter HistoryRecorderTests` | N/A — test-only | one test function |

Phases are **sequential**. Inside a phase, RED strictly precedes its GREEN. Two ordering constraints
are hard: Phase 0 must be its own commit(s) at either end, and **Phase 5 (D6) must land before any
other task touches store wiring**. Phases 1–4 and 6–8 are file-disjoint from each other and could be
reordered by one writer, but not parallelised across worktrees.

---

## Phase 0: Housekeeping and baseline (2 commits, own boundary)

- [x] 0.1 Record the baseline on `3562cd1`: `swift test --package-path Packages/CellarCore` test/suite
      counts (expect 555 / 73) and `swiftlint --quiet` finding count. No commit — this is the number
      task 9.2 compares against.
      **Recorded**: `Test run with 555 tests in 73 suites passed after 5.272 seconds with 1 known
      issue.` · `swiftlint --quiet` = **60** findings.
- [x] 0.2 `openspec/config.yaml`: `:7` `review_budget_lines: 800 → 2000`, and `:59` prose
      "Forecast the 800-line review budget" → `2,000`. — proposal item #10. **Commit 0a.**
- [x] 0.3 `git mv openspec/changes/m2-mutations-installed openspec/changes/archive/2026-08-03-m2-mutations-installed`,
      then repoint the citation at `openspec/specs/installed-inventory/spec.md:547` to the archive
      path (**path text only — not a spec delta**). Re-run `rg m2-mutations-installed` and record the
      result: `openspec/changes/archive/**` reports and `m3-services-cleanup-taps/explore.md:4,:309`
      keep their historical references **unchanged** and are the expected residue. — item #10.
      **Commit 0b.**
      **Recorded**: after the move, `rg m2-mutations-installed` outside `openspec/changes/archive/**`
      and this change's own artifacts returns only `m3-services-cleanup-taps/explore.md:4,:309` (the
      untracked M3 umbrella, unchanged) and `openspec/specs/installed-inventory/spec.md:557`, which
      names the slice rather than citing a path. The `:547` path citation now reads the archive path.

## Phase 1: Catalog adoption ordinal — D1, D2 (item #1, `catalog-sync`)

- [x] 1.1 **RED** `Tests/CatalogTests/CatalogAdoptionTests.swift` —
      `anOlderSnapshotArrivingAfterANewerOneIsDiscarded`: adopt `B` fully, then adopt older `A`;
      expect `packageCount` still `B`'s and `indexBuildCount == 1`. — sc *"An older snapshot arriving
      after a newer one has installed is discarded"*.
- [x] 1.2 **RED** same file — `theAdoptedRevisionDoesNotRegressAfterDiscardingAnOlderSnapshot`:
      re-deliver `B` after the discarded `A`; expect no additional index build. — same scenario,
      second AND clause.
- [x] 1.3 **GREEN** `Sources/Catalog/CatalogStore.swift:179-183` — replace the equality guard with
      `snapshot.revision.ordinal > adoptedRevision?.ordinal`, older joins `adoptionInFlight` then
      returns, so the `adoptedRevision =` assignment at `:183` is unreachable for an older snapshot.
      Keep `adoptionSequence`/`installedSequence` (D2 — they guard build completion, not arrival).
      Equal ordinal keeps today's join-a-duplicate contract byte-for-byte.
- [x] 1.4 Add `.timeLimit(.minutes(1))` to the `@Suite("Catalog adoption", .serialized)` trait list.
      **Whole minutes only** — `.seconds(30)` traps at runtime. — proposal item #9.
      **Commit 1.**

## Phase 2: Typed unknown-operation result — D8 (item #6, `brew-execution`)

- [x] 2.1 **RED** `Tests/BrewProcessTests/ExitTests.swift` —
      `anUnknownOperationYieldsATypedUnknownResultRatherThanSuccess`: ask `exit(of:)` for an id never
      submitted; expect `reason == .unknownOperation`, `isSuccess == false`, nothing thrown, no
      `isReleased` involvement. — sc *"An unknown operation identity yields a typed unknown result"*.
- [x] 2.2 **GREEN** `Sources/BrewProcess/BrewExit.swift` — add `case unknownOperation` **inside the
      `Reason` declaration** (`:7-14`); a Swift enum case cannot be added in an extension. Then
      `extension BrewExit { public static let unknownOperation = BrewExit(status: -1, reason: .unknownOperation) }`.
      `-1` cannot collide with a wait status (0–255) or a signalled `128+n`, and `isSuccess`
      (`reason == .exited && status == 0`) makes the fabricated success unrepresentable.
- [x] 2.3 **GREEN** `Sources/BrewProcess/BrewRunner.swift:286` and `:291` — return
      `BrewExit.unknownOperation` instead of `BrewExit(status: 0, reason: .exited)`. Signature stays
      non-throwing, so the 30 callers via `BrewOperation.exit()` are untouched.
- [x] 2.4 **RED** `Tests/BrewClientTests/ClassificationTests.swift` —
      `anUnknownOperationClassifiesAsLaunchFailedNotSucceeded`: expect `.launchFailed`,
      `isFailure == true`, and that the terminal path still records an entry. — `brew-execution` sc
      above + `operation-activity` *"an identity the execution layer cannot answer"* clause.
      **Landed in a new `Tests/BrewClientTests/UnknownOperationTests.swift` instead**: adding it to
      `ClassificationTests` pushed that struct to 259 lines and raised a new `type_body_length`
      finding, which the zero-new-findings gate forbids. RED was observed in both locations. The
      "records an entry" half is proven end to end by task 3.1 through the single `finish` funnel.
- [x] 2.5 **GREEN** `Sources/BrewClient/MutationOutcome.swift` — add the `.unknownOperation` branch
      after the fault switch, mapping to the **existing** `.launchFailed` ("the process never
      started"). No new `MutationOutcome` case, no message or `summaryLabel` churn. **Commit 2.**

## Phase 3: No-runner submit through the funnel — D3 (item #2, `operation-activity`)

- [x] 3.1 **RED** `Tests/BrewClientTests/OperationCenterTests.swift` —
      `aSubmitWithNoRunnerRecordsExactlyOneHistoryEntry`: submit with `runner == nil`; expect outcome
      `.launchFailed`, recorder spy drafts `== 1`, gate terminals `== 1`. — sc *"An operation that
      never spawns still records once"*.
- [x] 3.2 **GREEN** `Sources/BrewClient/OperationCenter.swift:159-169` — hoist `gate?.begin()`
      **above** `guard let runner`, and replace the inline `item.queuePhase = …` / `item.settle(…)`
      pair with `finish(item, with: .launchFailed)` after setting the terminal queue phase. One
      `begin()` per submit, one `end()` per finish; `finish` is the only settle site and already
      writes the entry idempotently. **Commit 3.**

## Phase 4: Failed clear stays observable — D4, D5 (item #3, `installation-history`)

- [x] 4.1 **RED** `Tests/PersistenceTests/HistoryStoreTests.swift` —
      `aFailedClearKeepsEveryEntryAndReportsTheReason`: three entries, injected clear closure that
      throws; expect all three records present with original fields, `availability` unavailable
      **after** the reload, `lastError` set. — sc *"A failed clear leaves every entry present and
      reports why"* + *"A failed clear's reason survives the reload that follows it"*.
- [x] 4.2 **RED** same file — `aSuccessfulClearLeavesNoStaleFailureReason`: expect `records.isEmpty`,
      `lastError == nil`, `.available`. — sc *"A confirmed clear empties the history"*.
- [x] 4.3 **GREEN** `Sources/Persistence/HistoryStore.swift` — add the internal
      `init(container:clearing:)` seam (default closure = `try context.delete(model:) ; try save()`)
      and an internal `init(unavailable:)` mirroring `MetadataStore`'s. Injected seam, not a
      filesystem-permission fake (D5).
- [x] 4.4 **GREEN** `clearAll()` (`:181-191`) — on failure `rollback()` and capture the reason, call
      `reload()` **first**, then apply `availability = .unavailable(reason:)` and set `lastError`
      exactly as `append` does. Inline surface only: no alert, no retry affordance (settled Q1).
      **Commit 4.**

## Phase 5: One container, both stores — D6 (item #4) — **before any other store wiring**

- [x] 5.1 **RED** `Tests/PersistenceTests/LocalStoresTests.swift` (new) —
      `oneContainerServesBothStores`: a row written through one store is visible to the other, and
      both report the identical container. — design D6 (no spec delta; success criterion 4).
- [x] 5.2 **RED** same file — `aStoreThatCannotBeOpenedGivesBothStoresTheSameReason`: point at a path
      blocked by a regular file where the directory must go; expect both stores
      `.unavailable(reason:)` with the same reason and **no throw**. — design D6.
- [x] 5.3 **GREEN** `Sources/Persistence/MetadataStore.swift:65` — widen
      `private convenience init(unavailable:)` to internal so `LocalStores` can fold one error into
      both stores.
- [x] 5.4 **GREEN** create `Sources/Persistence/LocalStores.swift` —
      `@MainActor public struct LocalStores { public let metadata: MetadataStore; public let history: HistoryStore; public init(at url: URL = PersistenceContainer.defaultURL()) }`.
      Opens **one** `PersistenceContainer.onDisk(at:)` and injects it into both `init(container:)`;
      an open failure folds into both stores' `.unavailable(reason:)`. Keep both `init(at:)`
      convenience initializers for tests. M3-1's services store joins here rather than opening a third.
- [x] 5.5 **Wire** `cellar/cellarApp.swift` — `:50` becomes `@State private var metadata: MetadataStore`
      (no inline default); in `init()` (`:60-66`) build `let stores = LocalStores()` and seed both
      `_metadata` and `_history` from it, dropping the standalone `HistoryStore()` at `:63`. Verified
      by `xcodebuild build` plus **manual step 9.1(a)** — a package test cannot see `cellarApp`, and
      a cross-target source scan was rejected by design. **Commit 5.**

## Phase 6: Note draft commits on a package switch — D7 (item #5)

- [x] 6.1 **RED** `Tests/PersistenceTests/NoteDraftTests.swift` (new) — three tests:
      `anEditedDraftOwesAWriteWhenTheShownPackageChanges`, `anUnchangedDraftOwesNoWrite`,
      `anEmptiedDraftOwesAWriteThatClearsTheNote` (pending write `== ""`). — design D7 / settled Q2.
- [x] 6.2 **GREEN** create `Sources/Persistence/NoteDraft.swift` — `Sendable, Equatable` value with
      `init(_:)`, `static func starting(from stored: String?)`, and
      `func pendingWrite(against stored: String?) -> String?` (`nil` = owes nothing). Pure; no store
      reference.
- [x] 6.3 **Wire** `cellar/Browse/PackageMetadataSection.swift` — `onChange(of: entry.id)` (`:56`)
      commits against **`oldValue`** before resetting the draft (the closure's `oldValue` is the only
      place the departing package's identity still exists — `stored` already reads the new one), then
      resets via `NoteDraft.starting(from:)`. Correct the `:26-27` doc comment: a multiline
      `TextEditor` has **no** `onSubmit`; the real triggers are focus loss and a package change. The
      view keeps layout only. Verified by `xcodebuild build` plus **manual step 9.1(b)**. **Commit 6.**

## Phase 7: Bulk selection in displayed order — D9 (item #7, `installed-inventory`)

- [x] 7.1 **RED** `Tests/BrewClientTests/InstalledSectionsTests.swift` (new) —
      `theDisplayedOrderIsOutdatedThenSelfUpdatingThenTheRest`. — design D9.
- [x] 7.2 **RED** same file — `bulkAddEntersTheSelectionInDisplayedOrderNotInventoryOrder`: inventory
      `git, pcre2, iterm2` displaying as `iterm2, git, pcre2`; a one-shot bulk add reports
      `iterm2, git, pcre2`. — sc *"A bulk add enters the selection in displayed order"*.
- [x] 7.3 **GREEN** create `Sources/BrewClient/InstalledSections.swift` —
      `public struct InstalledSections: Sendable, Equatable { init(entries:outdatedIDs:); let outdated, selfUpdating, rest: [PackageEntry]; var displayed: [PackageEntry] { outdated + selfUpdating + rest } }`.
      One projection read twice — the `upgradableIDs` precedent (II14).
- [x] 7.4 **Wire** `cellar/Installed/InstalledListView.swift` — replace the private `outdated` /
      `selfUpdating` / `rest` computeds (`:185-202`) with one `InstalledSections`; the three
      `Section`s at `:56-77` render from it, and `reconcileOrder` at `:117` maps over
      `sections.displayed` instead of `entries`. Section **titles stay exactly as rendered today**
      (Outdated → Updates itself → All packages / Installed on request) — the spec deliberately does
      not name them. Verified by `xcodebuild build` plus **manual step 9.1(c)**. **Commit 7.**

## Phase 8: Test integrity (item #8)

- [x] 8.1 `Tests/PersistenceTests/HistoryRecorderTests.swift:214` — amend
      `aStoredRowCannotBecomeACommand` with a per-file **positive anchor**
      (`#expect(source.contains("HistoryEntry"))`) before the four negative assertions, so an
      unresolved path or an over-eager comment strip fails instead of passing vacuously. Run once
      against a deliberately wrong filename to prove the anchor bites, then revert that probe.
      **Commit 8.**
      **Probe recorded**: the stronger of the two failure modes was used — `declarations(of:)` was
      temporarily made to return `""` (an over-eager comment strip; a wrong *filename* already
      throws out of `String(contentsOf:)`). The amended test then failed with three issues, one per
      scanned file: `Expectation failed: (source → "").contains("HistoryEntry")`. Before the
      amendment that same emptied scan passed all four negative assertions silently. Probe reverted.

## Phase 9: Verification (no commit of its own unless a fix is needed)

- [x] 9.1 **Manual verification — reserved for the orchestrator, leave unchecked.** Four steps, run
      against a `xcodebuild build` product after Phase 8:

      **Executed 2026-08-03 (orchestrator + user), all four steps PASS with one honest caveat on (a).**
      (a) PASS with partial evidence: the before-launch `stat` was not captured (the app was launched
      before this task's exact steps were read). After the session: exactly **one** `.store` file
      exists under `Application Support/com.juancasanueva.cellar/` (`fd -e store` count = 1),
      `stat -f '%i %m %z'` = `451684779 1785735401 90112`, and the user exercised star + note +
      mutation + History in one session with no "could not be opened" reason anywhere and all
      surfaces surviving relaunch (user-observed). The one-container rule itself is proven headless
      by `LocalStoresTests > oneContainerServesBothStores`.
      (b) PASS: typed note text survived switching to another package and back without leaving the
      field, and survived quit + relaunch (user-observed).
      (c) PASS: a one-gesture multi-add followed by bulk submission ran operations in the order the
      list displays them, top to bottom, matching the visible rows (user-observed).
      (d) PASS as honestly scoped: the Clear flow shows a confirmation only — no blocking alert, no
      retry affordance (user-observed). The failure path is not reachable through the UI; that
      coverage rests on the headless seam tests (`HistoryStoreTests`), as planned.
      **(a) One container at launch (item #4, mandatory).** Before launching, `stat -f '%i %m %z'` the
      store file at `PersistenceContainer.defaultURL()` and list its directory. Launch, then in one
      session: star a package in Browse, write a note on it, run one mutation, open History. Expect
      all three surfaces readable, **no** "could not be opened" reason anywhere, the store file's
      **inode unchanged**, and **no second `.store` file** created beside it. Record the before/after
      `stat` output as evidence.
      **(b) Note draft survives a package switch (item #5, mandatory).** Browse → package A, type into
      Note **without leaving the field**, click package B in the list, click back to A. Expect the
      typed text present. Quit and relaunch → still present.
      **(c) Select All submits in displayed order (item #7, mandatory).** Installed, with an outdated
      package that sorts **low** in inventory order. Select all, submit a bulk upgrade. Expect the
      Activity list to show the outdated package's operation **first**, matching the rows top to
      bottom — not inventory order.
      **(d) Failed-clear inline surface (item #3, negative check — partial by design).** Forcing a
      SwiftData delete to throw is **not reliably reachable through the UI**, so the failed-clear path
      itself stays covered by the headless seam tests 4.1/4.2. What *is* reachable: make the store
      unopenable before launch (rename or `chmod 000` the store file), launch, open History, and
      confirm the reason renders **inline** on the projection's own surface with **no blocking alert
      and no retry control**. Restore the file afterwards. State this partiality explicitly in the
      verify report rather than claiming full manual coverage.
- [x] 9.2 **Full gate.** (i) `swift test --package-path Packages/CellarCore` — green, count ≥ baseline
      555 + 14 new tests; (ii) `xcodebuild build -project cellar.xcodeproj -scheme cellar -destination 'platform=macOS,arch=arm64'`
      — BUILD SUCCEEDED, zero concurrency warnings; (iii) `swiftlint --quiet` — finding count equal to
      the 0.1 baseline (**zero new**); (iv) file length — `wc -l` on `CatalogStore.swift`,
      `OperationCenter.swift`, `HistoryStore.swift`, `BrewRunner.swift`, `MutationOutcome.swift`,
      `InstalledListView.swift` and the three new files, each under SwiftLint's default 400-line
      `file_length` warning.
      **Recorded**: (i) `Test run with 571 tests in 77 suites passed after 5.293 seconds with 1 known
      issue.` — baseline 555 + **16** new tests (the plan forecast 14; the two extra are the
      relocation of item #6's classification test into its own suite, and one added `NoteDraft`
      starting-state test). (ii) `** BUILD SUCCEEDED **`, zero concurrency warnings — the only
      warning emitted is `appintentsmetadataprocessor: Metadata extraction skipped. No
      AppIntents.framework dependency found.`, which is pre-existing and not a compiler diagnostic.
      (iii) `swiftlint --quiet` = **60** findings, equal to the 0.1 baseline — zero new. (iv) `wc -l`:
      `CatalogStore` 231, `OperationCenter` 327, `HistoryStore` 234, `BrewRunner` 365,
      `MutationOutcome` 187, `InstalledListView` 210, `LocalStores` 48, `NoteDraft` 40,
      `InstalledSections` 52 — every one under 400.
- [x] 9.3 **Scope guard.** `git diff main...HEAD --name-only` must contain **no** `Package.swift`, no
      `project.pbxproj`, no new SPM target, and no services / taps / cleanup / disk-usage file. Then
      `rg 'BrewMutating|InvalidationScope|ServiceCommand|TapCommand|CleanupCommand'` over `Sources/`
      and `cellar/` must return **zero**, `forcesReSnapshot` must be unchanged (PM6 untouched), and
      the delta set must still be exactly five MODIFIED requirements with zero ADDED / REMOVED /
      RENAMED. Any hit is M3-1 scope that leaked.
      **Recorded**: 33 changed files, none matching `Package.swift`, `project.pbxproj`, or
      services / taps / cleanup / disk-usage; no new SPM target. `rg` over `Sources/` and `cellar/`
      for the five M3-1 symbols returns **zero**. `forcesReSnapshot` does not appear in the
      `MutationOutcome.swift` diff at all (PM6 untouched). The delta set is five files, each with
      exactly one `## MODIFIED Requirements` header and no ADDED / REMOVED / RENAMED header.
      **Candidate size**: `git diff main...HEAD --shortstat` = **1,808 insertions + 72 deletions =
      1,880** changed lines against the 2,000 budget. No item was dropped; no `size:exception` is
      requested. Roughly 120 lines of headroom remain for the verify report — see the apply report's
      risk note.

---

**Counts.** 34 tasks across 10 phases; 12 RED tasks naming 14 new test functions (design's 13 RED
rows), plus 1 amended scan (8.1) and 1 suite trait (1.4). 10 commits: 2 housekeeping + 8 work units.
