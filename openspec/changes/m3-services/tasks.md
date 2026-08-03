# Tasks: M3-1 — Service Management

Sources: `proposal.md`; `design.md` **revision 2** (D1–D9, settle-grace removed); `specs/` (6 files —
`service-management` NEW 12 req / 40 sc, plus `package-mutation` 4 MOD, `installation-history` 3 MOD,
`installed-inventory` 1 MOD, `operation-activity` 1 MOD, `brew-execution` 1 MOD). Baseline: `main` @
`3f2c166`. Artifact store: hybrid — **this file wins**; Engram `sdd/m3-services/tasks` is an index.

**Strict TDD is active.** Every behavioural task is preceded by its RED test task. Inner loop:
`swift test --package-path Packages/CellarCore`. App-target wiring is proven by `xcodebuild build`
plus the pre-written manual checks in Phase 16 — never by a cross-target source scan.

**This file is deliberately long.** The generic SDD 530-word cap is overridden by the project
precedent (`archive/2026-08-03-m3-hardening-prelude/.../tasks.md`) and by ruling #7180 c, which
requires every manual check to be *written before apply, not improvised at verify*. M2-3's IH6
CRITICAL is the recorded cost of the alternative.

**Two register items are already closed and get NO tasks** — verified in shipped code, not assumed:
**S1** (`BrewRunner.exit(of:)` returns `.unknownOperation`, `BrewRunner.swift:288/293`; carried at
`openspec/specs/brew-execution/spec.md:272-283`) and **W1** (no-runner submit routes through
`finish()`, `OperationCenter.swift:168-177`). The follow-up register that lists them as open is stale.

---

## Review Workload Forecast

> Forecast against **2,000** — the project's declared `review_budget_lines` (`openspec/config.yaml:7`).
> The `400-line budget risk` line is the SDD default metric, not this project's budget.

| Field | Value |
|-------|-------|
| Estimated changed lines | **~5,700–6,800** (my own task-level estimate; see arithmetic below) |
| Against project budget (2,000) | **~2.9–3.4× over** |
| 400-line budget risk | High |
| Chained PRs recommended | Yes |
| Suggested split | Recommended: PR 1 read half (Phases 0–7) → PR 2 control half (Phases 8–17). **User chose ONE PR with `size:exception`** (ruling #7182-1); not re-litigated here |
| Delivery strategy | exception-ok |
| Chain strategy | size-exception |

Decision needed before apply: No
Chained PRs recommended: Yes
Chain strategy: size-exception
400-line budget risk: High

**Why no decision is owed.** `exception-ok` means the maintainer has already accepted the
`size:exception` after being shown the two-way split and the supporting evidence (this umbrella
under-priced M2-0 by 1.67× and M2-1 by 1.82×). The exception must still be **recorded before apply
starts** (task 0.2), not requested at the ledger gate. The recommendation above stays `Yes` because
the honest forecast is high; the accepted exception resolves it, it does not lower it.

### My arithmetic, and where it disagrees with the design

| Bucket | Lines | Basis |
|---|---|---|
| `Sources/` (CellarCore) | 1,400–1,530 | 7 new files + 9 modified, sized against their models: `ServicesStore` ≈ `InstalledStore` (250), `ServicesWire` ≈ `InstalledWire`, `BrewMutating` 180, `ServiceCommand` 170, coordinator 150 |
| `cellar/` (app target) | 470–570 | 4 new views + `AppSection` + `ContentView`/`cellarApp` wiring; the four existing mutation call sites compile unchanged (D1) |
| Tests | 1,400–1,900 | ~60–70 new test functions at this suite's 20–25 lines each, plus fixtures and two new fakes |
| SDD markdown **already written and on the branch** | 1,744 **measured** | `service-management` 480 + `package-mutation` 256 + `installation-history` 180 + `installed-inventory` 135 + `operation-activity` 85 + `brew-execution` 74 + `proposal` 158 + `design` 376 |
| tasks.md + verify report | 700–1,000 | this file plus the verify report, which M3-0 proved must sit inside the budget |
| explore.md correction, register, config | 30–60 | |
| **Total** | **5,744–6,804** | |

**The design says ~3,650–5,050. I disagree, and the difference is almost entirely one accounting
question:** whether the 1,744 measured lines of proposal + design + spec deltas already committed on
the branch are inside the ledger. In M3-0 they demonstrably were — `git diff main...HEAD --shortstat`
counted them, which is how a forecast of 1,480–1,930 landed at 1,915. Add 1,744 to the design's band
and you get **5,394–6,794**, which is my band. We do not disagree about the volume of work; we
disagree about the boundary of the candidate. Use my number.

**Drop-first order if the candidate has to shrink** (the exception is accepted, so this is a
contingency, not a plan): drop **Phase 10** (VS2 `ConfirmationBox`) first — it is a register item with
no user-visible surface; then **Phase 7** (failed-clear reason) — also a register item, and its
headless seam already exists from M3-0. **Never drop Phase 11 or 14**: they carry the classification
and refresh correctness that the whole slice exists for. A further `size:exception` request is the
signal that scope leaked, not a remedy.

### Suggested Work Units

| Unit | Commit | Goal | Focused test command | Runtime harness | Rollback boundary |
|------|--------|------|----------------------|-----------------|-------------------|
| 1 | `fix(brew-process): stop ANSI at the source with HOMEBREW_NO_COLOR` | no ESC byte survives capture | `swift test --package-path Packages/CellarCore --filter "EnvironmentTests\|BrewIntegrationTests"` | **MV-11** | `BrewEnvironment.swift` + its two suites |
| 2 | `feat(brew-client): decode the services list and info payloads tolerantly` | seven statuses + catch-all, null keys absent | `swift test --package-path Packages/CellarCore --filter ServicesDecodeTests` | MV-9 (fixture-driven) | `ServicesWire.swift` + fixtures |
| 3 | `feat(brew-client): read services through constant and single-named argv` | exact argv, no `--all` | `swift test --package-path Packages/CellarCore --filter ServicesPayloadTests` | N/A — headless-provable | `ServicesPayloadSource.swift` |
| 4 | `feat(brew-client): hold services state with last-good survival` | store parity with `InstalledStore` | `swift test --package-path Packages/CellarCore --filter ServicesStoreTests` | N/A — headless-provable | `ServicesStore.swift` |
| 5 | `feat(brew-client): poll services only while the surface is visible` | zero spawns while hidden | `swift test --package-path Packages/CellarCore --filter ServicesRefreshTests` | **MV-2** | `ServicesRefreshCoordinator.swift` |
| 6 | `feat(services): show the services list, detail and log locations` | the read surface | `xcodebuild build …` (view code) | **MV-1, MV-5, MV-9, MV-10** | `cellar/Services/*` + `AppSection`/`ContentView` hunks |
| 7 | `fix(persistence): keep a failed clear's reason across the next reload` | reason survives a keystroke | `swift test --package-path Packages/CellarCore --filter HistoryStoreTests` | N/A — failure path not UI-reachable | `HistoryStore` sticky-reason hunk |
| 8 | `refactor(brew-client): generalize the mutation spine behind BrewMutating` | second family, six package cases intact | `swift test --package-path Packages/CellarCore --filter "MutationCommandTests\|BrewMutatingTests"` | N/A — headless-provable | `BrewMutating.swift` + the `MutationCommand` extension |
| 9 | `feat(brew-client): refresh only the state domains a command invalidates` | zero inventory probes per service toggle | `swift test --package-path Packages/CellarCore --filter "MutationGatesTests\|InstalledRefreshTests"` | **MV-8** | `MutationGates` + `OperationCenter.init` hunk |
| 10 | `fix(brew-client): close the pending-confirmation setter` | no external writer | `swift test --package-path Packages/CellarCore --filter ConfirmationBoxTests` | N/A — test-only surface | `ConfirmationBox` + the computed getter |
| 11 | `feat(brew-client): classify service outcomes from output markers` | exit 0 ≠ state change | `swift test --package-path Packages/CellarCore --filter "ServiceCommandTests\|ServiceClassificationTests"` | **MV-4** | `ServiceCommand.swift` + `.noChange` hunks |
| 12 | `feat(brew-client): submit service verbs one per service, guarded` | no contradictory pair | `swift test --package-path Packages/CellarCore --filter ServiceSubmissionTests` | **MV-3, MV-6** | `OperationCenterServices.swift` |
| 13 | `feat(persistence): record service verbs with a null package identity` | one entry per verb | `swift test --package-path Packages/CellarCore --filter "ServiceHistoryTests\|HistoryRecordingTests"` | **MV-7** | verb vocabulary + recorder hunks |
| 14 | `feat(services): wire the row controls to the guarded submit path` | poll suppressed, one refresh at terminal | `swift test --package-path Packages/CellarCore --filter ServicesRefreshTests` | **MV-2, MV-4, MV-12** | `ServiceControls.swift` + coordinator terminals hunk |
| 15 | `docs(sdd): reconcile the spec headers, register and explore doc` | no stale claim survives | N/A — docs only | N/A — no runtime surface | markdown only |

Phases are **sequential**. Inside a phase, RED strictly precedes its GREEN. Phases 1–7 are
file-disjoint from Phases 8–14 apart from the two hunks named at the boundary below.

---

## SPLIT BOUNDARY — read half ends after Phase 7

The user chose one PR. **This ordering keeps the two-way split live until apply begins**, so the
decision can still be reversed at zero replanning cost.

- **Read half = Phases 0–7** → `m3-services-read` (≈2,600–3,100 incl. its share of markdown).
- **Control half = Phases 8–17** → `m3-services-control` (≈3,100–3,700).

If the split is taken, exactly four things must move with it — nothing else:

1. **The `service-management` delta splits too.** Read half keeps SM1, SM2, SM3 (visibility clauses
   only), SM9, SM11, SM12. Control half takes SM4, SM5, SM6, SM7, SM8, SM10 and the SM3 sentence
   *"Polling MUST be suppressed while a service mutation is in flight"* plus its scenario. The other
   five capability deltas are **entirely control half**.
2. **`ServicesRefreshCoordinator` ships twice**: visibility + poll in Phase 5, terminals consumer +
   mutation suppression in Phase 14.
3. **`ServiceRow` ships without controls** in Phase 6; `ServiceControls.swift` is Phase 14.
4. **`brew-execution` (Phase 1) and the failed-clear fix (Phase 7) stay in the read half** — both are
   absorbed register items with no dependency on the spine.

---

## Phase 0: Baseline and delivery precondition

- [x] 0.1 Record the baseline on `3f2c166`: `swift test --package-path Packages/CellarCore` test/suite
      counts (expect **571 / 77**) and `swiftlint --quiet` finding count (expect **60**). No commit —
      this is the number task 17.1 compares against.
      **Measured 2026-08-03 on `284aab9`: 571 tests / 77 suites passed, 1 known issue; `swiftlint --quiet`
      = 60 findings. Both match the expectation exactly.**
- [x] 0.2 **Record the accepted `size:exception` before any code is written** (ruling #7182-1). The
      forecast above, this task's timestamp and the user's acceptance are the record. Apply MUST NOT
      start until this is checked.

---

# READ HALF

## Phase 1: ANSI stopped at the source — D5, `brew-execution` BE1 (defect #7179)

> **Trap, load-bearing.** `brew-execution` BE2 requires an ANSI-carrying line to be delivered
> **byte-identically**. Stripping, filtering or rewriting ESC bytes anywhere in the capture path
> would satisfy this phase's success criterion while breaking a shipped scenario. The fix is
> **environment-only**. No task below touches `LineSplitter`, `LogLine` or `SystemProcess`.

- [x] 1.1 **RED** `Tests/BrewProcessTests/EnvironmentTests.swift` —
      `theForceColourKeyIsNeverSetAtAnyValue`: `#expect(BrewEnvironment.pinned["HOMEBREW_COLOR"] == nil)`
      and `#expect(BrewEnvironment.pinned["HOMEBREW_NO_COLOR"] == "1")`. — sc *"The force-colour key is
      never set at any value"*.
- [x] 1.2 **RED** same file — `theSpawnedProcessReceivesTheSuppressionKeyAndNotTheForceKey`: drive a
      real spawn through `Tests/BrewClientTests/Fakes/RecordingProcessLauncher.swift`'s
      `BrewProcessTests` equivalent and assert the **recorded** environment, so the key cannot be
      reintroduced anywhere between `pinned` and `SystemProcess`. — sc *"Environment applied to every
      invocation"*.
- [x] 1.3 **GREEN** `Sources/BrewProcess/BrewEnvironment.swift:22` — `"HOMEBREW_COLOR": "0"` →
      `"HOMEBREW_NO_COLOR": "1"`, and correct the doc comment at `:15`, which today asserts the
      opposite of the shipped behaviour.
- [x] 1.4 **RED (integration, self-skipping)** `Tests/BrewProcessTests/BrewIntegrationTests.swift` —
      `noEscapeByteSurvivesCaptureFromARealBrewInvocation`: discover a formula via
      `brew list --formula`, run `brew info --formula <name>`, assert
      `log.allSatisfy { !$0.text.utf8.contains(0x1B) }`. Guard with `.enabled(if:)` on the real brew
      binary and tag it so the fast loop can exclude it. A fake process cannot prove anything about
      brew's own colour decision — this is the honest form of the success criterion. — sc *"No ANSI
      escape byte survives capture"*.
- [x] 1.5 `openspec/changes/m3-services-cleanup-taps/explore.md:207-208` — correct the repeated false
      claim that `HOMEBREW_COLOR=0` stops ANSI. Prose only; do not restructure the section. **Commit 1.**

## Phase 2: Services wire and decoders — D7, SM1 / SM2 (decode)

- [ ] 2.1 Create `Tests/BrewClientTests/Fakes/ServicesFixture.swift` — a `services list --json` payload
      carrying one record per status (`started`, `none`, `scheduled`, `stopped`, `error`, `unknown`,
      `other`) plus one carrying `mystery`; a record with `user` and `exit_code` both JSON **null**;
      an unparseable record; and two `services info --json` payloads — one with `log_path`,
      `error_log_path` and `pid` all null, one where `log_path == error_log_path`.
      **Fixture-first is mandatory**: the dev machine shows one service and only `none` is observable.
- [ ] 2.2 **RED** `Tests/BrewClientTests/ServicesDecodeTests.swift` (new) —
      `allSevenStatusesDecodeToTheirOwnCase`, `anUnrecognisedStatusPreservesTheRawStringAndNeverFailsThePayload`
      (three records in, three out, third reports `mystery`),
      `anUndecodableRecordIsSkippedRatherThanFailingThePayload`. — sc *"All seven statuses decode"*,
      *"An unrecognised status never fails the payload"*.
- [ ] 2.3 **RED** same file — `aNullUserAndNullExitCodeDecodeAsAbsent`: nothing thrown, no default
      substituted. — sc *"Null user and null exit code decode as absent"*.
- [ ] 2.4 **GREEN** create `Sources/BrewClient/ServicesWire.swift` — tolerant decoders plus
      `ServiceStatus { started, none, scheduled, stopped, error, unknown, other, unrecognised(String) }`.
      brew's own `other` is a real value, so the catch-all needs a different name. Decoding runs off
      the main actor.
- [ ] 2.5 **RED** same test file — `nullOptionalInfoKeysDecodeAsAbsent` and
      `identicalLogAndErrorLogPathsArePresentedOnce` (plus the differing-paths half). — sc *"Null
      optional keys decode as absent"*, *"Identical log and error-log paths are presented once"*.
- [ ] 2.6 **GREEN** same file — `ServiceDetail` with `logPaths: [URL]` **deduped and order-stable**
      (log first, error second only when different). A service declaring no log location reports
      none, never an empty or placeholder path. **Commit 2.**

## Phase 3: Payload sources and argv — D7, SM1 / SM2 (argv)

- [ ] 3.1 **RED** `Tests/BrewClientTests/ServicesPayloadTests.swift` (new) —
      `oneRefreshRecordsExactlyOneInvocationWithTheExactArgv`: assert `services list --json`, element
      for element, through `RecordingProcessLauncher`. — sc *"One invocation per refresh, with the
      exact argv"*.
- [ ] 3.2 **RED** same file — `theDetailProbeNamesExactlyOneServiceAndNeverUsesAll`: the info argv is
      `["services","info","--json", name]` with `name` as the **last, separate** element, never
      interpolated; no invocation carries `--all`. — sc *"Detail is fetched only for the selected
      service"*.
- [ ] 3.3 **GREEN** create `Sources/BrewClient/ServicesPayloadSource.swift` —
      `ServicesListPayloadSource` on the compile-time-constant `BrewCommand.read(["services","list","--json"])`
      (exactly `BrewInfoPayloadSource`'s pattern) and `ServiceInfoPayloadSource`, the codebase's only
      parameterised read argv. Closed error enum
      `ServicesError { brewUnavailable, commandFailed(status:message:), malformedPayload, cancelled }`.
- [ ] 3.4 **RED** same file — `aNonZeroExitIsAnErrorAndNeverAnEmptyList`,
      `stderrNeverEntersTheDocument`, `aBlankDocumentIsMalformed`. — copies `InstalledPayload`'s rules
      verbatim (design D7).
- [ ] 3.5 **GREEN** same source file — the pure `ServicesPayload.payload(from:exit:)` function.
      **Commit 3.**

## Phase 4: `ServicesStore` — D7, SM11 (read half)

- [ ] 4.1 **RED** `Tests/BrewClientTests/ServicesStoreTests.swift` (new) — three tests mirroring
      `InstalledStoreTests`: overlapping refreshes coalesce onto the one in flight keyed by request
      URL + invalidation mark; an older ordinal arriving after a newer one is discarded; a failed
      refresh leaves the last good list intact.
- [ ] 4.2 **RED** same file — `absentBrewGivesAnEmptyListWithGuidanceAndNoSpawn`: empty list, nothing
      thrown, `absence` carries the guidance, **zero** recorded invocations, no poll loop running. —
      sc *"Absent brew produces an empty services list with guidance"*.
- [ ] 4.3 **GREEN** create `Sources/BrewClient/ServicesStore.swift` — `InstalledStore`'s shape over
      services. **It opens no `ModelContainer`**: services state is launchd truth and persists
      nothing, so W3's one-container invariant holds *a fortiori* and
      `LocalStoresTests > oneContainerServesBothStores` remains the assertion. This is a deliberate,
      recorded deviation from the proposal's "joins `LocalStores`". **Commit 4.**

## Phase 5: Poll coordinator, visibility half — D3, SM3 (visibility clauses)

> **Trap, read from the code.** The poll must **not** be a `LoopOwner` slot. `LoopOwner.start` guards
> on `loops[id] == nil` and a slot stays claimed for the whole launch (`LoopOwner.swift:20-23,32`) —
> a poll registered there would run once and never restart after the first hide. `LoopOwner.start("services")`
> runs the **terminals consumer only** (Phase 14); the poll task is owned by the coordinator.

- [ ] 5.1 **RED** `Tests/BrewClientTests/ServicesRefreshTests.swift` (new), suite trait
      `.timeLimit(.minutes(1))` — **whole minutes only**, `.seconds(30)` traps at runtime (M3-0
      task 1.4) — `theListRefreshesOnTheFiveSecondCadenceWhileVisible`: `TestClock` from
      `Sources/CellarTestSupport/TestClock.swift`, advance 5 s three times, expect one baseline plus
      exactly three refreshes, no wall-clock sleep. — sc *"The list refreshes on the poll cadence
      while visible"*.
- [ ] 5.2 **RED** same file — `hidingTheSurfaceStopsPollingEntirely`: after `setVisible(false)`,
      advance **60 s** and expect zero further invocations; `setVisible(true)` again performs a
      baseline refresh. — sc *"Hiding the surface stops polling entirely"*. Also the threat-matrix
      **Process integration** row: *no spawn after hide across 60 s of simulated time*.
- [ ] 5.3 **RED** same file — `onlyOnePollLoopRunsPerLaunch`: visible → hidden → visible twice over,
      expect a single loop throughout. — sc *"Only one poll loop runs per launch"*.
- [ ] 5.4 **RED** same file — `aPollTickFetchesNoDetail`: with nothing selected, every recorded
      invocation is the list probe and no `services info` invocation exists. — sc *"A poll tick
      fetches no detail"*.
- [ ] 5.5 **GREEN** create `Sources/BrewClient/ServicesRefreshCoordinator.swift` — baseline on
      `setVisible(true)`, poll task created there and `cancel()`-ed **and niled** by
      `setVisible(false)`, cadence `.seconds(5)` on an injected `any Clock<Duration>`. The terminals
      consumer and mutation suppression are **Phase 14** — leave the seam, do not fake it.
      **Commit 5.**

## Phase 6: The services read surface — D8, SM9 / SM11 / SM12

- [ ] 6.1 `cellar/Shell/AppSection.swift` — add `.services` as the 5th case. Verified safe: no test
      asserts a case count on `AppSection`; `BulkSelection.Action.allCases == [.upgrade, .uninstall]`
      is the suite's only exhaustive enum assertion and is untouched here.
- [ ] 6.2 Create `cellar/Services/ServicesListView.swift` and `cellar/Services/ServiceRow.swift` —
      name plus colour-coded status. **No controls yet** (Phase 14). `onAppear`/`onDisappear` *report*
      visibility to the coordinator; they never decide it.
- [ ] 6.3 **RED** `Tests/BrewClientTests/ServicesPresentationTests.swift` (new) — the status → label +
      colour mapping as a **pure projection**, one case per status including `unrecognised`. This is
      the headless substitute for the six statuses that cannot be produced on the dev machine; MV-9
      corroborates it under a temporary fixture patch.
- [ ] 6.4 **RED** same file — `aChangedStatusReplacesThePreviousOne` (no stale status retained) and a
      structural assertion that the services surface declares **no** notification request, no
      permission prompt, no badge and no blocking alert. — sc *"A service that dies is shown as failed
      at the next poll"*, *"No notification is requested or delivered for it"* (ruling #7182-2).
- [ ] 6.5 **GREEN** create `Sources/BrewClient/LogFileOpening.swift` — the open-in-Console protocol
      seam (`rules.design`: a protocol boundary for every external dependency). The **single**
      `NSWorkspace` implementation lives in the app target, not in CellarCore.
- [ ] 6.6 Create `cellar/Services/ServiceDetailView.swift` — status, user, plist `file`, deduped log
      paths, open-in-Console. Brew-absent renders `ServicesStore.absence` / `OperationCenter.unavailableGuidance`
      as read-only guidance; no new rule.
- [ ] 6.7 **Wire** `cellar/ContentView.swift` (services column) and `cellar/cellarApp.swift` (DI,
      `scenePhase` → `setVisible`). `loops.start("services")` is **Phase 14** — the terminals consumer
      does not exist yet. Verified by `xcodebuild build` plus manual steps **MV-1, MV-5, MV-10**.
      **Commit 6.**

## Phase 7: A failed clear's reason survives the next reload — D6 (a), register top item

> The defect: `HistoryStore.search` (`:83-84`) reloads on every keystroke, and `reload()` ends with an
> unconditional `availability = .available` (`:170`), so a failed clear's reason is erased by the next
> character the user types.

- [ ] 7.1 **RED** `Tests/PersistenceTests/HistoryStoreTests.swift` —
      `aFailedClearReasonSurvivesASearchDrivenReload`: fail a clear through the M3-0 injected clear
      seam, then set `search` (triggering the `didSet` reload), and expect **both** the
      `.unavailable(reason:)` availability and `lastError` still present afterwards.
- [ ] 7.2 **RED** same file — `aSuccessfulAppendOrClearLeavesNoStaleFailureReason`.
- [ ] 7.3 **GREEN** `Sources/Persistence/HistoryStore.swift` — a private sticky failure reason set by
      `clearAll()`'s catch; `reload()` ends with `availability = sticky.map(.unavailable) ?? <fetch outcome>`
      instead of the unconditional `.available` at `:170`; a successful `append`/`clearAll` clears it.
      **Commit 7.**

---

# === SPLIT BOUNDARY === everything below is the control half

---

## Phase 8: `BrewMutating`, `AnyBrewMutation`, `InvalidationScope` — D1, D2, `package-mutation` PM1

- [ ] 8.1 **RED** `Tests/BrewClientTests/BrewMutatingTests.swift` (new) —
      `anotherFamilyEntersTheSpineWithoutBecomingACaseOfTheMutationCommandType`: submit a non-package
      conformer through the spine, then assert `MutationCommand` still carries exactly the six package
      commands, and that the submitted command was still projected with its argv, its verb and its
      terminal outcome. — PM1 sc *"Another family enters the spine without becoming a case of this
      type"*.
- [ ] 8.2 **RED** same file — `anErasedMutationCarriesOnlyProjectionsAndCompareByValue`: build
      `AnyBrewMutation` from two equal and two differing conformers; assert synthesized `==` holds and
      that **nothing** can be parsed back out of it (no case payload to recover). This strengthens the
      shipped "nothing is parsed back out of a command" property rather than weakening it.
- [ ] 8.3 **GREEN** create `Sources/BrewClient/BrewMutating.swift` — the `Sendable`-only protocol
      (`arguments`, `verb`, `packageID`, `requiresConfirmation`, `invalidates`, `classify`), its
      default `displayCommand` / `brewCommand` / `classify` (today's logic **verbatim**), the
      `AnyBrewMutation` erased value, and `InvalidationScope` as a `Sendable, Hashable` `OptionSet`
      with `installedInventory` (1<<0) and `services` (1<<1) only — taps and disk usage are reserved
      by comment, **not declared**. No `Equatable`/`Hashable` `Self`-requirement: it would make the
      protocol unusable as a stored property and break `ConfirmationRequest: Equatable` and its four
      existing assertions.
- [ ] 8.4 **GREEN** `Sources/BrewClient/MutationCommand.swift` — add
      `extension MutationCommand: BrewMutating { var invalidates: InvalidationScope { .installedInventory } }`
      and **nothing else**.
- [ ] 8.5 **GREEN** `Sources/BrewClient/OperationCenter.swift`, `OperationCenterBulk.swift`,
      `ActivityItem.swift` — `submit(_ command: some BrewMutating, versions:)` and
      `request(_ commands: [some BrewMutating])` are **generic, not existential**, so every app-target
      call site (`MutationMenu.swift:83-84`, `InstalledListView`, `ActivityBar`, `BrowseView`)
      compiles **unchanged**. `ActivityItem.command` and `ConfirmationRequest.command`/`additional`
      store `AnyBrewMutation`.
- [ ] 8.6 **RED** `Tests/BrewClientTests/MutationCommandTests.swift` — extend the existing VS1-style
      structural scan over `Sources/BrewClient/*Command.swift` with the positive anchor and the new
      structural rule: *a conformer's `arguments` may contain only literal verb/flag enum raw values
      plus tokens taken from a validated wrapper*. Keep the M3-0 lesson from task 8.1 — the scan must
      assert something positive first, or it passes vacuously. **Commit 8.**

## Phase 9: Scoped invalidation — D2, PM6 / II10 / IH7

> **The finding that makes this cheap:** `InstalledChangeObserving.swift` needs **zero edits**.
> Scoping falls out of `MutationGates` never calling `begin()` on the installed gate for a command
> that does not declare `.installedInventory` — so `InstalledMutationGate.isMutating` stays false
> (no suppression) and its `terminals` stream never fires (no forced re-snapshot). Task 9.7 asserts
> that file is byte-unchanged. **No settle-grace, no `isSettling`** — see Phase 15.

- [ ] 9.1 **RED** `Tests/BrewClientTests/MutationGatesTests.swift` (new) —
      `aCommandDeclaringTheInstalledSetRefreshesItExactlyOnceAtEveryTerminal`: success, non-zero exit,
      typed busy failure and cancellation, each forcing exactly one re-snapshot. This is the
      carried-forward PM6 invariant and must stay green. — PM6 sc 1–3.
- [ ] 9.2 **RED** same file — `aCommandThatDoesNotDeclareTheInstalledSetTakesNoInventorySnapshot`:
      zero `brew info --installed --json=v2` invocations across successful, failed **and** cancelled
      terminals, and exactly one refresh of each domain it *did* declare. — PM6 sc 4–5,
      `service-management` sc *"A successful service verb refreshes services once and the inventory
      never"* / *"A failed or cancelled service verb still refreshes services once"*, II10 sc *"An
      operation that does not invalidate the installed set forces no re-snapshot"*.
- [ ] 9.3 **RED** `Tests/BrewClientTests/InstalledRefreshTests.swift` —
      `externalSignalsAreNotSuppressedByANonInvalidatingOperation`: a change signal emitted while a
      services command runs is answered after the quiet window, without waiting for that operation. —
      II10 sc *"External signals are not suppressed by a non-invalidating operation"*.
- [ ] 9.4 **RED** `Tests/BrewClientTests/OperationCenterHistoryTests.swift` —
      `aFailingRecorderChangesNeitherTheOutcomeNorThePerDomainRefreshCounts` for a non-package
      operation: identical outcome, exactly one refresh per declared domain and none for any it did
      not declare, nothing thrown. — IH7 sc 3, OA6 sc *"A failing recorder does not change what the
      queue reports"*.
- [ ] 9.5 **GREEN** `Sources/BrewClient/BrewMutating.swift` — add `MutationGates`, mapping scope →
      gate and beginning/ending **only the intersecting** gates. The services gate is a **second
      instance of the shipped `InstalledMutationGate` type**, not a new type — it is already a depth
      counter plus a `terminals` stream with nothing installed-specific in its body. The rename it
      deserves is deliberately **not** done here (public API, test call sites, buys no behaviour); the
      naming debt is registered in task 15.4, not hidden.
- [ ] 9.6 **GREEN** `Sources/BrewClient/MutationOutcome.swift` and `OperationCenter.swift` — **delete**
      `MutationOutcome.forcesReSnapshot`; what a command invalidates is a property of what ran, not of
      how it ended. `OperationCenter.init(gates:…)` is the new form; keep `init(gate:)` as a
      convenience building `[(.installedInventory, gate)]` so every current test and the app's
      composition root compile unchanged.
- [ ] 9.7 **Scope guard** — `git diff main -- Packages/CellarCore/Sources/BrewClient/InstalledChangeObserving.swift`
      must be **empty**. Any hunk there means the settle-grace crept back in. **Commit 9.**

## Phase 10: `ConfirmationBox` — D6 (b), register item VS2

- [ ] 10.1 **RED** `Tests/BrewClientTests/ConfirmationBoxTests.swift` (new) —
      `pendingConfirmationHasNoSetterAtAll`: a structural scan proving `OperationCenter.pendingConfirmation`
      is a computed getter with no setter — strictly stronger than the `private(set)` VS2 asked to
      restore. Anchor the scan positively first (M3-0 task 8.1).
- [ ] 10.2 **RED** same file — `requestingAndConfirmingStillPropagatesThroughTheNestedObservable`:
      `request` → `confirm`/`decline` still drive the same observable transitions, so the sheet still
      updates.
- [ ] 10.3 **GREEN** `Sources/BrewClient/OperationCenter.swift` — a small `@Observable ConfirmationBox`
      held `@ObservationIgnored private let`; `pendingConfirmation` becomes a computed getter over it.
      Observation propagates through the nested observable read. **Commit 10.**

## Phase 11: `ServiceCommand` and marker classification — D4, D9, SM4–SM7, PM4

> **The decision most deserving adversarial review in this slice** is task 11.7: the marker pass reads
> **stdout**, where `MutationOutcome`'s shipped rule is stderr-only precisely so a package's build
> script cannot change what the user is told. The mitigation is structural — the marker pass is
> **family-owned** (`ServiceCommand` overrides `classify`; the protocol default is untouched), so it
> cannot reach `install`/`upgrade`. Task 11.6 is the test that makes that claim falsifiable.

- [ ] 11.1 **RED** `Tests/BrewClientTests/ServiceCommandTests.swift` (new) —
      `anUnsafeServiceNameIsRejectedAtConstructionAndBuildsNoArgv`, parameterized over a name with a
      leading `-`, an empty name, whitespace, `;`, `$(…)` and a name equal to `--all`. Each rejected
      at construction, **no argv built**. — threat matrix, *Subprocess argument composition*.
      `ServiceTarget` is expressed over `MutationName.isSafe` (`MutationCommand.swift:104`) exactly as
      `PackageTarget` is; that stays the single gate.
- [ ] 11.2 **RED** same file — `eachVerbProducesItsExactArgv` (`services start atuin`,
      `services stop atuin`, `services restart atuin`, `services run atuin`);
      `noServiceArgvEverContainsAll`; `killAndStopKeepAreNotOffered`. — SM4 sc 1–3.
- [ ] 11.3 **RED** same file — `theRowControlSurfaceIsExactlyTheFiveEnumeratedControls`:
      `ServiceRowControl.allCases == [.start, .run, .stop, .restart, .copyCommand]`, the
      `ActivityItem.Control` / `HistoryRecord.Control` idiom, so *"no hidden default"* is a claim about
      the whole surface rather than an unwritten omission. — SM5 sc *"Neither action is a hidden
      default"* (ruling #7182-3).
- [ ] 11.4 **GREEN** create `Sources/BrewClient/ServiceCommand.swift` — `ServiceTarget` plus
      `enum ServiceCommand: Sendable, Equatable, BrewMutating { case start/run/stop/restart(ServiceTarget) }`.
      `arguments` = `["services", <verb>, target.name]`; **`--all` is unrepresentable** because no case
      omits a target. `invalidates` = `.services`; `packageID` = `nil` (ruling #7180 a);
      `requiresConfirmation` = **false** for all four — recorded, not silent: none destroys anything,
      each is reversible in one click, and start-vs-run is already an explicit user choice.
- [ ] 11.5 **RED** `Tests/BrewClientTests/ServiceClassificationTests.swift` (new), fixture `LogLine`
      arrays — `aColdStartIsClassifiedAsStarted`;
      `aStartOnAnAlreadyRunningServiceIsClassifiedFromTheMarkerNotTheExitCode` (exit **0**, stdout
      ``Service `atuin` already started, use …``, no `Successfully` line → `.noChange`, not a failure);
      `aStopOnAnAlreadyStoppedServiceIsClassifiedFromItsStderrWarning` (exit **0**, stderr
      ``Warning: Service `atuin` is not started.`` → `.noChange`);
      `anUnmatchedOutcomeIsNeverASuccess` (non-zero + no marker → `.failed` with the log verbatim;
      exit 0 + no marker → not reported as a state change that did not happen). — SM6 sc 1–4.
- [ ] 11.6 **RED** same file — `packageClassificationIsByteIdentical` (a regression anchor over the
      existing `ClassificationTests` cases) and
      `aPayloadContainingAServiceMarkerCannotReclassifyAnInstall` (feed `already started, use` into an
      install's log; classification unchanged). — threat matrix, *Untrusted subprocess payload as
      classification input*.
- [ ] 11.7 **GREEN** `Sources/BrewClient/MutationOutcome.swift` — add exactly one case, `.noChange`
      (`isSuccess == false`, `isFailure == false` — the `.cancelled` shape; `summaryLabel` `"No
      change"`). Cost is four compiler-enforced exhaustive switches. Rejected and recorded: an
      associated value on `.succeeded` (breaks `==` across many shipped tests); a display-only note
      (would leave the durable history saying "Done" about a no-op, which is a lie). Then override
      `classify` **on `ServiceCommand` only**: consult its own markers on exit 0 first, then fall
      through to the protocol default. Markers match with `line.contains(<interior invariant>)`,
      never anchored and never whole-sentence, because brew interpolates the service name into every
      one; `"Successfully started"`/`"Successfully stopped"` are **corroboration only**, never the
      sole success test.
- [ ] 11.8 **RED** same file — `aRootDomainWarningOnAZeroExitIsASuccessNotAPrivilegeFailure` and
      `aRejectedBootstrapIsAGenericFailureWithItsLogIntactAndNoRetry`. `.needsPrivileges` only when
      the exit is **non-zero** and the marker is present; the exact bootstrap signature is unprobed
      (U5 residual), so the default degrades to a generic failure with the output on screen. — SM7
      sc 1–2, PM4 sc *"A non-fatal privilege warning on a successful run is not a sudo failure"*;
      threat matrix, *Privilege boundary*.
- [ ] 11.9 **RED** same file — `nothingParsedFromBrewsOutputReachesAnArgv`: trace every value the
      classification surface extracts and assert none builds, extends or modifies an argv. — SM6 sc 5.
- [ ] 11.10 **GREEN** `Sources/Persistence/SwiftDataHistoryRecorder.swift` — map `.noChange` to
      `(raw: "noChange", exitStatus: 0)`. **Commit 11.**

## Phase 12: The services submit path and the duplicate guard — D6 (c), SM8 / SM10, PM7

- [ ] 12.1 **RED** `Tests/BrewClientTests/ServiceSubmissionTests.swift` (new) —
      `aSecondOperationForTheSameServiceIsRefusedWhileOneIsInFlight` (no second operation enqueued, no
      process spawned); `aDifferentServiceIsNotBlocked`;
      `theGuardIsReleasedAtTheTerminalOutcome` across succeeded, failed **and** cancelled. — SM10
      sc 1–3.
- [ ] 12.2 **RED** same file — `actingOnSeveralServicesEnqueuesOneOperationEachInOrder`: `atuin`,
      `postgresql`, `redis` chosen in that order produce exactly three operations with those argvs, in
      that order. — SM4 sc *"Acting on several services enqueues one operation each, in order"* (M2
      fan-out ruling, PM2 sc2).
- [ ] 12.3 **RED** same file — `absentBrewSpawnsNothingForAnyOfTheFourVerbs`, also for an invalid
      configured path: nothing thrown, the affordance reports itself unavailable with the rejection
      reason as guidance. — SM11 sc 2, PM7 sc *"A non-package family is equally unavailable when brew
      is absent"*.
- [ ] 12.4 **RED** same file — `theInstalledBulkVocabularyIsUnchanged`:
      `BulkSelection.Action.allCases == [.upgrade, .uninstall]`, still exactly two, no service verb.
      This assertion is load-bearing for `installed-inventory` II13 sc4 and must not be relaxed. —
      SM4 sc 5.
- [ ] 12.5 **GREEN** create `Sources/BrewClient/OperationCenterServices.swift` — the services submit
      path plus `ServiceSubmissionGuard`, keyed on `ServiceTarget.name`, **on this path only**. A
      second services command for a name with a non-terminal one already in flight returns that
      existing `ActivityItem` instead of queueing an opposite operation. Explicitly services-scoped:
      the general M2-2 #7 dedup rule stays deferred, and `brew-execution` still permits duplicate
      submissions of the same command in general. **Commit 12.**

## Phase 13: History for the four verbs — `installation-history` IH1 / IH5, `operation-activity` OA6

> **VS4 (clock seam for `HistoryDraft.date`) is NOT adopted** (D6). No assertion below needs a
> deterministic timestamp — the claims are "exactly N entries", "null package identity", "typed verb"
> and "exact argv". Do not add the seam speculatively; it stays open on the register (task 15.4).

- [ ] 13.1 **RED** `Tests/BrewClientTests/ServiceHistoryTests.swift` (new), over
      `Tests/BrewClientTests/Fakes/OperationCenterHarness.swift` —
      `eachServiceVerbWritesOneEntryWithANullPackageIdentity`: four operations → exactly four entries,
      each with its own verb, its outcome and its exact argv; every one carrying a **null** package
      identity, no version-from, no version-to, and none storing `atuin` as a package identity. —
      IH1 sc 5, OA6 sc *"An operation with no package identity records exactly one entry"*.
- [ ] 13.2 **RED** same file — `repeatedTogglingAppendsOneEntryPerOperation`: five start/stop pairs →
      exactly ten entries in submission order, nothing collapsed, deduplicated or netted out. — IH1
      sc 6. The chatty-history cost is accepted and recorded (ruling #7180 a), not papered over.
- [ ] 13.3 **RED** `Tests/PersistenceTests/HistoryStoreTests.swift` —
      `aNullPackageServiceEntryIsFindableByVerbAndByItsArgv`: searching `STOP` and then `atuin` each
      returns only the service entry, and it is present in the unfiltered newest-first projection. —
      IH5 sc 5.
- [ ] 13.4 **GREEN** the verb vocabulary — `verb` = `"serviceStart" | "serviceRun" | "serviceStop" |
      "serviceRestart"`, camelCase on the `upgradeAll` precedent and **namespaced** so an IH5 search
      for "start" cannot collide with a package verb. Update `Sources/BrewClient/HistoryRecording.swift`
      and `Sources/Persistence/SwiftDataHistoryRecorder.swift` for the null-package draft form.
      **Commit 13.**

## Phase 14: Poll control half and the row controls — D3, D8, SM3 (suppression) / SM8

- [ ] 14.1 **RED** `Tests/BrewClientTests/ServicesRefreshTests.swift` —
      `pollingIsSuppressedWhileAServiceMutationIsInFlight`: advance the `TestClock` past several
      intervals before the terminal; expect **zero** poll refreshes while in flight and **exactly
      one** refresh at the terminal, not duplicated by the poll. — SM3 sc 4.
- [ ] 14.2 **RED** same file — `aFailedOrCancelledServiceVerbStillForcesExactlyOneServicesRefresh`,
      and zero inventory re-snapshots in both cases. — SM8 sc 2.
- [ ] 14.3 **GREEN** `Sources/BrewClient/ServicesRefreshCoordinator.swift` — the terminals consumer
      (forced refresh at every service-mutation terminal) and suppression while
      `serviceGate.isMutating`.
- [ ] 14.4 **Wire** `cellar/Services/ServiceControls.swift` (new) — all four verbs as **separately
      labelled, separately invoked** controls, each label stating which it does ("Start at login" vs
      "Run once"), plus copy-command. `cellar/cellarApp.swift` gains `loops.start("services")` running
      the terminals consumer only — **not** the poll (see the Phase 5 trap). Verified by
      `xcodebuild build` plus manual steps **MV-2, MV-3, MV-4, MV-6, MV-12**. **Commit 14.**

## Phase 15: Reconciliation — specs, register, docs

- [ ] 15.1 **PM6 is RETITLED, not merely re-bodied.** Old title: *"Every terminal outcome forces one
      re-snapshot"*. New title: *"Every terminal outcome forces one refresh of each state domain the
      command invalidates, and cancel is reported honestly"*. The archive step replaces by requirement
      **NAME**, so promotion MUST be treated as a **rename-in-place**: the old-titled requirement is
      removed from `openspec/specs/package-mutation/spec.md` in the same edit that adds the new one.
      Otherwise the main spec ends up carrying **both** titles. Record this instruction inside the
      delta header so the archive agent cannot miss it.
- [ ] 15.2 **Reconcile the `package-mutation` capability header prose**,
      `openspec/specs/package-mutation/spec.md:1-12`, which still describes the old **unconditional**
      re-snapshot at every terminal outcome. That prose is **outside delta scope** and will therefore
      survive the archive untouched unless it is fixed deliberately. Same treatment for any header
      sentence in `installation-history` naming "the forced inventory re-snapshot" in the singular.
      Prose only — no requirement text, no scenario.
- [ ] 15.3 **Re-register M2-2 #6 (post-terminal FSEvents echo) as an OPEN follow-up**, with its reason
      stated: closing it requires an explicit `installed-inventory` **II10 amendment** narrowing the
      `:334-337` convergence guarantee, so a post-terminal echo can be dropped without also dropping a
      genuine external signal landing in the same window. The earlier draft's `isSettling` grace sat
      exactly where that re-snapshot fires and dropped it, and cited II10 sc5 (`:329-332`), which
      governs *in-flight* suppression — a different moment and a different guarantee. The register
      already classifies the redundant re-snapshot as **conforming, not a defect**. That is a spec
      decision, and this slice does not take it.
- [ ] 15.4 Re-register the remaining open items with their reasons: **VS3** (no XCUITest harness;
      a dedicated harness slice remains the eventual answer, funded separately); **VS4** (clock seam —
      still unneeded, see Phase 13); the **`InstalledMutationGate` naming debt** (now serving two
      domains under an installed-specific name; renaming is public-API churn that buys no behaviour);
      **U5 residual** (exact stderr/exit signature of a rejected root-domain `launchctl bootstrap` —
      a message-quality gap, not a correctness gap); and the **`services info --json <name>` cost
      question** (probed only via `--all` at n=1; the mitigation is a cache, not a redesign, because
      the fetch is already lazy and selection-keyed).
- [ ] 15.5 Mark **S1** and **W1** closed on the register, citing `BrewRunner.swift:288/293` and
      `OperationCenter.swift:168-177`. No code task exists for either. **Commit 15.**

## Phase 16: Manual verification — VS3, written now, executed at apply/verify

> **Ruling #7180 c**: these checks exist **before** apply. Do not improvise additions at verify; if a
> check proves impossible, record *why* rather than quietly dropping it.
>
> **The observability constraint, stated plainly.** The dev machine has exactly one brew service,
> `atuin`, currently status `none`. Live checks can reach **two** of the seven statuses: `none`
> (baseline) and `started` (by running the start verb). `scheduled`, `stopped`, `error`, `unknown`
> and `other` are **not producible on this machine**. They are covered headlessly by task 6.3 and
> corroborated by the one fixture-driven check, MV-9. Every check below is labelled **LIVE**,
> **FIXTURE-DRIVEN** or **HEADLESS-ONLY**.

- [ ] 16.1 **Manual verification — reserved for the orchestrator/user, leave unchecked until run.**
      Build with `xcodebuild build -project cellar.xcodeproj -scheme cellar -destination 'platform=macOS,arch=arm64'`
      and run the twelve checks below in order. Record the **actual** observation for each, not just
      PASS.

      **MV-1 (LIVE) — The services surface exists and lists real state.** Launch, select Services in
      the sidebar. *Expect*: `atuin` listed with status `none`, matching `brew services list` in
      Terminal. No error state, no empty-state placeholder.

      **MV-2 (LIVE) — Poll runs at 5 s while visible and stops entirely while hidden.**
      (a) With Services visible, open Activity Monitor filtered to `brew`. *Expect*: a short-lived
      `brew` process roughly every 5 s. (b) From Terminal run `brew services start atuin`. *Expect*:
      the row flips to `started` within ~5 s **with no user action**. (c) Hide the window (⌘H) or
      select another section, and watch Activity Monitor for 60 s. *Expect*: **zero** `brew` processes
      from Cellar in that window. (d) From Terminal run `brew services stop atuin`, then re-show
      Services. *Expect*: the row shows `none` at the baseline refresh. The "zero spawns while hidden"
      claim is proven headlessly by task 5.2; this is corroboration on the real app.

      **MV-3 (LIVE) — Start-at-login and run-once are visibly distinct, and actually differ.**
      Enumerate the controls on the `atuin` row. *Expect*: exactly five — Start at login, Run once,
      Stop, Restart, Copy command — each labelled to state what it does, and **no** single control
      that would choose between start and run on the user's behalf. Then: with atuin stopped, run
      `ls ~/Library/LaunchAgents | rg atuin` (*expect*: no match). Click **Run once**, re-run the
      `ls` (*expect*: **still no match** — run does not register). Stop it, click **Start at login**,
      re-run the `ls` (*expect*: `homebrew.mxcl.atuin.plist` now present). Stop it again to restore
      the machine.

      **MV-4 (LIVE) — Exit 0 does not mean a state change.** With atuin stopped: click Start.
      *Expect*: the Activity item reports a successful start. Click Start **again**. *Expect*: the
      summary reads **"No change"** — **not** "Done", **not** a failure, and **not** an error row.
      Then Stop (*expect*: success), and Stop **again** (*expect*: **"No change"**). Record all four
      summary labels verbatim.

      **MV-5 (LIVE) — Detail pane, and the deduped log rule.** With atuin started, select its row.
      *Expect*: status, user, and the plist `file` path, all matching
      `brew services info atuin --json` run in Terminal. Compare `log_path` and `error_log_path` in
      that JSON: if they are the **same** file, exactly **one** log location is shown; if they
      **differ**, both are shown; if both are null, the pane says there is none and shows **no** empty
      or placeholder path. Click **Open in Console**. *Expect*: Console.app opens that exact file.

      **MV-6 (LIVE) — The duplicate-submit guard.** With atuin started, double-click **Stop** as fast
      as possible. *Expect*: exactly **one** operation in the Activity list, never two, and never a
      queued start-then-stop pair. After it reaches its terminal outcome, click Stop again. *Expect*:
      it enqueues normally (the guard released).

      **MV-7 (LIVE) — History records the verbs with no package identity.** After MV-4, open History.
      *Expect*: one entry per operation submitted (four from MV-4), each showing its service verb and
      its exact argv, and **no** package name rendered as a package identity for any of them. Search
      `atuin` → only the service entries. Search `stop` → only the stop entries. Confirm nothing was
      collapsed or deduplicated: the count matches the number of clicks.

      **MV-8 (LIVE, corroboration) — A service toggle costs no inventory probe.** With Activity
      Monitor showing `brew` processes, click Start on atuin. *Expect*: the `services start`
      invocation and a `services list --json` refresh, and **no** `brew info --installed --json=v2`
      process at any point. The authoritative proof is task 9.2; this confirms it end to end.

      **MV-9 (FIXTURE-DRIVEN — temporary local patch, MUST be reverted, MUST NOT be committed) —
      All seven statuses plus the catch-all render distinctly.** Temporarily point `ServicesStore`'s
      payload source at the Phase 2 fixture, build, and open Services. *Expect*: eight rows —
      `started`, `none`, `scheduled`, `stopped`, `error`, `unknown`, `other` and `mystery` — each
      with its own label, the failure states visibly red, and the unrecognised one showing its raw
      string rather than being hidden or crashing. Screenshot as evidence. Then **revert the patch**,
      rebuild, and confirm `git status` is clean before continuing. This check exists because these
      six statuses cannot be produced on this machine; the pure mapping is proven headlessly by task
      6.3.

      **MV-10 (LIVE if reachable, otherwise HEADLESS-ONLY — record which) — Brew-absent read-only
      guidance.** If a configured-brew-path affordance is reachable in the UI, point it at a
      nonexistent path. *Expect*: the services list empty, the same read-only guidance the rest of the
      app shows (not an error state), all four controls unavailable with that guidance attached, and
      **no** `brew` process spawned. Restore the path afterwards. If no such affordance is reachable,
      **say so explicitly in the verify report** and record that this coverage rests on tasks 4.2 and
      12.3 — do not claim manual coverage that was not obtained. This is the M2-3 IH6 lesson applied.

      **MV-11 (LIVE) — No ANSI escape reaches the UI.** After any service operation, open its log in
      the Activity drawer. *Expect*: no `[34m`-style garbage anywhere. Copy the log and paste it into
      a plain-text editor, or pipe it through `od -c`. *Expect*: **no** `033` byte. The authoritative
      proof is the self-skipping integration test 1.4; this is the human-visible half.

      **MV-12 (LIVE, best-effort) — A service that dies on its own surfaces at the next poll, and
      silently.** With atuin started and Services visible, kill its process from Terminal
      (`pkill -f atuin` — note that launchd may relaunch it if the plist sets `KeepAlive`). *Expect*:
      within ~5 s the row shows brew's real status — `error` or `none`, whichever brew reports;
      record which. *Also expect, and this is the point*: **no** system notification, **no**
      notification-permission prompt, **no** badge, and **no** blocking alert at any moment. If
      launchd relaunches it too fast to observe, record that and fall back to task 6.4.

## Phase 17: Full gate and scope guard

- [ ] 17.1 **Full gate.** (i) `swift test --package-path Packages/CellarCore` — green, count ≥ the 0.1
      baseline of 571 plus the new tests; (ii)
      `xcodebuild build -project cellar.xcodeproj -scheme cellar -destination 'platform=macOS,arch=arm64'`
      — BUILD SUCCEEDED, zero concurrency warnings; (iii) `swiftlint --quiet` — finding count equal to
      the 0.1 baseline (**zero new**); (iv) file length — `wc -l` on every new file plus
      `OperationCenter.swift`, `MutationOutcome.swift`, `HistoryStore.swift` and `InstalledStore.swift`,
      each under SwiftLint's default 400-line `file_length` warning. `ServicesStore.swift` and
      `ServicesWire.swift` are the two most likely to breach — split rather than suppress.
- [ ] 17.2 **Scope guard.** `git diff main...HEAD --name-only` must contain **no** taps, cleanup or
      disk-usage file, and **no** edit to
      `Packages/CellarCore/Sources/BrewClient/InstalledChangeObserving.swift` (task 9.7). Then
      `rg 'isSettling|settleGrace'` over `Sources/` and `cellar/` must return **zero** — the deferred
      M2-2 #6 grace must not have crept back. `rg 'forcesReSnapshot'` must return **zero** (deleted in
      9.6). `BulkSelection.Action.allCases` must still be exactly two cases.
- [ ] 17.3 **Candidate size.** Record `git diff main...HEAD --shortstat` and compare it against the
      forecast band above. If it lands outside ~5,700–6,800, say so and say why — a forecast that is
      never checked against the outcome is how this project under-priced M2-0 by 1.67× and M2-1 by
      1.82×. The accepted `size:exception` covers the verify report as well.

---

**Counts.** 84 tasks across 18 phases; 44 RED tasks, 12 pre-written manual checks, 15 work-unit
commits. Split boundary after Phase 7 / commit 7.
